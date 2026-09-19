package aero.flyfun.forms.logic

import java.time.DateTimeException
import java.time.LocalDate

enum class MRZFormat { TD3, TD1 }

data class MRZScanResult(
    val surname: String,
    val givenNames: String,
    val passportNumber: String,
    val nationality: String,
    val dateOfBirth: LocalDate,
    val expiryDate: LocalDate,
    val gender: String,
    val issuingCountry: String,
    val format: MRZFormat,
)

/**
 * ICAO 9303 machine-readable-zone parser.
 *
 * Port of `Services/MRZParser.swift`; the Swift tests are the specification.
 * Pure logic - OCR (Vision on iOS, ML Kit on Android) supplies the lines.
 */
object MRZParser {

    fun parse(lines: List<String>, today: LocalDate = LocalDate.now()): MRZScanResult? {
        val trimmed = lines.map { it.trim() }
        if (trimmed.size == 2 && trimmed[0].length == 44 && trimmed[1].length == 44) {
            return parseTD3(trimmed[0], trimmed[1], today)
        }
        if (trimmed.size == 3 && trimmed.all { it.length == 30 }) {
            return parseTD1(trimmed[0], trimmed[1], trimmed[2], today)
        }
        return null
    }

    // MARK: ICAO 9303 check digit

    fun checkDigit(input: String): Int {
        val weights = intArrayOf(7, 3, 1)
        var sum = 0
        input.forEachIndexed { i, ch ->
            val value = when {
                ch == '<' -> 0
                ch.isDigit() -> ch - '0'
                ch in 'A'..'Z' -> ch - 'A' + 10
                else -> 0
            }
            sum += value * weights[i % 3]
        }
        return sum % 10
    }

    // MARK: OCR sanitization (digit-expected positions only)

    fun sanitizeDigits(s: String): String = buildString {
        for (ch in s) {
            append(
                when (ch) {
                    'O' -> '0'
                    'I' -> '1'
                    'B' -> '8'
                    'S' -> '5'
                    'G' -> '6'
                    'Q' -> '0'
                    else -> ch
                }
            )
        }
    }

    /**
     * When the checksum fails on a field that may contain letters (a passport
     * number, say), try the substitutions the MRZ font makes ambiguous:
     * D/0, I/1, B/8, S/5, G/6, Z/2.
     */
    fun correctField(field: String, expectedCheck: Int): String? {
        val substitutions: Map<Char, List<Char>> = mapOf(
            '0' to listOf('O', 'D', 'Q'),
            '1' to listOf('I', 'L'),
            '8' to listOf('B'),
            '5' to listOf('S'),
            '6' to listOf('G'),
            '2' to listOf('Z'),
        )

        val chars = field.toCharArray()

        // Single-character corrections first - much the most common case.
        for (i in chars.indices) {
            val original = chars[i]
            val alternatives = substitutions[original] ?: continue
            for (alt in alternatives) {
                chars[i] = alt
                val candidate = String(chars)
                if (checkDigit(candidate) == expectedCheck) return candidate
            }
            chars[i] = original
        }

        // Then pairs, for cases where two characters were both misread.
        for (i in chars.indices) {
            val origI = chars[i]
            val altsI = substitutions[origI] ?: continue
            for (altI in altsI) {
                chars[i] = altI
                for (j in (i + 1) until chars.size) {
                    val origJ = chars[j]
                    val altsJ = substitutions[origJ] ?: continue
                    for (altJ in altsJ) {
                        chars[j] = altJ
                        val candidate = String(chars)
                        if (checkDigit(candidate) == expectedCheck) return candidate
                    }
                    chars[j] = origJ
                }
                chars[i] = origI
            }
        }

        return null
    }

    // MARK: Dates

    /**
     * MRZ dates are YYMMDD with no century. A birth date whose two-digit year is
     * greater than the current one must be last century; an expiry is always this
     * one.
     *
     * [today] is injectable so the century rule can be tested without the result
     * depending on when the suite runs.
     */
    fun parseMRZDate(s: String, isBirthDate: Boolean, today: LocalDate = LocalDate.now()): LocalDate? {
        if (s.length != 6) return null
        val yy = s.substring(0, 2).toIntOrNull() ?: return null
        val mm = s.substring(2, 4).toIntOrNull() ?: return null
        val dd = s.substring(4, 6).toIntOrNull() ?: return null
        if (mm !in 1..12 || dd !in 1..31) return null

        val century = if (isBirthDate) {
            if (yy > today.year % 100) 1900 else 2000
        } else {
            2000
        }

        // Swift's Calendar is lenient and rolls 31 February into March; LocalDate
        // rejects it. Rejecting is the better answer for a scanned document, and
        // no ported test depends on the rollover.
        return try {
            LocalDate.of(century + yy, mm, dd)
        } catch (_: DateTimeException) {
            null
        }
    }

    // MARK: TD3 (passport, 2x44)

    private fun parseTD3(line1: String, line2: String, today: LocalDate): MRZScanResult? {
        // Sanitize only the positions that must be digits: check digits and dates.
        val l2 = sanitizePositions(
            line2,
            setOf(9, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 43),
        )

        var passNum = substr(l2, 0, 9)
        val passExpected = digit(l2, 9)
        if (checkDigit(passNum) != passExpected) {
            passNum = correctField(passNum, passExpected) ?: return null
        }

        val dob = substr(l2, 13, 6)
        if (checkDigit(dob) != digit(l2, 19)) return null

        val expiry = substr(l2, 21, 6)
        if (checkDigit(expiry) != digit(l2, 27)) return null

        // Composite check over 0-9 + 13-19 + 21-27 + 28-42, using the corrected
        // passport number.
        val compositeInput = passNum + substr(l2, 9, 1) + substr(l2, 13, 7) +
            substr(l2, 21, 7) + substr(l2, 28, 15)
        val trailingTruncated = substr(l2, 28, 16).all { it == '<' }
        if (!trailingTruncated && checkDigit(compositeInput) != digit(l2, 43)) return null

        val (surname, givenNames) = parseNames(line1.drop(5))
        val birthDate = parseMRZDate(dob, isBirthDate = true, today = today) ?: return null
        val expiryDate = parseMRZDate(expiry, isBirthDate = false, today = today) ?: return null

        return MRZScanResult(
            surname = surname,
            givenNames = givenNames,
            passportNumber = cleanField(passNum),
            nationality = cleanCountry(substr(l2, 10, 3)),
            dateOfBirth = birthDate,
            expiryDate = expiryDate,
            gender = parseGender(substr(l2, 20, 1)),
            issuingCountry = cleanCountry(substr(line1, 2, 3)),
            format = MRZFormat.TD3,
        )
    }

    // MARK: TD1 (ID card, 3x30)

    private fun parseTD1(line1: String, line2: String, line3: String, today: LocalDate): MRZScanResult? {
        val l1 = sanitizePositions(line1, setOf(14))
        val l2 = sanitizePositions(line2, setOf(0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 29))

        val docNum = substr(l1, 5, 9)
        if (checkDigit(docNum) != digit(l1, 14)) return null

        val dob = substr(l2, 0, 6)
        if (checkDigit(dob) != digit(l2, 6)) return null

        val expiry = substr(l2, 8, 6)
        if (checkDigit(expiry) != digit(l2, 14)) return null

        val compositeInput = substr(l1, 5, 25) + substr(l2, 0, 7) + substr(l2, 8, 7) + substr(l2, 18, 11)
        if (checkDigit(compositeInput) != digit(l2, 29)) return null

        val (surname, givenNames) = parseNames(line3)
        val birthDate = parseMRZDate(dob, isBirthDate = true, today = today) ?: return null
        val expiryDate = parseMRZDate(expiry, isBirthDate = false, today = today) ?: return null

        return MRZScanResult(
            surname = surname,
            givenNames = givenNames,
            passportNumber = cleanField(docNum),
            nationality = cleanCountry(substr(l2, 15, 3)),
            dateOfBirth = birthDate,
            expiryDate = expiryDate,
            gender = parseGender(substr(l2, 7, 1)),
            issuingCountry = cleanCountry(substr(l1, 2, 3)),
            format = MRZFormat.TD1,
        )
    }

    // MARK: Helpers

    private fun substr(s: String, start: Int, length: Int): String {
        if (start >= s.length) return ""
        return s.substring(start, minOf(start + length, s.length))
    }

    private fun digit(s: String, pos: Int): Int {
        if (pos >= s.length) return -1
        return s[pos].digitToIntOrNull() ?: -1
    }

    /** Apply OCR digit sanitization only to the given positions. */
    private fun sanitizePositions(line: String, positions: Set<Int>): String {
        val chars = line.toCharArray()
        for (i in positions) {
            if (i < chars.size) chars[i] = sanitizeDigits(chars[i].toString())[0]
        }
        return String(chars)
    }

    private fun parseNames(nameField: String): Pair<String, String> {
        val parts = nameField.split("<<")
        val surname = titleCase(parts[0].replace('<', ' ').trim())
        val given = if (parts.size > 1) {
            titleCase(parts.drop(1).joinToString(" ").replace('<', ' ').trim())
        } else {
            ""
        }
        return surname to given
    }

    private fun titleCase(s: String): String =
        s.lowercase()
            .split(" ")
            .filter { it.isNotEmpty() }
            .joinToString(" ") { it.replaceFirstChar { c -> c.uppercaseChar() } }

    private fun cleanField(s: String): String = s.replace("<", "").trim()

    private fun cleanCountry(s: String): String = s.replace("<", "").trim()

    private fun parseGender(s: String): String = when (s) {
        "M" -> "M"
        "F" -> "F"
        else -> "X"
    }
}

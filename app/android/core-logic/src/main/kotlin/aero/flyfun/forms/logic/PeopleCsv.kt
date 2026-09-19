package aero.flyfun.forms.logic

import java.time.LocalDate
import java.time.format.DateTimeParseException

/** One row of a GAR-format people CSV, before it becomes storage. */
data class CsvPerson(
    val firstName: String,
    val lastName: String,
    val sex: String? = null,
    val dateOfBirth: LocalDate? = null,
    val nationality: String? = null,
    val docType: String? = null,
    val docNumber: String? = null,
    val docExpiry: LocalDate? = null,
    val docIssuingCountry: String? = null,
    val isCrew: Boolean = false,
)

class CsvImportException(message: String) : Exception(message)

/**
 * Parser for the bulk people CSV.
 *
 * Port of `Services/PeopleCSVImporter.swift`. Parsing only - the storage half
 * lives in the app layer, so this stays Android-free and testable on the JVM.
 *
 * Expected columns: First Name, Last Name, Gender, DoB, Nationality, Doc Type,
 * Doc Number, Doc Expiry, Doc Issuing State, Type. Only the names are required.
 */
object PeopleCsv {

    private val REQUIRED = listOf("first name", "last name")

    fun parse(content: String): List<CsvPerson> {
        val lines = content.split('\n', '\r')
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        val headerLine = lines.firstOrNull()
            ?: throw CsvImportException("CSV file is empty or has no header row.")

        // A UTF-8 BOM would otherwise attach itself to the first header name and
        // make "first name" unfindable. Swift's String(data:encoding:) strips it;
        // Kotlin does not.
        val headers = parseRow(headerLine.removePrefix("﻿")).map { it.lowercase().trim() }

        val missing = REQUIRED.filter { it !in headers }
        if (missing.isNotEmpty()) {
            throw CsvImportException("Missing required columns: ${missing.joinToString(", ")}")
        }

        fun col(name: String): Int? = headers.indexOf(name).takeIf { it >= 0 }

        val iFirst = col("first name")!!
        val iLast = col("last name")!!
        val iGender = col("gender")
        val iDob = col("dob")
        val iNat = col("nationality")
        val iDocType = col("doc type")
        val iDocNum = col("doc number")
        val iDocExpiry = col("doc expiry")
        val iDocState = col("doc issuing state")
        val iType = col("type")

        return lines.drop(1).mapNotNull { line ->
            val fields = parseRow(line)
            fun field(i: Int?): String? {
                if (i == null || i >= fields.size) return null
                return fields[i].trim().takeIf { it.isNotEmpty() }
            }

            val firstName = field(iFirst).orEmpty()
            val lastName = field(iLast).orEmpty()
            if (firstName.isEmpty() && lastName.isEmpty()) return@mapNotNull null

            CsvPerson(
                firstName = firstName,
                lastName = lastName,
                sex = field(iGender),
                dateOfBirth = field(iDob)?.let(::parseDate),
                nationality = field(iNat),
                docType = field(iDocType),
                docNumber = field(iDocNum),
                docExpiry = field(iDocExpiry)?.let(::parseDate),
                docIssuingCountry = field(iDocState),
                isCrew = field(iType)?.lowercase() == "crew",
            )
        }
    }

    /** `yyyy-MM-dd`; anything else is nil rather than an error, as on iOS. */
    private fun parseDate(s: String): LocalDate? = try {
        LocalDate.parse(s)
    } catch (_: DateTimeParseException) {
        null
    }

    /**
     * Dedup key, matching the Swift importer: name case-insensitive plus date of
     * birth. Two people who genuinely share both are indistinguishable here, which
     * is the same trade the iOS importer makes.
     */
    fun dedupKey(firstName: String, lastName: String, dateOfBirth: LocalDate?): String =
        "${firstName.lowercase()}|${lastName.lowercase()}|${dateOfBirth?.toString() ?: "nil"}"

    /**
     * Split parsed rows into those to import and those already present.
     *
     * Pure, so the dedup rule is testable without a database. [existingKeys] comes
     * from [dedupKey] over what storage already holds.
     */
    fun plan(parsed: List<CsvPerson>, existingKeys: Set<String>): ImportPlan {
        val seen = existingKeys.toMutableSet()
        val toImport = mutableListOf<CsvPerson>()
        var skipped = 0
        for (p in parsed) {
            val key = dedupKey(p.firstName, p.lastName, p.dateOfBirth)
            if (!seen.add(key)) {
                skipped++
            } else {
                toImport += p
            }
        }
        return ImportPlan(toImport = toImport, skipped = skipped)
    }

    data class ImportPlan(val toImport: List<CsvPerson>, val skipped: Int)

    /**
     * One CSV row, per RFC 4180: quoted fields may contain commas, and a doubled
     * quote inside a quoted field is a literal quote.
     *
     * **Deliberate divergence from the Swift original.** That implementation
     * guards its escape branch with `inQuotes && prev == "\""`, but the first
     * quote of the pair has already toggled `inQuotes` off, so the branch is
     * unreachable and `"An""na"` silently parses as `Anna`. Faithfully porting a
     * defect is not worth it; this reads the escape correctly. Rare in passport
     * names, so the practical impact on iOS is small - but it is a real bug
     * there.
     */
    private fun parseRow(row: String): List<String> {
        val fields = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false
        var i = 0

        while (i < row.length) {
            val ch = row[i]
            when {
                inQuotes && ch == '"' && i + 1 < row.length && row[i + 1] == '"' -> {
                    current.append('"')
                    i++ // consume the second quote of the pair
                }
                ch == '"' -> inQuotes = !inQuotes
                ch == ',' && !inQuotes -> {
                    fields.add(current.toString())
                    current.clear()
                }
                else -> current.append(ch)
            }
            i++
        }
        fields.add(current.toString())
        return fields
    }
}

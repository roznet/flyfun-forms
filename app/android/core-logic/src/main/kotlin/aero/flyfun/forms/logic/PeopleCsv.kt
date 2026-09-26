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
     * What an import will do, worked out before anything is written.
     *
     * Port of iOS `PeopleCSVImporter.importInto` (`1173620`). Rows are matched
     * by [dedupKey] against the people already stored and against earlier rows
     * of the same file, so someone listed once per passport becomes one person
     * with several documents. A matched row adds its document unless that
     * person already holds the number; otherwise it is skipped.
     *
     * Pure, so the rule is testable without a database; the app writes the plan.
     */
    fun plan(parsed: List<CsvPerson>, existing: List<KnownPerson>): ImportPlan {
        // The first stored person under a key takes the documents, as on iOS.
        val existingByKey = mutableMapOf<String, String>()
        val docNumbers = mutableMapOf<String, MutableSet<String>>()
        for (person in existing) {
            val key = dedupKey(person.firstName, person.lastName, person.dateOfBirth)
            existingByKey.putIfAbsent(key, person.id)
            docNumbers.getOrPut(key) { mutableSetOf() } += person.docNumbers
        }

        val newPeople = linkedMapOf<String, NewPerson>()
        val forExisting = mutableListOf<ExistingDocument>()
        var imported = 0
        var documentsAdded = 0
        var skipped = 0

        for (row in parsed) {
            val key = dedupKey(row.firstName, row.lastName, row.dateOfBirth)
            val number = row.docNumber.orEmpty()
            val hasNewDocument = number.isNotEmpty() && number !in docNumbers[key].orEmpty()
            val existingId = existingByKey[key]
            val earlier = newPeople[key]
            when {
                existingId == null && earlier == null -> {
                    newPeople[key] = NewPerson(row, if (hasNewDocument) listOf(row) else emptyList())
                    imported++
                }
                !hasNewDocument -> {
                    skipped++
                    continue
                }
                existingId != null -> {
                    forExisting += ExistingDocument(existingId, row)
                    documentsAdded++
                }
                else -> {
                    newPeople[key] = earlier!!.copy(documents = earlier.documents + row)
                    documentsAdded++
                }
            }
            if (hasNewDocument) docNumbers.getOrPut(key) { mutableSetOf() } += number
        }
        return ImportPlan(newPeople.values.toList(), forExisting, imported, documentsAdded, skipped)
    }

    /** A stored person, as far as matching an import is concerned. */
    data class KnownPerson(
        val id: String,
        val firstName: String,
        val lastName: String,
        val dateOfBirth: LocalDate?,
        val docNumbers: Set<String>,
    )

    /** A person to create from the row that introduced them, with the rows whose documents they get. */
    data class NewPerson(val person: CsvPerson, val documents: List<CsvPerson>)

    /** A row's document for a person already stored. */
    data class ExistingDocument(val personId: String, val row: CsvPerson)

    data class ImportPlan(
        val newPeople: List<NewPerson>,
        val documentsForExisting: List<ExistingDocument>,
        val imported: Int,
        val documentsAdded: Int,
        val skipped: Int,
    ) {
        /** "2 imported, 1 document added, 3 already existed." - what iOS says after an import. */
        val summary: String
            get() = buildList {
                if (imported > 0) add("$imported imported")
                if (documentsAdded > 0) add("$documentsAdded document${if (documentsAdded == 1) "" else "s"} added")
                if (skipped > 0) add("$skipped already existed")
            }.joinToString(", ").ifEmpty { "Nothing to import" }.replaceFirstChar { it.uppercase() } + "."
    }

    /**
     * The app's own vocabulary for sex: the CSV template says M/F, the person
     * editor stores Male/Female. Anything else is kept as written.
     */
    fun normaliseSex(value: String?): String? = when (value?.trim()?.uppercase()) {
        null, "" -> null
        "M", "MALE" -> "Male"
        "F", "FEMALE" -> "Female"
        else -> value.trim()
    }

    /** A person to write out, one row per document. */
    data class ExportPerson(
        val firstName: String,
        val lastName: String,
        val sex: String?,
        val dateOfBirth: LocalDate?,
        val isCrew: Boolean,
        val documents: List<ExportDocument>,
    )

    data class ExportDocument(
        val docType: String,
        val docNumber: String,
        val expiryDate: LocalDate?,
        val issuingCountry: String?,
    )

    val EXPORT_HEADER = listOf(
        "First Name", "Last Name", "Gender", "DoB", "Nationality",
        "Doc Type", "Doc Number", "Doc Expiry", "Doc Issuing State", "Type",
    )

    /**
     * The people as CSV in the same columns [parse] reads, one row per
     * document so a round trip keeps every document. Port of iOS
     * `CSVExportDocument`. Nationality is the document's issuing country: on
     * Android it derives from the document, never the person.
     */
    fun export(people: List<ExportPerson>): String {
        val rows = mutableListOf(EXPORT_HEADER)
        for (person in people) {
            val base = listOf(person.firstName, person.lastName, person.sex.orEmpty(), person.dateOfBirth?.toString().orEmpty())
            val type = if (person.isCrew) "Crew" else ""
            if (person.documents.isEmpty()) {
                rows += base + listOf("", "", "", "", "", type)
            } else {
                person.documents.forEach { doc ->
                    rows += base + listOf(
                        doc.issuingCountry.orEmpty(),
                        doc.docType,
                        doc.docNumber,
                        doc.expiryDate?.toString().orEmpty(),
                        doc.issuingCountry.orEmpty(),
                        type,
                    )
                }
            }
        }
        return rows.joinToString("\n") { row -> row.joinToString(",") { escape(it) } }
    }

    private fun escape(field: String): String =
        if (field.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) {
            "\"" + field.replace("\"", "\"\"") + "\""
        } else {
            field
        }

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

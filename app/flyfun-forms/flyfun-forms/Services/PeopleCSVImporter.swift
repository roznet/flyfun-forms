import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let commaSeparatedText = UTType(importedAs: "public.comma-separated-values-text")
}

struct CSVPerson {
    var firstName: String
    var lastName: String
    var sex: String?
    var dateOfBirth: Date?
    var nationality: String?
    var idType: String?
    var idNumber: String?
    var idExpiry: Date?
    var idIssuingCountry: String?
    var isCrew: Bool
}

struct PeopleCSVImporter {
    enum ImportError: LocalizedError {
        case noHeader
        case missingColumns([String])

        var errorDescription: String? {
            switch self {
            case .noHeader:
                return "CSV file is empty or has no header row."
            case .missingColumns(let cols):
                return "Missing required columns: \(cols.joined(separator: ", "))"
            }
        }
    }

    /// Parse GAR-format CSV into CSVPerson values.
    /// Expected columns: First Name, Last Name, Gender, DoB, Nationality,
    ///                    Doc Type, Doc Number, Doc Expiry, Doc Issuing State, Type
    static func parse(data: Data) throws -> [CSVPerson] {
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let headerLine = lines.first else { throw ImportError.noHeader }
        let headers = parseCSVRow(headerLine).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        let required = ["first name", "last name"]
        let missing = required.filter { !headers.contains($0) }
        if !missing.isEmpty { throw ImportError.missingColumns(missing) }

        func col(_ name: String) -> Int? { headers.firstIndex(of: name) }
        let iFirst = col("first name")!
        let iLast = col("last name")!
        let iGender = col("gender")
        let iDob = col("dob")
        let iNat = col("nationality")
        let iDocType = col("doc type")
        let iDocNum = col("doc number")
        let iDocExpiry = col("doc expiry")
        let iDocState = col("doc issuing state")
        let iType = col("type")

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        var result: [CSVPerson] = []
        for line in lines.dropFirst() {
            let fields = parseCSVRow(line)
            func field(_ i: Int?) -> String? {
                guard let i, i < fields.count else { return nil }
                let v = fields[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }

            let firstName = field(iFirst) ?? ""
            let lastName = field(iLast) ?? ""
            guard !firstName.isEmpty || !lastName.isEmpty else { continue }

            result.append(CSVPerson(
                firstName: firstName,
                lastName: lastName,
                sex: field(iGender),
                dateOfBirth: field(iDob).flatMap { dateFmt.date(from: $0) },
                nationality: field(iNat),
                idType: field(iDocType),
                idNumber: field(iDocNum),
                idExpiry: field(iDocExpiry).flatMap { dateFmt.date(from: $0) },
                idIssuingCountry: field(iDocState),
                isCrew: field(iType)?.lowercased() == "crew"
            ))
        }
        return result
    }

    /// Import parsed people into SwiftData, skipping duplicates by first+last+DOB.
    @discardableResult
    static func importInto(
        _ context: ModelContext,
        from data: Data
    ) throws -> (imported: Int, skipped: Int) {
        let parsed = try parse(data: data)

        let existing = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let existingKeys = Set(existing.map { personKey($0.firstName, $0.lastName, $0.dateOfBirth) })

        var imported = 0
        var skipped = 0
        for csv in parsed {
            let key = personKey(csv.firstName, csv.lastName, csv.dateOfBirth)
            if existingKeys.contains(key) {
                skipped += 1
                continue
            }
            let person = Person(firstName: csv.firstName, lastName: csv.lastName)
            person.sex = csv.sex
            person.dateOfBirth = csv.dateOfBirth
            person.nationality = csv.nationality
            person.idType = csv.idType
            person.idNumber = csv.idNumber
            person.idExpiry = csv.idExpiry
            person.idIssuingCountry = csv.idIssuingCountry
            person.isUsualCrew = csv.isCrew
            context.insert(person)
            imported += 1
        }
        return (imported, skipped)
    }

    private static func personKey(_ first: String, _ last: String, _ dob: Date?) -> String {
        let dobStr = dob.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
        return "\(first.lowercased())|\(last.lowercased())|\(dobStr)"
    }

    /// Parse a single CSV row, handling quoted fields with commas.
    private static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var prev: Character?

        for char in row {
            if char == "\"" {
                if inQuotes && prev == "\"" {
                    current.append("\"")
                    prev = nil
                    continue
                }
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
                prev = char
                continue
            } else {
                current.append(char)
            }
            prev = char
        }
        fields.append(current)
        return fields
    }
}

import Foundation
import SwiftData
import UniformTypeIdentifiers

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

    /// Import parsed people into SwiftData.
    ///
    /// People are matched by first+last name+DOB, both against existing people
    /// and against earlier rows of the same file: a person listed on several
    /// rows (one per passport or ID card) becomes one person with several
    /// documents. A matched row only adds its document when the person doesn't
    /// already hold that document number; otherwise it is skipped.
    @discardableResult
    static func importInto(
        _ context: ModelContext,
        from data: Data
    ) throws -> (imported: Int, documentsAdded: Int, skipped: Int) {
        let parsed = try parse(data: data)

        let existing = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        var people: [String: Person] = [:]
        var docNumbers: [String: Set<String>] = [:]
        for person in existing {
            let key = personKey(person.firstName, person.lastName, person.dateOfBirth)
            people[key] = people[key] ?? person
            docNumbers[key, default: []].formUnion(person.documentList.map(\.docNumber))
        }

        var imported = 0
        var documentsAdded = 0
        var skipped = 0
        for csv in parsed {
            let key = personKey(csv.firstName, csv.lastName, csv.dateOfBirth)
            let docNumber = csv.idNumber ?? ""
            let hasNewDocument = !docNumber.isEmpty && !(docNumbers[key]?.contains(docNumber) ?? false)

            let person: Person
            if let match = people[key] {
                guard hasNewDocument else {
                    skipped += 1
                    continue
                }
                person = match
                documentsAdded += 1
            } else {
                person = Person(firstName: csv.firstName, lastName: csv.lastName)
                person.sex = csv.sex
                person.dateOfBirth = csv.dateOfBirth
                person.nationality = csv.nationality
                person.isUsualCrew = csv.isCrew
                context.insert(person)
                people[key] = person
                imported += 1
            }

            if hasNewDocument {
                let doc = TravelDocument(
                    docType: csv.idType ?? "Passport",
                    docNumber: docNumber,
                    issuingCountry: csv.idIssuingCountry,
                    expiryDate: csv.idExpiry
                )
                doc.person = person
                context.insert(doc)
                docNumbers[key, default: []].insert(docNumber)
            }
        }
        return (imported, documentsAdded, skipped)
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

import Foundation
import SwiftData

/// Context describing where the scan was initiated from.
enum MRZScanContext {
    /// Scanning from a document edit page (existing person + existing document).
    case document(TravelDocument)
    /// Scanning from a person edit page (existing person, will create document).
    case person(Person)
    /// Scanning from the people list (no person context).
    case standalone
}

/// Outcome of processing an MRZ scan result against existing data.
struct MRZProcessingResult: Identifiable {
    let id = UUID()
    let scanResult: MRZScanResult
    let context: MRZScanContext
    /// Whether a document with the same number already exists.
    let duplicateDocument: TravelDocument?
    /// Whether the scanned name mismatches the context person.
    let namesMismatch: Bool
    /// People with similar names found in the database.
    let matchingPeople: [Person]
}

enum MRZResultProcessor {

    // MARK: - Process

    /// Analyze a scan result against the database and return a processing result.
    static func process(
        _ result: MRZScanResult,
        context: MRZScanContext,
        modelContext: ModelContext
    ) -> MRZProcessingResult {
        let duplicate = findDuplicateDocument(number: result.passportNumber, modelContext: modelContext, excluding: contextDocument(context))
        let mismatch: Bool
        let matches: [Person]

        switch context {
        case .document(let doc):
            mismatch = doc.person.map { !namesMatch(person: $0, result: result) } ?? false
            matches = []
        case .person(let person):
            mismatch = !person.firstName.isEmpty && !namesMatch(person: person, result: result)
            matches = []
        case .standalone:
            mismatch = false
            matches = findMatchingPeople(result: result, modelContext: modelContext)
        }

        return MRZProcessingResult(
            scanResult: result,
            context: context,
            duplicateDocument: duplicate,
            namesMismatch: mismatch,
            matchingPeople: matches
        )
    }

    // MARK: - Apply Actions

    /// Fill a document's fields from a scan result.
    static func fillDocument(_ document: TravelDocument, from result: MRZScanResult) {
        document.docNumber = result.passportNumber
        document.issuingCountry = result.issuingCountry
        document.expiryDate = result.expiryDate
        document.docType = result.format == .td1 ? "Identity card" : "Passport"
    }

    /// Fill a person's empty fields from a scan result.
    static func fillPerson(_ person: Person, from result: MRZScanResult, overwriteName: Bool = false) {
        if person.firstName.isEmpty || overwriteName {
            person.firstName = result.givenNames
        }
        if person.lastName.isEmpty || overwriteName {
            person.lastName = result.surname
        }
        if person.dateOfBirth == nil {
            person.dateOfBirth = result.dateOfBirth
        }
        if person.nationality == nil || person.nationality?.isEmpty == true {
            person.nationality = result.nationality
        }
        if person.sex == nil || person.sex?.isEmpty == true {
            switch result.gender {
            case "M": person.sex = "Male"
            case "F": person.sex = "Female"
            default: break
            }
        }
    }

    /// Create a new document from a scan result and attach it to a person.
    @discardableResult
    static func createDocument(for person: Person, from result: MRZScanResult, in modelContext: ModelContext) -> TravelDocument {
        let doc = TravelDocument()
        fillDocument(doc, from: result)
        doc.person = person
        modelContext.insert(doc)
        return doc
    }

    /// Create a new person with a document from a scan result.
    @discardableResult
    static func createPersonWithDocument(from result: MRZScanResult, in modelContext: ModelContext) -> Person {
        let person = Person()
        fillPerson(person, from: result, overwriteName: true)
        modelContext.insert(person)
        createDocument(for: person, from: result, in: modelContext)
        return person
    }

    // MARK: - Name Matching

    /// Check if a person's name matches the scan result (case-insensitive, trimmed).
    static func namesMatch(person: Person, result: MRZScanResult) -> Bool {
        let personFirst = person.firstName.lowercased().trimmingCharacters(in: .whitespaces)
        let personLast = person.lastName.lowercased().trimmingCharacters(in: .whitespaces)
        let scanFirst = result.givenNames.lowercased().trimmingCharacters(in: .whitespaces)
        let scanLast = result.surname.lowercased().trimmingCharacters(in: .whitespaces)

        // Exact match
        if personLast == scanLast && personFirst == scanFirst {
            return true
        }

        // Surname matches and first name starts with same prefix (MRZ truncates long names)
        if personLast == scanLast {
            let shorter = min(personFirst.count, scanFirst.count)
            if shorter >= 2 && personFirst.prefix(shorter) == scanFirst.prefix(shorter) {
                return true
            }
        }

        return false
    }

    /// Compute a similarity score (0.0-1.0) between a person and scan result.
    static func nameSimilarity(person: Person, result: MRZScanResult) -> Double {
        let personLast = person.lastName.lowercased().trimmingCharacters(in: .whitespaces)
        let scanLast = result.surname.lowercased().trimmingCharacters(in: .whitespaces)
        let personFirst = person.firstName.lowercased().trimmingCharacters(in: .whitespaces)
        let scanFirst = result.givenNames.lowercased().trimmingCharacters(in: .whitespaces)

        guard !personLast.isEmpty else { return 0 }

        var score = 0.0

        // Last name comparison (weighted more heavily)
        if personLast == scanLast {
            score += 0.6
        } else if personLast.hasPrefix(scanLast) || scanLast.hasPrefix(personLast) {
            score += 0.4
        }

        // First name comparison
        if personFirst == scanFirst {
            score += 0.3
        } else if !personFirst.isEmpty && !scanFirst.isEmpty {
            let shorter = min(personFirst.count, scanFirst.count)
            if shorter >= 2 && personFirst.prefix(shorter) == scanFirst.prefix(shorter) {
                score += 0.2
            }
        }

        // DOB match bonus
        if let dob = person.dateOfBirth, Calendar.current.isDate(dob, inSameDayAs: result.dateOfBirth) {
            score += 0.1
        }

        return min(score, 1.0)
    }

    // MARK: - Duplicate Detection

    /// Find an existing document with the same number, excluding a specific document.
    static func findDuplicateDocument(number: String, modelContext: ModelContext, excluding: TravelDocument? = nil) -> TravelDocument? {
        guard !number.isEmpty else { return nil }
        let predicate = #Predicate<TravelDocument> { doc in
            doc.docNumber == number
        }
        var descriptor = FetchDescriptor<TravelDocument>(predicate: predicate)
        descriptor.fetchLimit = 2
        guard let docs = try? modelContext.fetch(descriptor) else { return nil }
        return docs.first { $0.persistentModelID != excluding?.persistentModelID }
    }

    // MARK: - People Search

    /// Find people whose names are similar to the scan result.
    static func findMatchingPeople(result: MRZScanResult, modelContext: ModelContext) -> [Person] {
        let scanLast = result.surname.lowercased()
        guard !scanLast.isEmpty else { return [] }

        // Fetch all people (SwiftData doesn't support complex string predicates well)
        let descriptor = FetchDescriptor<Person>()
        guard let allPeople = try? modelContext.fetch(descriptor) else { return [] }

        return allPeople
            .map { (person: $0, score: nameSimilarity(person: $0, result: result)) }
            .filter { $0.score >= 0.4 }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map(\.person)
    }

    // MARK: - Private

    private static func contextDocument(_ context: MRZScanContext) -> TravelDocument? {
        if case .document(let doc) = context { return doc }
        return nil
    }
}

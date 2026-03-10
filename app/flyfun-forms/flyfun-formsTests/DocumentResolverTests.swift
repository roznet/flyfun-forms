import Testing
import Foundation
import SwiftData
@testable import flyfun_forms

// MARK: - In-memory SwiftData helpers

/// Creates an in-memory ModelContainer for testing (no CloudKit, no persistence).
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Person.self, TravelDocument.self, Aircraft.self, Flight.self, Trip.self,
        configurations: config
    )
}

/// Creates a Person with the given documents already attached, inserted into an in-memory context.
@MainActor
@discardableResult
private func makePerson(
    container: ModelContainer,
    firstName: String = "Zara",
    lastName: String = "Kowalski",
    documents: [(type: String, number: String, country: String?, expiry: Date?)] = []
) -> (Person, [TravelDocument]) {
    let context = container.mainContext
    let person = Person(firstName: firstName, lastName: lastName)
    context.insert(person)

    var docs: [TravelDocument] = []
    for d in documents {
        let doc = TravelDocument(
            docType: d.type,
            docNumber: d.number,
            issuingCountry: d.country,
            expiryDate: d.expiry
        )
        doc.person = person
        context.insert(doc)
        docs.append(doc)
    }
    try? context.save()
    return (person, docs)
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
}

// MARK: - Tests

@Suite("DocumentResolver")
struct DocumentResolverTests {

    // Clear any leftover user overrides before each test
    init() {
        UserDefaults.standard.removeObject(forKey: "documentPreferences")
    }

    @Test("No documents returns nil")
    @MainActor
    func noDocuments() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [])
        let result = DocumentResolver.resolve(person: person, airport: "LSGS")
        #expect(result == nil)
    }

    @Test("Single document is always returned")
    @MainActor
    func singleDocument() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Passport", number: "PP-100001", country: "XYZ", expiry: date(2030, 6, 15)),
        ])
        let result = DocumentResolver.resolve(person: person, airport: "LSGS")
        #expect(result?.docNumber == "PP-100001")
    }

    @Test("Schengen airport prefers Schengen-issued document")
    @MainActor
    func schengenPreference() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Passport", number: "PP-GBR-001", country: "GBR", expiry: date(2031, 1, 1)),
            (type: "Identity card", number: "ID-FRA-001", country: "FRA", expiry: date(2029, 6, 1)),
        ])
        // LSGS is LS prefix → Schengen → should pick FRA document
        let result = DocumentResolver.resolve(person: person, airport: "LSGS")
        #expect(result?.docNumber == "ID-FRA-001")
    }

    @Test("UK airport prefers GBR-issued document")
    @MainActor
    func ukPreference() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Identity card", number: "ID-FRA-001", country: "FRA", expiry: date(2029, 6, 1)),
            (type: "Passport", number: "PP-GBR-001", country: "GBR", expiry: date(2031, 1, 1)),
        ])
        // EGKA is EG prefix → UK → should pick GBR document
        let result = DocumentResolver.resolve(person: person, airport: "EGKA")
        #expect(result?.docNumber == "PP-GBR-001")
    }

    @Test("French airport (LF) is Schengen — picks FRA over GBR")
    @MainActor
    func frenchAirportSchengen() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Passport", number: "PP-GBR-001", country: "GBR", expiry: date(2031, 1, 1)),
            (type: "Passport", number: "PP-FRA-001", country: "FRA", expiry: date(2029, 1, 1)),
        ])
        let result = DocumentResolver.resolve(person: person, airport: "LFAC")
        #expect(result?.docNumber == "PP-FRA-001")
    }

    @Test("No region match falls back to latest expiry")
    @MainActor
    func noRegionMatchLatestExpiry() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Passport", number: "PP-EARLY", country: "XYZ", expiry: date(2028, 1, 1)),
            (type: "Passport", number: "PP-LATE", country: "ABC", expiry: date(2032, 12, 31)),
        ])
        // ZZZZ has unknown prefix → .other → no region match → latest expiry wins
        let result = DocumentResolver.resolve(person: person, airport: "ZZZZ")
        #expect(result?.docNumber == "PP-LATE")
    }

    @Test("Region match tiebreak by latest expiry")
    @MainActor
    func regionMatchTiebreakByExpiry() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Identity card", number: "ID-DEU-001", country: "DEU", expiry: date(2028, 1, 1)),
            (type: "Passport", number: "PP-FRA-001", country: "FRA", expiry: date(2032, 6, 1)),
            (type: "Passport", number: "PP-GBR-001", country: "GBR", expiry: date(2033, 1, 1)),
        ])
        // LSGS = Schengen → DEU and FRA match → FRA has later expiry
        let result = DocumentResolver.resolve(person: person, airport: "LSGS")
        #expect(result?.docNumber == "PP-FRA-001")
    }

    @Test("UK airport with no GBR document falls back to latest expiry")
    @MainActor
    func ukNoGBRFallback() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Passport", number: "PP-FRA-001", country: "FRA", expiry: date(2028, 1, 1)),
            (type: "Passport", number: "PP-USA-001", country: "USA", expiry: date(2032, 6, 1)),
        ])
        // EG airport but no GBR doc → regionMatches empty → falls back to all docs by expiry
        let result = DocumentResolver.resolve(person: person, airport: "EGLL")
        #expect(result?.docNumber == "PP-USA-001")
    }

    @Test("Nil expiry dates are sorted last")
    @MainActor
    func nilExpiryLast() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Passport", number: "PP-NIL", country: "XYZ", expiry: nil),
            (type: "Passport", number: "PP-DATED", country: "ABC", expiry: date(2027, 1, 1)),
        ])
        let result = DocumentResolver.resolve(person: person, airport: "ZZZZ")
        #expect(result?.docNumber == "PP-DATED")
    }

    @Test("Multiple Schengen prefixes recognized")
    @MainActor
    func multipleSchengenPrefixes() throws {
        let container = try makeTestContainer()
        let (person, _) = makePerson(container: container, documents: [
            (type: "Passport", number: "PP-GBR-001", country: "GBR", expiry: date(2031, 1, 1)),
            (type: "Passport", number: "PP-ITA-001", country: "ITA", expiry: date(2029, 1, 1)),
        ])

        // ED (Germany), EB (Belgium), LI (Italy) — all Schengen
        for airport in ["EDDF", "EBBR", "LIRF"] {
            let result = DocumentResolver.resolve(person: person, airport: airport)
            #expect(result?.docNumber == "PP-ITA-001", "Expected ITA doc for Schengen airport \(airport)")
        }
    }
}

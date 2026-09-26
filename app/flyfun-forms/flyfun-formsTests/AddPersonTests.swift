import Testing
import Foundation
import SwiftData
@testable import flyfun_forms

/// Creates an in-memory ModelContainer for testing (no CloudKit, no persistence).
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(
        for: Person.self, TravelDocument.self, Aircraft.self, Flight.self, Trip.self,
        configurations: config
    )
}

@MainActor
private func peopleCount(in context: ModelContext) throws -> Int {
    try context.fetchCount(FetchDescriptor<Person>())
}

@Suite("Adding a person")
@MainActor
struct AddPersonTests {

    // MARK: - Person.isBlank

    @Test("A new person is blank")
    func newPersonIsBlank() {
        #expect(Person().isBlank)
    }

    @Test("Whitespace alone is still blank")
    func whitespaceIsBlank() {
        let person = Person(firstName: "  ", lastName: "\n")
        person.phone = " "
        #expect(person.isBlank)
    }

    @Test("Any entered detail makes a person not blank")
    func anyDetailIsNotBlank() {
        #expect(!Person(firstName: "Jane").isBlank)
        #expect(!Person(lastName: "Zztest").isBlank)
        let dated = Person()
        dated.dateOfBirth = Date(timeIntervalSince1970: 0)
        #expect(!dated.isBlank)
        let reachable = Person()
        reachable.email = "someone@example.com"
        #expect(!reachable.isBlank)
    }

    @Test("A person holding a document is not blank, even an empty one")
    func documentIsNotBlank() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let person = Person()
        context.insert(person)
        let doc = TravelDocument()
        doc.person = person
        context.insert(doc)
        #expect(!person.isBlank)
    }

    // MARK: - Discarding

    @Test("A blank person is taken off the selection and deleted")
    func blankPersonDiscarded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let pilot = Person(firstName: "Test", lastName: "Pilot")
        let blank = Person()
        context.insert(pilot)
        context.insert(blank)
        var crew = [pilot]
        var passengers = [blank]

        let discarded = PeoplePickerView.discardIfBlank(blank, crew: &crew, passengers: &passengers, in: context)
        try context.save()

        #expect(discarded)
        #expect(crew.map(\.lastName) == ["Pilot"])
        #expect(passengers.isEmpty)
        #expect(try peopleCount(in: context) == 1)
    }

    @Test("A person with a name is kept and stays selected")
    func namedPersonKept() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let traveller = Person(firstName: "New", lastName: "Traveller")
        context.insert(traveller)
        var crew: [Person] = []
        var passengers = [traveller]

        let discarded = PeoplePickerView.discardIfBlank(traveller, crew: &crew, passengers: &passengers, in: context)
        try context.save()

        #expect(!discarded)
        #expect(passengers.count == 1)
        #expect(try peopleCount(in: context) == 1)
    }

    // MARK: - Name from search text

    @Test("One word is a last name")
    func oneWordIsLastName() {
        #expect(PeoplePickerView.splitName("Zztest") == ("", "Zztest"))
    }

    @Test("The first word is the first name, the rest the last name")
    func severalWords() {
        #expect(PeoplePickerView.splitName("Jane van Zztest") == ("Jane", "van Zztest"))
    }
}

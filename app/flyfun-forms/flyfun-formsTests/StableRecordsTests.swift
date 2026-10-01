import Testing
import Foundation
import SwiftData
@testable import flyfun_forms

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: AppSchema.schema, configurations: config)
}

/// What was actually written to the store, read back through a second context
/// so a value set on the in-memory object but left out of the save shows up.
@MainActor
private func stored<T: StableRecord>(_ type: T.Type, in container: ModelContainer) throws -> [T] {
    try ModelContext(container).fetch(FetchDescriptor<T>())
}

@Suite("Move-my-data stable records")
@MainActor
struct StableRecordsTests {

    init() {
        UpdateStamper.install()
    }

    // MARK: - uuid

    @Test("New records get a uuid from their init")
    func initAssignsUUID() {
        #expect(Person().uuid != nil)
        #expect(TravelDocument().uuid != nil)
        #expect(Aircraft().uuid != nil)
        #expect(Flight().uuid != nil)
        #expect(Trip().uuid != nil)
        #expect(Person().uuid != Person().uuid)
    }

    @Test("Backfill gives each record its own uuid, without touching updatedAt")
    func backfillAssignsDistinctUUIDs() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let people = (0..<3).map { Person(firstName: "Zz\($0)", lastName: "Zztest") }
        let flight = Flight()
        people.forEach(context.insert)
        context.insert(flight)
        try context.save()

        // What a row synced from an older build looks like: no uuid, no updatedAt.
        try UpdateStamper.withoutStamping {
            for person in people { person.uuid = nil; person.updatedAt = nil }
            flight.uuid = nil; flight.updatedAt = nil
            try context.save()
        }

        #expect(try StableRecords.backfill(in: context) == 4)

        let storedPeople = try stored(Person.self, in: container)
        let uuids = Set(storedPeople.compactMap(\.uuid))
        #expect(uuids.count == 3)
        #expect(storedPeople.allSatisfy { $0.updatedAt == nil })
        let storedFlight = try #require(try stored(Flight.self, in: container).first)
        #expect(storedFlight.uuid != nil)
        #expect(storedFlight.updatedAt == nil)
    }

    @Test("A second backfill changes and saves nothing")
    func backfillIsIdempotent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(Person(firstName: "Zed", lastName: "Zztest"))
        try context.save()
        let before = try #require(try stored(Person.self, in: container).first)

        #expect(try StableRecords.backfill(in: context) == 0)
        #expect(!context.hasChanges)
        let after = try #require(try stored(Person.self, in: container).first)
        #expect(after.uuid == before.uuid)
        #expect(after.updatedAt == before.updatedAt)
    }

    // MARK: - updatedAt

    @Test("Inserting stamps updatedAt, and the stamp is saved")
    func insertStamps() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let start = Date.now
        context.insert(Aircraft(registration: "ZZ-TST"))
        try context.save()

        let aircraft = try #require(try stored(Aircraft.self, in: container).first)
        let stamp = try #require(aircraft.updatedAt)
        #expect(stamp >= start)
    }

    @Test("Editing moves updatedAt forward")
    func editStamps() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let trip = Trip(name: "Zz trip")
        context.insert(trip)
        try context.save()
        let first = try #require(trip.updatedAt)

        // Make "later" unambiguous without sleeping.
        try UpdateStamper.withoutStamping {
            trip.updatedAt = first.addingTimeInterval(-60)
            try context.save()
        }
        trip.name = "Zz trip renamed"
        try context.save()

        let saved = try #require(try stored(Trip.self, in: container).first)
        #expect(saved.name == "Zz trip renamed")
        #expect(try #require(saved.updatedAt) > first.addingTimeInterval(-60))
    }

    @Test("Writing without stamping keeps the given updatedAt, as an import must")
    func withoutStampingKeepsTimestamp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let fromFile = Date(timeIntervalSince1970: 1_700_000_000)

        let person = Person(firstName: "Zed", lastName: "Zztest")
        try UpdateStamper.withoutStamping {
            person.updatedAt = fromFile
            context.insert(person)
            try context.save()
        }
        #expect(try stored(Person.self, in: container).first?.updatedAt == fromFile)

        try UpdateStamper.withoutStamping {
            person.lastName = "Zzimported"
            try context.save()
        }
        let saved = try #require(try stored(Person.self, in: container).first)
        #expect(saved.lastName == "Zzimported")
        #expect(saved.updatedAt == fromFile)

        // And stamping resumes afterwards.
        person.lastName = "Zzedited"
        try context.save()
        #expect(try #require(try stored(Person.self, in: container).first?.updatedAt) > fromFile)
    }

    // MARK: - Tombstones

    @Test("Deleting a record leaves one tombstone with its uuid and kind")
    func deleteRecordsTombstone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let person = Person(firstName: "Zed", lastName: "Zztest")
        let doc = TravelDocument(docNumber: "ZZ0000001")
        let aircraft = Aircraft(registration: "ZZ-TST")
        let flight = Flight()
        let trip = Trip(name: "Zz trip")
        context.insert(person)
        context.insert(doc)
        context.insert(aircraft)
        context.insert(flight)
        context.insert(trip)
        try context.save()

        let expected: [String: UUID?] = [
            "person": person.uuid, "travelDocument": doc.uuid, "aircraft": aircraft.uuid,
            "flight": flight.uuid, "trip": trip.uuid,
        ]
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.deleteRecordingTombstone(person, at: deletedAt)
        context.deleteRecordingTombstone(doc, at: deletedAt)
        context.deleteRecordingTombstone(aircraft, at: deletedAt)
        context.deleteRecordingTombstone(flight, at: deletedAt)
        context.deleteRecordingTombstone(trip, at: deletedAt)
        try context.save()

        let tombstones = try ModelContext(container).fetch(FetchDescriptor<DeletedRecord>())
        #expect(tombstones.count == 5)
        for tombstone in tombstones {
            #expect(expected[tombstone.kind] == tombstone.uuid)
            #expect(tombstone.deletedAt == deletedAt)
        }
        #expect(try stored(Person.self, in: container).isEmpty)
        #expect(try stored(Flight.self, in: container).isEmpty)
    }

    @Test("A record that never had a uuid leaves no tombstone")
    func noUUIDNoTombstone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let person = Person(firstName: "Zed", lastName: "Zztest")
        context.insert(person)
        try context.save()
        try UpdateStamper.withoutStamping {
            person.uuid = nil
            try context.save()
        }

        context.deleteRecordingTombstone(person)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<DeletedRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Person>()) == 0)
    }

    @Test("Delete All Data clears tombstones and writes none")
    func eraseAllClearsTombstones() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let gone = Person(firstName: "Zed", lastName: "Zztest")
        context.insert(gone)
        context.insert(Person(firstName: "Ann", lastName: "Zzsample"))
        context.insert(Flight())
        try context.save()
        context.deleteRecordingTombstone(gone)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<DeletedRecord>()) == 1)

        let forms = GeneratedFormFiles(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("StableRecordsTests-\(UUID().uuidString)", isDirectory: true))
        try LocalDataEraser.eraseAll(in: context, formFiles: forms)

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<DeletedRecord>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Person>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Flight>()) == 0)
    }
}

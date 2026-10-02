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

    @Test("Deleting a person deletes their documents, one tombstone each plus the person's")
    func deletePersonTakesDocuments() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let person = Person(firstName: "Zed", lastName: "Zztest")
        let passport = TravelDocument(docNumber: "ZZ0000001")
        let idCard = TravelDocument(docType: "Identity card", docNumber: "ZZ0000002")
        let someoneElses = TravelDocument(docNumber: "ZZ0000003")
        let other = Person(firstName: "Ann", lastName: "Zzsample")
        [person, other].forEach(context.insert)
        [passport, idCard, someoneElses].forEach(context.insert)
        passport.person = person
        idCard.person = person
        someoneElses.person = other
        try context.save()

        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.deleteRecordingTombstone(person, at: deletedAt)
        try context.save()

        let tombstones = try ModelContext(container).fetch(FetchDescriptor<DeletedRecord>())
        #expect(tombstones.count == 3)
        #expect(Set(tombstones.compactMap(\.uuid)) == Set([person.uuid, passport.uuid, idCard.uuid].compactMap { $0 }))
        #expect(tombstones.filter { $0.kind == "travelDocument" }.count == 2)
        #expect(tombstones.allSatisfy { $0.deletedAt == deletedAt })
        #expect(try stored(TravelDocument.self, in: container).map(\.docNumber) == ["ZZ0000003"])
        #expect(try stored(Person.self, in: container).map(\.lastName) == ["Zzsample"])
    }

    @Test("A document deleted just before its person gets one tombstone, not two")
    func deleteDocumentThenPerson() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let person = Person(firstName: "Zed", lastName: "Zztest")
        let passport = TravelDocument(docNumber: "ZZ0000001")
        context.insert(person)
        context.insert(passport)
        passport.person = person
        try context.save()

        context.deleteRecordingTombstone(passport)
        context.deleteRecordingTombstone(person)
        try context.save()

        let tombstones = try ModelContext(container).fetch(FetchDescriptor<DeletedRecord>())
        #expect(tombstones.filter { $0.uuid == passport.uuid }.count == 1)
        #expect(tombstones.count == 2)
    }

    // MARK: - Orphan documents

    @Test("Orphan cleanup deletes only an orphan seen long enough ago and unedited, with a tombstone")
    func orphanCleanup() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60)
        let longAgo = now.addingTimeInterval(-2 * StableRecords.orphanMargin)

        let old = TravelDocument(docNumber: "ZZORPHANOLD")
        let edited = TravelDocument(docNumber: "ZZORPHANEDITED")
        let new = TravelDocument(docNumber: "ZZORPHANNEW")
        let held = TravelDocument(docNumber: "ZZHELD")
        let person = Person(firstName: "Zed", lastName: "Zztest")
        context.insert(person)
        [old, edited, new, held].forEach(context.insert)
        held.person = person
        try context.save()
        // Edited within the margin, as an older build still syncing it would.
        try UpdateStamper.withoutStamping {
            edited.updatedAt = now.addingTimeInterval(-60 * 60)
            old.updatedAt = nil
            try context.save()
        }

        let oldId = try #require(old.uuid)
        let editedId = try #require(edited.uuid)
        let newId = try #require(new.uuid)
        let heldId = try #require(held.uuid)
        var firstSeen: [UUID: Date] = [
            oldId: longAgo,
            editedId: longAgo,
            heldId: longAgo,  // has a person again: forgotten
        ]
        let deleted1 = try StableRecords.deleteOrphanDocuments(in: context, firstSeen: &firstSeen, now: now)
        #expect(deleted1 == 1)

        #expect(Set(try stored(TravelDocument.self, in: container).map(\.docNumber))
            == ["ZZORPHANEDITED", "ZZORPHANNEW", "ZZHELD"])
        let tombstones = try ModelContext(container).fetch(FetchDescriptor<DeletedRecord>())
        #expect(tombstones.compactMap(\.uuid) == [oldId])
        #expect(tombstones.first?.kind == "travelDocument")
        #expect(tombstones.first?.deletedAt == now)
        // The new orphan starts its clock now; the edited one keeps its own.
        #expect(firstSeen == [editedId: longAgo, newId: now])
        // A cleanup is not an edit.
        #expect(try stored(TravelDocument.self, in: container).first { $0.docNumber == "ZZORPHANEDITED" }?.updatedAt
            == now.addingTimeInterval(-60 * 60))
    }

    @Test("An orphan seen for the first time is kept, however old, in case its person is still syncing")
    func orphanFirstSeenKept() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let orphan = TravelDocument(docNumber: "ZZORPHAN")
        context.insert(orphan)
        try context.save()
        try UpdateStamper.withoutStamping {
            orphan.updatedAt = nil
            try context.save()
        }

        let uuid = try #require(orphan.uuid)
        var firstSeen: [UUID: Date] = [:]
        let now = Date.now
        let deleted2 = try StableRecords.deleteOrphanDocuments(in: context, firstSeen: &firstSeen, now: now)
        #expect(deleted2 == 0)
        #expect(firstSeen == [uuid: now])
        #expect(try context.fetchCount(FetchDescriptor<TravelDocument>()) == 1)

        // A day later, still without a person: now it goes.
        let later = now.addingTimeInterval(StableRecords.orphanMargin + 1)
        let deleted3 = try StableRecords.deleteOrphanDocuments(in: context, firstSeen: &firstSeen, now: later)
        #expect(deleted3 == 1)
        #expect(firstSeen.isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TravelDocument>()) == 0)
    }

    @Test("Orphan cleanup with nothing to do changes and saves nothing")
    func orphanCleanupNoOp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let person = Person(firstName: "Zed", lastName: "Zztest")
        let passport = TravelDocument(docNumber: "ZZ0000001")
        context.insert(person)
        context.insert(passport)
        passport.person = person
        try context.save()
        let before = try #require(try stored(TravelDocument.self, in: container).first?.updatedAt)

        var firstSeen: [UUID: Date] = [:]
        let later = Date.now.addingTimeInterval(30 * 24 * 60 * 60)
        let deleted4 = try StableRecords.deleteOrphanDocuments(in: context, firstSeen: &firstSeen, now: later)
        #expect(deleted4 == 0)
        #expect(!context.hasChanges)
        #expect(firstSeen.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<DeletedRecord>()) == 0)
        #expect(try stored(TravelDocument.self, in: container).first?.updatedAt == before)
    }

    @Test("The launch step keeps first sightings between launches in UserDefaults")
    func orphanCleanupDefaults() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let suite = "StableRecordsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let orphan = TravelDocument(docNumber: "ZZORPHAN")
        context.insert(orphan)
        try context.save()
        let uuid = try #require(orphan.uuid)

        try StableRecords.deleteOrphanDocuments(in: context, defaults: defaults)
        let kept = try #require(defaults.dictionary(forKey: "orphanDocumentsFirstSeen") as? [String: Date])
        #expect(kept.keys.compactMap { UUID(uuidString: $0) } == [uuid])
        #expect(try context.fetchCount(FetchDescriptor<TravelDocument>()) == 1)

        // Once it has a person again, it is forgotten.
        let person = Person(firstName: "Zed", lastName: "Zztest")
        context.insert(person)
        orphan.person = person
        try context.save()
        try StableRecords.deleteOrphanDocuments(in: context, defaults: defaults)
        #expect(defaults.object(forKey: "orphanDocumentsFirstSeen") == nil)
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

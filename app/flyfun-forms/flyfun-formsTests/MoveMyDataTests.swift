import Testing
import Foundation
import SwiftData
@testable import flyfun_forms

// "Move my data": crypto, format, merge and apply. The merge cases mirror
// Android's `InterchangeTest.kt` by name, and the cross-platform fixtures in
// `app/fixtures/move-my-data/` are shared with `MoveMyDataFixturesTest.kt`.
// All data is self-describing dummy data (CLAUDE.md).

private enum Fixtures {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // flyfun-formsTests
        .deletingLastPathComponent()   // flyfun-forms
        .deletingLastPathComponent()   // app
        .appendingPathComponent("fixtures/move-my-data")

    /// The passphrase of both encrypted fixtures. The "é" is NFC-composed, so
    /// decrypting checks both platforms normalise alike.
    static let passphrase = "Fixture-Caf\u{e9}-rudder-alpha"

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: dir.appendingPathComponent(name))
    }

    static let androidCryptoSource = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("android/core-logic/src/main/kotlin/aero/flyfun/forms/logic/DataFileCrypto.kt")
}

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: AppSchema.schema, configurations: config)
}

private let t1 = "2026-09-01T10:00:00Z"
private let t2 = "2026-09-10T10:00:00Z"
private let t3 = "2026-09-19T10:00:00Z"

private func person(_ id: String, _ name: String, _ updated: String, deleted: String? = nil) -> PersonRecord {
    PersonRecord(id: id, firstName: name, lastName: "X", updatedAt: updated, deletedAt: deleted)
}

// MARK: - Crypto

@Suite("Move my data: encryption")
@MainActor
struct DataFileCryptoTests {
    let payload = Data(#"{"format":"flyfun-forms/data","people":[{"id":"a"}]}"#.utf8)
    let passphrase = "alpha-bravo-charlie-delta-echo-foxtrot"

    @Test("Round trips")
    func roundTrips() throws {
        let blob = try DataFileCrypto.encrypt(payload, passphrase: passphrase)
        #expect(try DataFileCrypto.decrypt(blob, passphrase: passphrase) == payload)
    }

    @Test("The file layout is magic, version, salt, nonce, then ciphertext and tag")
    func layout() throws {
        let blob = try DataFileCrypto.encrypt(payload, passphrase: passphrase)
        #expect(blob.prefix(7) == Data("FFFORMS".utf8))
        #expect(blob[7] == 1)
        #expect(blob.count == 7 + 1 + 16 + 12 + payload.count + 16)
    }

    @Test("The wrong passphrase fails cleanly rather than returning junk")
    func wrongPassphrase() throws {
        let blob = try DataFileCrypto.encrypt(payload, passphrase: passphrase)
        #expect(throws: DataFileCrypto.Failure.wrongPassphrase) {
            try DataFileCrypto.decrypt(blob, passphrase: "wrong-wrong-wrong")
        }
    }

    @Test("A tampered byte is detected, not silently decrypted")
    func tampered() throws {
        var blob = try DataFileCrypto.encrypt(payload, passphrase: passphrase)
        blob[blob.count - 1] &+= 1
        #expect(throws: DataFileCrypto.Failure.wrongPassphrase) {
            try DataFileCrypto.decrypt(blob, passphrase: passphrase)
        }
        var body = try DataFileCrypto.encrypt(payload, passphrase: passphrase)
        body[40] &+= 1
        #expect(throws: DataFileCrypto.Failure.wrongPassphrase) {
            try DataFileCrypto.decrypt(body, passphrase: passphrase)
        }
    }

    @Test("A foreign file is refused by its header")
    func foreignHeader() {
        #expect(throws: DataFileCrypto.Failure.notOurFile) {
            try DataFileCrypto.decrypt(Data("just some bytes that are long enough to pass the size check".utf8),
                                       passphrase: passphrase)
        }
        var otherVersion = Data("FFFORMS".utf8)
        otherVersion.append(contentsOf: [2] + [UInt8](repeating: 0, count: 60))
        #expect(throws: DataFileCrypto.Failure.notOurFile) {
            try DataFileCrypto.decrypt(otherVersion, passphrase: passphrase)
        }
    }

    @Test("Plaintext is never visible in the ciphertext, and every export differs")
    func opaqueAndSalted() throws {
        let a = try DataFileCrypto.encrypt(payload, passphrase: passphrase)
        let b = try DataFileCrypto.encrypt(payload, passphrase: passphrase)
        #expect(a.range(of: Data("flyfun-forms".utf8)) == nil)
        #expect(a != b)
    }

    @Test("Encrypted files are recognisable without the passphrase")
    func looksEncrypted() throws {
        #expect(DataFileCrypto.looksEncrypted(try DataFileCrypto.encrypt(payload, passphrase: passphrase)))
        #expect(!DataFileCrypto.looksEncrypted(payload))
    }

    @Test("Passphrases are trimmed and NFC-normalised but keep their case")
    func normalisation() throws {
        let composed = "Caf\u{e9}-Rudder"          // é as one code point
        let decomposed = "  Cafe\u{301}-Rudder \n" // e + combining accent, with spaces
        let blob = try DataFileCrypto.encrypt(payload, passphrase: composed)
        #expect(try DataFileCrypto.decrypt(blob, passphrase: decomposed) == payload)
        #expect(throws: DataFileCrypto.Failure.wrongPassphrase) {
            try DataFileCrypto.decrypt(blob, passphrase: "caf\u{e9}-rudder")
        }
    }

    @Test("Generated passphrases are six words from the list, usable and distinct")
    func generated() throws {
        let one = DataFileCrypto.generatePassphrase()
        let two = DataFileCrypto.generatePassphrase()
        let words = one.split(separator: "-").map(String.init)
        #expect(words.count == 6)
        #expect(words.allSatisfy(DataFileCrypto.wordList.contains))
        #expect(one != two)
        let blob = try DataFileCrypto.encrypt(payload, passphrase: one)
        #expect(try DataFileCrypto.decrypt(blob, passphrase: one) == payload)
    }

    @Test("The word list is Android's, in the same order")
    func wordListMatchesAndroid() throws {
        let source = try String(contentsOf: Fixtures.androidCryptoSource, encoding: .utf8)
        let start = try #require(source.range(of: "WORDS = listOf("))
        let end = try #require(source[start.upperBound...].range(of: ")"))
        let android = source[start.upperBound..<end.lowerBound]
            .matches(of: /"([a-z]+)"/).map { String($0.output.1) }
        #expect(android == DataFileCrypto.wordList)
    }

    @Test("Decrypts the file Android encrypted")
    func decryptsAndroidFixture() throws {
        let blob = try Fixtures.data("android-encrypted.ffdata")
        #expect(DataFileCrypto.looksEncrypted(blob))
        let plaintext = try DataFileCrypto.decrypt(blob, passphrase: Fixtures.passphrase)
        #expect(plaintext == (try Fixtures.data("android-plain.json")))
    }

    @Test("Decrypts the iOS fixture, which Android's tests decrypt too")
    func decryptsIOSFixture() throws {
        let plaintext = try DataFileCrypto.decrypt(try Fixtures.data("ios-encrypted.ffdata"),
                                                   passphrase: Fixtures.passphrase)
        #expect(plaintext == (try Fixtures.data("ios-plain.json")))
    }
}

// MARK: - Format

@Suite("Move my data: format")
@MainActor
struct InterchangeFormatTests {

    @Test("Round trip through encode and decode preserves everything")
    func roundTrip() throws {
        let document = InterchangeDocument(
            exportedAt: t3,
            people: [person("a", "Anna", t1)],
            flights: [FlightRecord(id: "f", originICAO: "EGTF", destinationICAO: "LFRM",
                                   departureInstant: t1, arrivalInstant: t2, updatedAt: t1)],
            flightPeople: [FlightPersonRecord(flightId: "f", personId: "a", role: "crew")]
        )
        #expect(try InterchangeMerge.decode(InterchangeMerge.encode(document)) == document)
    }

    @Test("Calendar days stay plain dates, instants keep their Z, nils are left out")
    func encodingShape() throws {
        let document = InterchangeDocument(
            exportedAt: t3,
            travelDocuments: [TravelDocumentRecord(id: "d", personId: "a", docNumber: "X",
                                                   expiryDate: "2031-06-30", updatedAt: t1)]
        )
        let text = String(decoding: try InterchangeMerge.encode(document), as: UTF8.self)
        #expect(text.contains(#""expiryDate" : "2031-06-30""#))
        #expect(text.contains(#""updatedAt" : "2026-09-01T10:00:00Z""#))
        #expect(!text.contains("deletedAt"))
        #expect(!text.contains("issuingCountry"))
    }

    @Test("Decodes the file Android wrote")
    func decodesAndroidFixture() throws {
        let document = try InterchangeMerge.decode(try Fixtures.data("android-plain.json"))
        #expect(document.exportedBy == ExportedBy(platform: "android", appVersion: "0.1-fixture"))
        #expect(document.people.count == 3)
        #expect(document.people.filter { $0.deletedAt != nil }.count == 1)
        let pilot = try #require(document.people.first { $0.lastName == "Pilot-One" })
        #expect(pilot.dateOfBirth == "1975-04-12")
        #expect(pilot.updatedAt == "2026-09-12T09:01:44.123456Z")
        #expect(document.travelDocuments.count == 2)
        #expect(document.aircraft.first?.ownerPersonId == pilot.id)
        #expect(document.trips.first?.extraFields == ["fixtureField": "fixture value"])
        #expect(document.flights.count == 2)
        #expect(document.flightPeople.count == 4)
    }

    @Test("Unknown keys are ignored and missing defaults are filled, as on Android")
    func lenientDecode() throws {
        let json = """
            {"format":"flyfun-forms/data","version":1,"exportedAt":"\(t1)","somethingNew":{"x":1},
             "people":[{"id":"a","updatedAt":"\(t1)","androidOnly":true}],
             "flights":[{"id":"f","departureInstant":"\(t1)","arrivalInstant":"\(t1)","updatedAt":"\(t1)"}]}
            """
        let document = try InterchangeMerge.decode(Data(json.utf8))
        #expect(document.exportedBy.platform == "android")
        #expect(document.people == [PersonRecord(id: "a", updatedAt: t1)])
        #expect(document.flights.first?.nature == "private")
        #expect(document.flights.first?.chosenDocNumbers == nil)
    }

    @Test("A foreign file is refused rather than half-imported")
    func foreignFormat() {
        #expect(throws: InterchangeMerge.Failure.notOurFile) {
            try InterchangeMerge.decode(Data(#"{"format":"something/else","version":1,"exportedAt":"\#(t1)"}"#.utf8))
        }
    }

    @Test("A newer format version is refused")
    func newerVersion() {
        #expect(throws: InterchangeMerge.Failure.newerVersion) {
            try InterchangeMerge.decode(Data(#"{"format":"flyfun-forms/data","version":99,"exportedAt":"\#(t1)"}"#.utf8))
        }
    }

    @Test("Garbage is refused, and so is a record missing a required field")
    func garbage() {
        #expect(throws: InterchangeMerge.Failure.notOurFile) {
            try InterchangeMerge.decode(Data("not json".utf8))
        }
        #expect(throws: InterchangeMerge.Failure.notOurFile) {
            try InterchangeMerge.decode(Data(#"{"exportedAt":"\#(t1)","people":[{"id":"a"}]}"#.utf8))
        }
    }

    @Test("Calendar days do not shift in a time zone far from UTC", arguments: [
        "Pacific/Auckland", "America/Los_Angeles", "Asia/Kolkata", "UTC",
    ])
    func calendarDays(zoneId: String) throws {
        let zone = try #require(TimeZone(identifier: zoneId))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // A stored day is midnight in the device's zone, as a date-only DatePicker writes it.
        let midnight = try #require(calendar.date(from: DateComponents(year: 1975, month: 4, day: 12)))
        #expect(InterchangeDay.format(midnight, timeZone: zone) == "1975-04-12")
        let parsed = try #require(InterchangeDay.parse("1975-04-12", timeZone: zone))
        #expect(parsed == midnight)
        #expect(InterchangeDay.parse("1975-02-30", timeZone: zone) == nil)
    }

    @Test("Timestamps compare as instants, not as strings")
    func instantsCompare() {
        #expect(InterchangeMerge.isNewer("2026-09-19T18:00:13Z", than: "2026-09-19T18:00:12.500Z"))
        #expect(!InterchangeMerge.isNewer("2026-09-19T18:00:12Z", than: "2026-09-19T18:00:12.500Z"))
        #expect(InterchangeMerge.isNewer("2026-09-19T18:00:12.750Z", than: "2026-09-19T18:00:12.500Z"))
        #expect(!InterchangeMerge.isNewer("2026-09-19T18:00:12Z", than: "2026-09-19T18:00:12Z"))
        #expect(InterchangeMerge.isNewer("2026-09-19T18:00:12.000001Z", than: "2026-09-19T18:00:12Z"))
    }

    @Test("Instants are written with Z, milliseconds only when present, never rounded up")
    func instantFormat() throws {
        let whole = try #require(InterchangeTime.parse("2026-09-18T14:22:03Z"))
        #expect(InterchangeTime.format(whole) == "2026-09-18T14:22:03Z")
        #expect(InterchangeTime.format(whole.addingTimeInterval(0.2509)) == "2026-09-18T14:22:03.250Z")
        #expect(InterchangeTime.format(whole.addingTimeInterval(0.9999)) == "2026-09-18T14:22:03.999Z")
        #expect(InterchangeTime.format(Date(timeIntervalSince1970: 0)) == InterchangeTime.oldest)
        #expect(InterchangeTime.parse("2026-09-18T16:22:03+02:00") == whole)
        #expect(InterchangeTime.parse("2026-09-18 14:22:03") == nil)
    }

    /// The document `ios-plain.json` holds, built here so the fixture can be
    /// regenerated from this code.
    static let iosFixture: InterchangeDocument = {
        let a101 = "00000000-0000-4000-8000-00000000a101"
        let a102 = "00000000-0000-4000-8000-00000000a102"
        let t = "2026-09-25T12:00:00Z"
        return InterchangeDocument(
            exportedAt: "2026-09-26T07:00:00Z",
            exportedBy: ExportedBy(platform: "ios", appVersion: "0.1-fixture"),
            people: [
                PersonRecord(id: a101, firstName: "Fixture", lastName: "Ios-Pilot", dateOfBirth: "1980-02-29",
                             sex: "Male", placeOfBirth: "Fixture Town", address: "101 Fixture Lane",
                             phone: "+00 0000 000101", email: "ios-pilot@example.invalid",
                             isUsualCrew: true, updatedAt: "2026-09-25T12:00:00.250Z"),
                PersonRecord(id: a102, firstName: "Fixture", lastName: "Ios-Passenger", sex: "Female", updatedAt: t),
            ],
            travelDocuments: [
                TravelDocumentRecord(id: "00000000-0000-4000-8000-00000000d101", personId: a101,
                                     docNumber: "TESTDOC101", issuingCountry: "FRA",
                                     expiryDate: "2032-03-31", updatedAt: t),
                TravelDocument.tombstone(id: "00000000-0000-4000-8000-00000000d199", deletedAt: "2026-09-24T08:00:00Z"),
            ],
            aircraft: [
                AircraftRecord(id: "00000000-0000-4000-8000-00000000c101", registration: "ZZ-IOSF", type: "FIXT",
                               ownerPersonId: a101, updatedAt: InterchangeTime.oldest),
            ],
            trips: [
                TripRecord(id: "00000000-0000-4000-8000-00000000e101", name: "Fixture iOS trip",
                           createdAt: "2026-09-20T00:00:00Z", extraFields: ["fixtureField": "fixture value"],
                           updatedAt: t),
                Trip.tombstone(id: "00000000-0000-4000-8000-00000000e199", deletedAt: "2026-09-23T10:00:00Z"),
            ],
            flights: [
                FlightRecord(id: "00000000-0000-4000-8000-00000000f101", originICAO: "EGTF", destinationICAO: "LFRM",
                             departureInstant: "2026-10-01T07:45:00Z", arrivalInstant: "2026-10-01T09:30:00Z",
                             aircraftId: "00000000-0000-4000-8000-00000000c101", responsiblePersonId: a101,
                             tripId: "00000000-0000-4000-8000-00000000e101", legOrder: 0,
                             chosenDocNumbers: ["TESTDOC101"], updatedAt: t),
                Flight.tombstone(id: "00000000-0000-4000-8000-00000000f199", deletedAt: "2026-09-22T16:00:00Z"),
            ],
            flightPeople: [
                FlightPersonRecord(flightId: "00000000-0000-4000-8000-00000000f101", personId: a101, role: "crew"),
                FlightPersonRecord(flightId: "00000000-0000-4000-8000-00000000f101", personId: a102, role: "passenger"),
            ]
        )
    }()

    @Test("The iOS fixture is what this code describes")
    func iosFixtureMatches() throws {
        #expect(try InterchangeMerge.decode(try Fixtures.data("ios-plain.json")) == Self.iosFixture)
    }

    /// Regenerates the iOS fixtures from this code. Run on a Mac with
    /// `TEST_RUNNER_WRITE_MOVE_MY_DATA_FIXTURES=1 xcodebuild test … -only-testing:flyfun-formsTests/InterchangeFormatTests`,
    /// then run Android's `MoveMyDataFixturesTest` against them.
    @Test("Write the iOS fixtures",
          .enabled(if: ProcessInfo.processInfo.environment["WRITE_MOVE_MY_DATA_FIXTURES"] == "1"))
    func writeIOSFixtures() throws {
        let plain = try InterchangeMerge.encode(Self.iosFixture)
        try plain.write(to: Fixtures.dir.appendingPathComponent("ios-plain.json"))
        try DataFileCrypto.encrypt(plain, passphrase: Fixtures.passphrase)
            .write(to: Fixtures.dir.appendingPathComponent("ios-encrypted.ffdata"))
    }
}

// MARK: - Merge (mirrors InterchangeTest.kt)

@Suite("Move my data: merge")
@MainActor
struct InterchangeMergeTests {

    @Test("A record only in the file is inserted")
    func insert() {
        let out = InterchangeMerge.merge(local: [PersonRecord](), incoming: [person("a", "Anna", t1)])
        #expect(out.insert.count == 1)
        #expect(out.update.isEmpty)
    }

    @Test("The newer updatedAt wins")
    func newerWins() {
        let out = InterchangeMerge.merge(local: [person("a", "Old", t1)], incoming: [person("a", "New", t2)])
        #expect(out.update.map(\.firstName) == ["New"])
    }

    @Test("An older incoming record is ignored")
    func olderIgnored() {
        let out = InterchangeMerge.merge(local: [person("a", "Current", t2)], incoming: [person("a", "Stale", t1)])
        #expect(out.update.isEmpty)
        #expect(out.unchanged == 1)
    }

    @Test("An identical timestamp is treated as unchanged rather than rewritten")
    func identicalUnchanged() {
        let out = InterchangeMerge.merge(local: [person("a", "Same", t2)], incoming: [person("a", "Same", t2)])
        #expect(out.unchanged == 1)
        #expect(out.update.isEmpty)
    }

    @Test("A local record the file does not mention is never deleted")
    func localOnlyKept() {
        let out = InterchangeMerge.merge(local: [person("a", "Anna", t1), person("b", "Bo", t1)],
                                         incoming: [person("a", "Anna", t2)])
        #expect(out.remove.isEmpty)
        #expect(out.update.count == 1)
    }

    @Test("A newer tombstone removes the local record")
    func newerTombstoneRemoves() {
        let out = InterchangeMerge.merge(local: [person("a", "Anna", t1)],
                                         incoming: [person("a", "Anna", t2, deleted: t2)])
        #expect(out.remove.count == 1)
        #expect(out.update.isEmpty)
    }

    @Test("An older tombstone does not resurrect as a delete")
    func olderTombstoneIgnored() {
        // Local edited after the other device deleted it: the edit wins.
        let out = InterchangeMerge.merge(local: [person("a", "Anna", t3)],
                                         incoming: [person("a", "Anna", t2, deleted: t2)])
        #expect(out.remove.isEmpty)
        #expect(out.unchanged == 1)
    }

    @Test("A tombstone for a record we never had is not an insert")
    func unknownTombstone() {
        let out = InterchangeMerge.merge(local: [PersonRecord](), incoming: [person("a", "Anna", t2, deleted: t2)])
        #expect(out.insert.isEmpty)
        #expect(out.unchanged == 1)
    }

    @Test("A live record deleted here more recently is not brought back")
    func localTombstoneGuards() {
        let local = [Person.tombstone(id: "a", deletedAt: t3)]
        let out = InterchangeMerge.merge(local: local, incoming: [person("a", "Anna", t2)])
        #expect(out.insert.isEmpty && out.update.isEmpty)
        #expect(out.unchanged == 1)
    }

    @Test("A live record edited after it was deleted here comes back")
    func olderLocalTombstoneLosesToEdit() {
        let local = [Person.tombstone(id: "a", deletedAt: t1)]
        let out = InterchangeMerge.merge(local: local, incoming: [person("a", "Anna", t2)])
        #expect(out.update.map(\.id) == ["a"])
    }

    @Test("Membership only rides with flights the merge writes")
    func membership() {
        let local = InterchangeMerge.LocalSnapshot(flights: [
            FlightRecord(id: "kept", departureInstant: t1, arrivalInstant: t1, updatedAt: t3),
        ])
        let document = InterchangeDocument(
            exportedAt: t3,
            flights: [
                FlightRecord(id: "kept", departureInstant: t1, arrivalInstant: t1, updatedAt: t1), // stale
                FlightRecord(id: "new", departureInstant: t1, arrivalInstant: t1, updatedAt: t2),  // inserted
            ],
            flightPeople: [
                FlightPersonRecord(flightId: "kept", personId: "p1", role: "crew"),
                FlightPersonRecord(flightId: "new", personId: "p2", role: "crew"),
            ]
        )
        let summary = InterchangeMerge.summarise(local: local, document: document)
        #expect(summary.flightPeople.map(\.flightId) == ["new"])
    }

    @Test("The summary counts every kind")
    func summaryCounts() {
        let local = InterchangeMerge.LocalSnapshot(people: [person("a", "Anna", t1)])
        let document = InterchangeDocument(
            exportedAt: t3,
            people: [person("a", "Anna Updated", t2), person("b", "Bo", t2)],
            aircraft: [AircraftRecord(id: "c", updatedAt: t1)]
        )
        let summary = InterchangeMerge.summarise(local: local, document: document)
        #expect(summary.inserted == 2)
        #expect(summary.updated == 1)
        #expect(summary.removed == 0)
        #expect(summary.untouched == 0)
    }
}

// MARK: - Export and apply (SwiftData, in memory)

@Suite("Move my data: export and import")
@MainActor
struct DataTransferTests {

    init() {
        UpdateStamper.install()
    }

    private func date(_ iso: String) throws -> Date {
        try #require(InterchangeTime.parse(iso))
    }

    private func day(_ value: String) throws -> Date {
        try #require(InterchangeDay.parse(value))
    }

    private func importFile(_ data: Data, passphrase: String? = nil, into context: ModelContext) throws -> MergeSummary {
        let preview = try DataTransfer.preview(data, passphrase: passphrase, in: context)
        try DataTransfer.apply(preview.summary, in: context)
        return preview.summary
    }

    /// Live records sorted by id, so two snapshots compare regardless of
    /// fetch order. Tombstones are dropped: an import does not store one for a
    /// record the device never had, as on Android.
    private func normalised(_ d: InterchangeDocument) -> InterchangeDocument {
        var d = d
        d.exportedAt = ""
        d.people.removeAll { $0.deletedAt != nil }
        d.travelDocuments.removeAll { $0.deletedAt != nil }
        d.aircraft.removeAll { $0.deletedAt != nil }
        d.trips.removeAll { $0.deletedAt != nil }
        d.flights.removeAll { $0.deletedAt != nil }
        d.people.sort { $0.id < $1.id }
        d.travelDocuments.sort { $0.id < $1.id }
        d.aircraft.sort { $0.id < $1.id }
        d.trips.sort { $0.id < $1.id }
        d.flights.sort { $0.id < $1.id }
        d.flightPeople.sort { ($0.flightId, $0.role, $0.seatOrder) < ($1.flightId, $1.role, $1.seatOrder) }
        return d
    }

    /// A small but complete dataset: two people with documents, an aircraft,
    /// a trip with two legs, crew and passengers, and one deletion.
    @discardableResult
    private func seed(_ context: ModelContext) throws -> (pilot: Person, flight: Flight) {
        let pilot = Person(firstName: "Fixture", lastName: "Seed-Pilot")
        let passenger = Person(firstName: "Fixture", lastName: "Seed-Passenger")
        let passport = TravelDocument(docNumber: "TESTDOC201", issuingCountry: "FRA", expiryDate: try day("2031-06-30"))
        let card = TravelDocument(docType: "Identity card", docNumber: "TESTDOC202", issuingCountry: "GBR")
        let aircraft = Aircraft(registration: "ZZ-SEED", type: "FIXT")
        let doomed = Aircraft(registration: "ZZ-GONE", type: "FIXT")
        let trip = Trip(name: "Fixture seed trip")
        let out = Flight()
        let back = Flight()
        // Inserted before any relationship is set.
        [pilot, passenger].forEach(context.insert)
        [passport, card].forEach(context.insert)
        [aircraft, doomed].forEach(context.insert)
        context.insert(trip)
        [out, back].forEach(context.insert)

        pilot.dateOfBirth = try day("1975-04-12")
        pilot.sex = "Male"
        pilot.isUsualCrew = true
        passenger.sex = "Female"
        passport.person = pilot
        card.person = passenger
        aircraft.ownerPerson = pilot
        trip.extraFields = ["fixtureField": "fixture value"]

        out.originICAO = "EGTF"; out.destinationICAO = "LFRM"
        out.departureDateTime = try date("2026-09-20T08:15:00Z")
        out.arrivalDateTime = try date("2026-09-20T10:05:00Z")
        out.aircraft = aircraft; out.trip = trip; out.legOrder = 0
        out.crew = [pilot]; out.passengers = [passenger]
        out.setResponsiblePerson(pilot)
        out.chosenDocNumbers = ["TESTDOC201"]

        back.originICAO = "LFRM"; back.destinationICAO = "EGTF"
        back.departureDateTime = try date("2026-09-22T23:30:00Z")
        back.arrivalDateTime = try date("2026-09-23T01:10:00Z")
        back.aircraft = aircraft; back.trip = trip; back.legOrder = 1
        back.crew = [pilot]
        try context.save()

        context.deleteRecordingTombstone(doomed)
        try context.save()
        return (pilot, out)
    }

    // MARK: Export

    @Test("Export maps every field, relationship and tombstone")
    func exportMapping() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (pilot, flight) = try seed(context)
        let document = try DataTransfer.snapshot(in: context, exportedBy: ExportedBy(platform: "ios", appVersion: "t"))

        let pilotId = try #require(pilot.uuid?.uuidString.lowercased())
        let pilotRecord = try #require(document.people.first { $0.id == pilotId })
        #expect(pilotRecord.dateOfBirth == "1975-04-12")
        #expect(pilotRecord.sex == "Male")
        #expect(pilotRecord.isUsualCrew)
        #expect(pilotRecord.updatedAt != InterchangeTime.oldest)

        let passport = try #require(document.travelDocuments.first { $0.docNumber == "TESTDOC201" })
        #expect(passport.personId == pilotId)
        #expect(passport.expiryDate == "2031-06-30")

        #expect(document.aircraft.first { $0.registration == "ZZ-SEED" }?.ownerPersonId == pilotId)
        let tombstone = try #require(document.aircraft.first { $0.deletedAt != nil })
        #expect(tombstone.updatedAt == tombstone.deletedAt)
        #expect(tombstone.registration == "")

        #expect(document.trips.first?.extraFields == ["fixtureField": "fixture value"])

        let flightId = try #require(flight.uuid?.uuidString.lowercased())
        let flightRecord = try #require(document.flights.first { $0.id == flightId })
        #expect(flightRecord.departureInstant == "2026-09-20T08:15:00Z")
        #expect(flightRecord.arrivalInstant == "2026-09-20T10:05:00Z")
        #expect(flightRecord.responsiblePersonId == pilotId)
        #expect(flightRecord.tripId == document.trips.first?.id)
        #expect(flightRecord.chosenDocNumbers == ["TESTDOC201"])
        #expect(document.flightPeople.filter { $0.flightId == flightId }.map(\.role).sorted() == ["crew", "passenger"])
    }

    @Test("A record from before stable ids exports with the oldest instant, never now")
    func nilUpdatedAtIsOldest() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let legacy = Person(firstName: "Fixture", lastName: "Legacy")
        context.insert(legacy)
        try context.save()
        try UpdateStamper.withoutStamping {
            legacy.updatedAt = nil
            try context.save()
        }
        let document = try DataTransfer.snapshot(in: context)
        #expect(document.people.map(\.updatedAt) == [InterchangeTime.oldest])
    }

    @Test("Orphan travel documents are left out of the export")
    func orphansSkipped() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(TravelDocument(docNumber: "TESTORPHAN"))
        try context.save()
        #expect(try DataTransfer.snapshot(in: context).travelDocuments.isEmpty)
    }

    @Test("Export platform names the OS that wrote the file")
    func platform() {
        #if os(macOS)
        #expect(DataTransfer.currentExporter.platform == "macos")
        #else
        #expect(DataTransfer.currentExporter.platform == "ios")
        #endif
    }

    // MARK: Import

    @Test("Imports Android's file with relationships, order and the file's updatedAt")
    func importsAndroidFixture() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let summary = try importFile(try Fixtures.data("android-encrypted.ffdata"),
                                     passphrase: Fixtures.passphrase, into: context)
        // 2 live people, 2 documents, 1 aircraft, 1 trip, 2 flights; the deleted person is not inserted.
        #expect(summary.inserted == 8)
        #expect(summary.untouched == 1)

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 2)
        let pilot = try #require(people.first { $0.lastName == "Pilot-One" })
        let passenger = try #require(people.first { $0.lastName == "Passenger-Two" })
        #expect(pilot.uuid == UUID(uuidString: "00000000-0000-4000-8000-00000000a001"))
        #expect(pilot.updatedAt == (try date("2026-09-12T09:01:44.123456Z")))
        #expect(InterchangeDay.format(try #require(pilot.dateOfBirth)) == "1975-04-12")
        #expect(pilot.documentList.map(\.docNumber) == ["TESTDOC001"])
        #expect(InterchangeDay.format(try #require(pilot.documentList.first?.expiryDate)) == "2031-06-30")
        #expect(passenger.documentList.first?.isActive == false)

        let aircraft = try #require(try context.fetch(FetchDescriptor<Aircraft>()).first)
        #expect(aircraft.ownerPerson === pilot)
        let trip = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
        #expect(trip.extraFields == ["fixtureField": "fixture value"])
        #expect(trip.sortedLegs.map(\.originICAO) == ["EGTF", "LFRM"])

        let out = try #require(trip.sortedLegs.first)
        #expect(out.departureDateTime == (try date("2026-09-20T08:15:00Z")))
        #expect(out.arrivalDateTime == (try date("2026-09-20T10:05:00Z")))
        #expect(out.crewList.map(\.lastName) == ["Pilot-One"])
        #expect(out.passengerList.map(\.lastName) == ["Passenger-Two"])
        #expect(out.responsiblePerson === pilot)
        #expect(out.aircraft === aircraft)
        #expect(out.chosenDocNumbers == ["TESTDOC001"])
        // Crosses UTC midnight: the instant, not a day + time pair, decides.
        let back = try #require(trip.sortedLegs.last)
        #expect(back.arrivalDateTime == (try date("2026-09-23T01:10:00Z")))
        #expect(Set(back.crewList.map(\.lastName)) == ["Passenger-Two", "Pilot-One"])
    }

    @Test("Imports the iOS fixture and keeps its tombstones out of the store")
    func importsIOSFixture() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let summary = try importFile(try Fixtures.data("ios-plain.json"), into: context)
        #expect(summary.removed == 0)
        #expect(try context.fetch(FetchDescriptor<Flight>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DeletedRecord>()).isEmpty)
        let aircraft = try #require(try context.fetch(FetchDescriptor<Aircraft>()).first)
        #expect(aircraft.updatedAt == Date(timeIntervalSince1970: 0))
    }

    @Test("An update keeps the file's updatedAt rather than being stamped now")
    func updateKeepsFileTimestamp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let before = Person(firstName: "Fixture", lastName: "Before")
        context.insert(before)
        try context.save()
        try UpdateStamper.withoutStamping {
            before.updatedAt = try date(t1)
            try context.save()
        }
        let id = try #require(before.uuid?.uuidString.lowercased())
        let file = InterchangeDocument(exportedAt: t3, people: [
            PersonRecord(id: id, firstName: "Fixture", lastName: "After", updatedAt: t2),
        ])
        let summary = try importFile(try InterchangeMerge.encode(file), into: context)
        #expect(summary.updated == 1)
        let stored = try ModelContext(context.container).fetch(FetchDescriptor<Person>())
        #expect(stored.map(\.lastName) == ["After"])
        #expect(stored.first?.updatedAt == (try date(t2)))
    }

    @Test("A tombstone in the file deletes the record and writes a DeletedRecord")
    func fileTombstoneDeletes() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let doomed = Person(firstName: "Fixture", lastName: "Doomed")
        context.insert(doomed)
        try context.save()
        try UpdateStamper.withoutStamping {
            doomed.updatedAt = try date(t1)
            try context.save()
        }
        let uuid = try #require(doomed.uuid)
        let file = InterchangeDocument(exportedAt: t3, people: [
            person(uuid.uuidString.lowercased(), "Fixture", t2, deleted: t2),
        ])
        let summary = try importFile(try InterchangeMerge.encode(file), into: context)
        #expect(summary.removed == 1)
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        let tombstone = try #require(try context.fetch(FetchDescriptor<DeletedRecord>()).first)
        #expect(tombstone.uuid == uuid)
        #expect(tombstone.kind == Person.recordKind)
        #expect(tombstone.deletedAt == (try date(t2)))
        // and the deletion keeps travelling
        #expect(try DataTransfer.snapshot(in: context).people.map(\.deletedAt) == [t2])
    }

    @Test("A record deleted here more recently than the file's edit stays deleted")
    func resurrectionGuard() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let uuid = UUID()
        context.insert(DeletedRecord(uuid: uuid, kind: Person.recordKind, deletedAt: try date(t3)))
        try context.save()
        let file = InterchangeDocument(exportedAt: t3, people: [person(uuid.uuidString.lowercased(), "Ghost", t2)])
        let summary = try importFile(try InterchangeMerge.encode(file), into: context)
        #expect(summary.untouched == 1)
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
    }

    @Test("A record edited elsewhere after it was deleted here comes back, and its tombstone goes")
    func newerEditBeatsOlderTombstone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let uuid = UUID()
        context.insert(DeletedRecord(uuid: uuid, kind: Person.recordKind, deletedAt: try date(t1)))
        try context.save()
        let file = InterchangeDocument(exportedAt: t3, people: [person(uuid.uuidString.lowercased(), "Back", t2)])
        _ = try importFile(try InterchangeMerge.encode(file), into: context)
        #expect(try context.fetch(FetchDescriptor<Person>()).map(\.uuid) == [uuid])
        #expect(try context.fetch(FetchDescriptor<DeletedRecord>()).isEmpty)
    }

    @Test("A reference to a record nowhere to be found becomes nil")
    func danglingReference() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let file = InterchangeDocument(exportedAt: t3, aircraft: [
            AircraftRecord(id: UUID().uuidString.lowercased(), registration: "ZZ-DANG",
                           ownerPersonId: UUID().uuidString.lowercased(), updatedAt: t1),
        ])
        _ = try importFile(try InterchangeMerge.encode(file), into: context)
        let aircraft = try #require(try context.fetch(FetchDescriptor<Aircraft>()).first)
        #expect(aircraft.ownerPerson == nil)
    }

    @Test("A failure part-way rolls back, writing nothing")
    func failureRollsBack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let file = InterchangeDocument(exportedAt: t3, people: [
            person(UUID().uuidString.lowercased(), "Written", t1),
            person("not-a-uuid", "Broken", t1),
        ])
        let preview = try DataTransfer.preview(try InterchangeMerge.encode(file), passphrase: nil, in: context)
        #expect(throws: InterchangeMerge.Failure.notOurFile) {
            try DataTransfer.apply(preview.summary, in: context)
        }
        #expect(!context.hasChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Person>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
    }

    @Test("A wrong passphrase fails cleanly and writes nothing")
    func wrongPassphraseWritesNothing() throws {
        let sourceContainer = try makeTestContainer()
        let source = sourceContainer.mainContext
        try seed(source)
        let file = try DataTransfer.exportEncrypted(in: source, passphrase: "Fixture-right")
        let targetContainer = try makeTestContainer()
        let target = targetContainer.mainContext
        #expect(throws: DataTransfer.Failure.needsPassphrase) {
            try DataTransfer.preview(file, passphrase: nil, in: target)
        }
        #expect(throws: DataFileCrypto.Failure.wrongPassphrase) {
            try DataTransfer.preview(file, passphrase: "Fixture-wrong", in: target)
        }
        #expect(try target.fetch(FetchDescriptor<Person>()).isEmpty)
    }

    @Test("End to end: export, import into an empty store, same data; import again, nothing changes")
    func endToEnd() throws {
        let sourceContainer = try makeTestContainer()
        let source = sourceContainer.mainContext
        try seed(source)
        let original = try DataTransfer.snapshot(in: source)
        let file = try DataTransfer.exportEncrypted(in: source, passphrase: "  Fixture-pass ")

        let targetContainer = try makeTestContainer()

        let target = targetContainer.mainContext
        let first = try importFile(file, passphrase: "Fixture-pass", into: target)
        // 2 people, 2 documents, 1 aircraft, 1 trip, 2 flights; the deleted aircraft is not inserted.
        #expect(first.inserted == 8)
        #expect(first.untouched == 1)
        #expect(normalised(try DataTransfer.snapshot(in: target)) == normalised(original))

        let again = try DataTransfer.preview(file, passphrase: "Fixture-pass", in: target).summary
        #expect(again.inserted == 0)
        #expect(again.updated == 0)
        #expect(again.removed == 0)
    }
}

// MARK: - Settings flow

/// The presentation sequencing in `MoveMyDataFlow`: each next step waits for
/// the current sheet or alert to be gone, or SwiftUI drops it.
@Suite("Move my data: settings flow")
@MainActor
struct MoveMyDataFlowTests {

    /// Lets the `DispatchQueue.main.async` hand-offs run.
    private func nextRunloopTurn() async {
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    @Test("The import result waits for the preview alert to close, then shows")
    func importResultWaitsForAlert() async throws {
        // Held: a context outlives nothing once its container is freed.
        let container = try makeTestContainer()
        let context = container.mainContext
        let file = InterchangeDocument(exportedAt: t3, people: [
            person(UUID().uuidString.lowercased(), "Flowtest", t1),
        ])
        let preview = try DataTransfer.preview(try InterchangeMerge.encode(file), passphrase: nil, in: context)
        let flow = MoveMyDataFlow()
        flow.notice = .preview(preview)

        flow.confirmImport(preview, in: context)
        // Still the preview: setting the result now would be wiped by the
        // closing alert's binding.
        guard case .preview = flow.notice else { Issue.record("result shown too early"); return }

        flow.alertDismissed()
        #expect(flow.notice == nil)
        await nextRunloopTurn()
        guard case .imported(let summary) = flow.notice else { Issue.record("no result shown"); return }
        #expect(summary.inserted == 1)
    }

    @Test("Closing a plain alert shows nothing after it")
    func plainAlertDismissal() async {
        let flow = MoveMyDataFlow()
        flow.notice = .failure("Flowtest")
        flow.alertDismissed()
        await nextRunloopTurn()
        #expect(flow.notice == nil)
    }

    @Test("The save panel opens only once the passphrase sheet has closed")
    func exporterWaitsForSheet() throws {
        // Held: a context outlives nothing once its container is freed.
        let container = try makeTestContainer()
        let context = container.mainContext
        let flow = MoveMyDataFlow()
        flow.startEncryptedExport()
        #expect(flow.sheet == .exportPassphrase)

        flow.exportEncrypted(in: context)
        #expect(flow.sheet == nil)
        #expect(!flow.isExporterPresented)

        flow.sheetDismissed()
        #expect(flow.isExporterPresented)
        #expect(flow.exportFile != nil)
    }

    @Test("Swiping the passphrase sheet away drops the file and passphrase")
    func swipeDismissClearsPendingImport() async throws {
        // Held: a context outlives nothing once its container is freed.
        let container = try makeTestContainer()
        let context = container.mainContext
        let encrypted = try DataTransfer.exportEncrypted(in: context, passphrase: "Flowtest-pass")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoveMyDataFlowTests-\(UUID().uuidString).ffdata")
        try encrypted.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let flow = MoveMyDataFlow()
        flow.filePicked(.success([url]), in: context)
        await nextRunloopTurn()
        #expect(flow.sheet == .importPassphrase)
        flow.importPassphrase = "Flowtest-pass"

        // A swipe: the binding clears the sheet, then onDismiss runs.
        flow.sheet = nil
        flow.sheetDismissed()
        #expect(flow.importPassphrase.isEmpty)

        // Nothing is left to open.
        flow.importPassphrase = "Flowtest-pass"
        flow.openWithPassphrase(in: context)
        #expect(flow.notice == nil)
        flow.sheetDismissed()
        #expect(flow.notice == nil)
    }
}

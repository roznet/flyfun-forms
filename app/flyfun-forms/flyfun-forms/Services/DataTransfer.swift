import Foundation
import SwiftData

/// Moves the whole dataset in and out of the app: the SwiftData edge of
/// "Move my data".
///
/// Two features, one serializer: an encrypted file for carrying data to
/// another device, and a plaintext one for GDPR Art. 20 portability. They
/// differ only in the wrapper. The format and merge are pure
/// (`Interchange.swift`); this file only maps models to records and back.
/// Mirrors Android's `data/DataTransfer.kt`. See
/// designs/future/move-my-data.md.
@MainActor
enum DataTransfer {

    enum Failure: LocalizedError, Equatable {
        /// An encrypted file was opened without a passphrase.
        case needsPassphrase

        var errorDescription: String? {
            String(localized: "This file needs its passphrase.")
        }
    }

    /// A decoded file and what importing it would change. Nothing written yet.
    struct ImportPreview {
        let document: InterchangeDocument
        let summary: MergeSummary
    }

    static var currentExporter: ExportedBy {
        #if os(macOS)
        let platform = "macos"
        #else
        let platform = "ios"
        #endif
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return ExportedBy(platform: platform, appVersion: version)
    }

    // MARK: - Export

    /// Everything this device holds, tombstones included, in file shape.
    ///
    /// Travel documents without a person are left out: the format requires a
    /// `personId`, and such a document (left behind by deleting its person) is
    /// not reachable in the app anyway.
    static func snapshot(
        in context: ModelContext,
        // Optional rather than defaulting to `currentExporter`: a default
        // argument is evaluated off the main actor, where that property isn't.
        exportedBy: ExportedBy? = nil,
        now: Date = .now
    ) throws -> InterchangeDocument {
        // No record may lack an id; this is a no-op once launch has run it.
        try StableRecords.backfill(in: context)

        let people = try context.fetch(FetchDescriptor<Person>())
        let documents = try context.fetch(FetchDescriptor<TravelDocument>())
        let aircraft = try context.fetch(FetchDescriptor<Aircraft>())
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let flights = try context.fetch(FetchDescriptor<Flight>())
        let tombstones = try Tombstones(context.fetch(FetchDescriptor<DeletedRecord>()))

        var flightPeople: [FlightPersonRecord] = []
        for flight in flights {
            guard let flightId = idString(flight.uuid) else { continue }
            for (role, members) in [(FlightPersonRecord.crew, flight.crewList),
                                    (FlightPersonRecord.passenger, flight.passengerList)] {
                for (seat, person) in members.enumerated() {
                    guard let personId = idString(person.uuid) else { continue }
                    flightPeople.append(FlightPersonRecord(
                        flightId: flightId, personId: personId, role: role, seatOrder: seat
                    ))
                }
            }
        }

        return InterchangeDocument(
            exportedAt: InterchangeTime.format(now),
            exportedBy: exportedBy ?? Self.currentExporter,
            people: people.compactMap { record($0) } + tombstones.records(Person.self, live: people),
            travelDocuments: documents.filter { $0.person?.uuid != nil }.compactMap { record($0) }
                + tombstones.records(TravelDocument.self, live: documents),
            aircraft: aircraft.compactMap { record($0) } + tombstones.records(Aircraft.self, live: aircraft),
            trips: trips.compactMap { record($0) } + tombstones.records(Trip.self, live: trips),
            flights: flights.compactMap { record($0) } + tombstones.records(Flight.self, live: flights),
            flightPeople: flightPeople
        )
    }

    /// The encrypted "Move my data" file.
    static func exportEncrypted(in context: ModelContext, passphrase: String) throws -> Data {
        try DataFileCrypto.encrypt(InterchangeMerge.encode(snapshot(in: context)), passphrase: passphrase)
    }

    /// The plaintext GDPR copy. Machine-readable by design, not encrypted.
    static func exportPlain(in context: ModelContext) throws -> Data {
        try InterchangeMerge.encode(snapshot(in: context))
    }

    // MARK: - Import

    /// Decodes a file and works out what importing it would change, without
    /// writing anything, so the user can be shown first.
    ///
    /// - Throws: ``Failure/needsPassphrase`` for an encrypted file without
    ///   one, ``DataFileCrypto/Failure`` for a wrong passphrase or a foreign
    ///   header, ``InterchangeMerge/Failure`` for a file that is not ours or is
    ///   too new.
    static func preview(_ data: Data, passphrase: String?, in context: ModelContext) throws -> ImportPreview {
        let plaintext: Data
        if DataFileCrypto.looksEncrypted(data) {
            guard let passphrase else { throw Failure.needsPassphrase }
            plaintext = try DataFileCrypto.decrypt(data, passphrase: passphrase)
        } else {
            plaintext = data
        }
        let document = try InterchangeMerge.decode(plaintext)
        return ImportPreview(
            document: document,
            summary: InterchangeMerge.summarise(local: try localSnapshot(in: context), document: document)
        )
    }

    /// What the merge compares against: every live record, plus a tombstone
    /// record for each `DeletedRecord`, so a deletion made here is weighed
    /// against the file just as Android weighs its soft-deleted rows.
    static func localSnapshot(in context: ModelContext) throws -> InterchangeMerge.LocalSnapshot {
        try StableRecords.backfill(in: context)
        let people = try context.fetch(FetchDescriptor<Person>())
        let documents = try context.fetch(FetchDescriptor<TravelDocument>())
        let aircraft = try context.fetch(FetchDescriptor<Aircraft>())
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let flights = try context.fetch(FetchDescriptor<Flight>())
        let tombstones = try Tombstones(context.fetch(FetchDescriptor<DeletedRecord>()))
        return InterchangeMerge.LocalSnapshot(
            people: people.compactMap { record($0) } + tombstones.records(Person.self, live: people),
            // Orphan documents too: a file carrying one must update it, not
            // insert a second copy with the same uuid.
            travelDocuments: documents.compactMap { record($0) } + tombstones.records(TravelDocument.self, live: documents),
            aircraft: aircraft.compactMap { record($0) } + tombstones.records(Aircraft.self, live: aircraft),
            trips: trips.compactMap { record($0) } + tombstones.records(Trip.self, live: trips),
            flights: flights.compactMap { record($0) } + tombstones.records(Flight.self, live: flights)
        )
    }

    /// Applies a previewed merge, all or nothing.
    ///
    /// One save, inside `UpdateStamper.withoutStamping` so imported records
    /// keep the file's `updatedAt`. Any failure rolls the context back: a
    /// half-applied import of passport records is worse than a failed one.
    /// Pending user edits are saved first, normally stamped, so the rollback
    /// can only discard the import.
    static func apply(_ summary: MergeSummary, in context: ModelContext) throws {
        if context.hasChanges { try context.save() }
        try UpdateStamper.withoutStamping {
            do {
                try Applier(context: context).apply(summary)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    // MARK: - Model → record

    private static func idString(_ uuid: UUID?) -> String? { uuid?.uuidString.lowercased() }

    private static func stamp(_ date: Date?) -> String {
        date.map(InterchangeTime.format) ?? InterchangeTime.oldest
    }

    private static func record(_ p: Person) -> PersonRecord? {
        guard let id = idString(p.uuid) else { return nil }
        // The legacy flat ID fields and `nationality` are not exported:
        // `migrateDocuments` has already moved them onto travel documents.
        return PersonRecord(
            id: id, firstName: p.firstName, lastName: p.lastName,
            dateOfBirth: p.dateOfBirth.map { InterchangeDay.format($0) }, sex: p.sex,
            placeOfBirth: p.placeOfBirth, address: p.address, phone: p.phone, email: p.email,
            isUsualCrew: p.isUsualCrew, updatedAt: stamp(p.updatedAt)
        )
    }

    private static func record(_ d: TravelDocument) -> TravelDocumentRecord? {
        guard let id = idString(d.uuid) else { return nil }
        return TravelDocumentRecord(
            id: id, personId: Self.idString(d.person?.uuid) ?? "", docType: d.docType, docNumber: d.docNumber,
            issuingCountry: d.issuingCountry, expiryDate: d.expiryDate.map { InterchangeDay.format($0) },
            isActive: d.isActive, updatedAt: stamp(d.updatedAt)
        )
    }

    private static func record(_ a: Aircraft) -> AircraftRecord? {
        guard let id = idString(a.uuid) else { return nil }
        return AircraftRecord(
            id: id, registration: a.registration, type: a.type, owner: a.owner,
            ownerAddress: a.ownerAddress, isAirplane: a.isAirplane, usualBase: a.usualBase,
            ownerPersonId: Self.idString(a.ownerPerson?.uuid), useCompanyOperator: a.useCompanyOperator,
            operatorName: a.operatorName, updatedAt: stamp(a.updatedAt)
        )
    }

    private static func record(_ t: Trip) -> TripRecord? {
        guard let id = idString(t.uuid) else { return nil }
        return TripRecord(
            id: id, name: t.name, createdAt: InterchangeTime.format(t.createdAt),
            extraFields: t.extraFields, updatedAt: stamp(t.updatedAt)
        )
    }

    private static func record(_ f: Flight) -> FlightRecord? {
        guard let id = idString(f.uuid) else { return nil }
        // The resolved instants, never the stored optional ones or the legacy
        // day + time pair: `departureDateTime` is what the app shows and sends.
        return FlightRecord(
            id: id, originICAO: f.originICAO, destinationICAO: f.destinationICAO,
            departureInstant: InterchangeTime.format(f.departureDateTime),
            arrivalInstant: InterchangeTime.format(f.arrivalDateTime),
            nature: f.nature, observations: f.observations, contact: f.contact,
            reasonForVisit: f.reasonForVisit, aircraftId: Self.idString(f.aircraft?.uuid),
            responsiblePersonId: Self.idString(f.responsiblePerson?.uuid), tripId: Self.idString(f.trip?.uuid),
            legOrder: f.legOrder, chosenDocNumbers: f.chosenDocNumbers, updatedAt: stamp(f.updatedAt)
        )
    }
}

// MARK: - Tombstones

/// The local `DeletedRecord`s by kind and uuid, keeping the latest deletion of each.
@MainActor
private struct Tombstones {
    /// kind → uuid → deletedAt
    private var latest: [String: [UUID: Date]] = [:]

    init(_ rows: [DeletedRecord]) {
        for row in rows {
            guard let uuid = row.uuid else { continue }
            let deletedAt = row.deletedAt ?? Date(timeIntervalSince1970: 0)
            if let known = latest[row.kind]?[uuid], known >= deletedAt { continue }
            latest[row.kind, default: [:]][uuid] = deletedAt
        }
    }

    /// Minimal records `{ id, updatedAt: deletedAt, deletedAt }` for every
    /// tombstone of `T`'s kind, with the kind's required fields filled from
    /// `deletedAt`. A uuid that is live again (an import brought it back, or
    /// two devices raced through CloudKit) is skipped: the live record wins.
    func records<T: StableRecord & TombstoneShaped>(_ type: T.Type, live: [T]) -> [T.Tombstone] {
        let liveIds = Set(live.compactMap(\.uuid))
        return (latest[T.recordKind] ?? [:])
            .filter { !liveIds.contains($0.key) }
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { uuid, deletedAt in
                T.tombstone(id: uuid.uuidString.lowercased(), deletedAt: InterchangeTime.format(deletedAt))
            }
    }
}

/// The interchange record type a model maps to, and its tombstone shape.
protocol TombstoneShaped {
    associatedtype Tombstone: InterchangeRecord
    static func tombstone(id: String, deletedAt: String) -> Tombstone
}

extension Person: TombstoneShaped {
    static func tombstone(id: String, deletedAt: String) -> PersonRecord {
        PersonRecord(id: id, updatedAt: deletedAt, deletedAt: deletedAt)
    }
}

extension TravelDocument: TombstoneShaped {
    /// `personId` is required by the format; a tombstone has no person.
    static func tombstone(id: String, deletedAt: String) -> TravelDocumentRecord {
        TravelDocumentRecord(id: id, personId: "", updatedAt: deletedAt, deletedAt: deletedAt)
    }
}

extension Aircraft: TombstoneShaped {
    static func tombstone(id: String, deletedAt: String) -> AircraftRecord {
        AircraftRecord(id: id, updatedAt: deletedAt, deletedAt: deletedAt)
    }
}

extension Trip: TombstoneShaped {
    static func tombstone(id: String, deletedAt: String) -> TripRecord {
        TripRecord(id: id, createdAt: deletedAt, updatedAt: deletedAt, deletedAt: deletedAt)
    }
}

extension Flight: TombstoneShaped {
    static func tombstone(id: String, deletedAt: String) -> FlightRecord {
        FlightRecord(
            id: id, departureInstant: deletedAt, arrivalInstant: deletedAt,
            updatedAt: deletedAt, deletedAt: deletedAt
        )
    }
}

// MARK: - Record → model

/// Writes a `MergeSummary` into a context. Does not save; `DataTransfer.apply`
/// owns the save and the rollback.
@MainActor
private struct Applier {
    let context: ModelContext

    func apply(_ summary: MergeSummary) throws {
        var tombstones = try context.fetch(FetchDescriptor<DeletedRecord>())

        // Parents before children, so references resolve to records this
        // import has just written: people, aircraft, trips, documents, flights.
        var people = try index(Person.self)
        for record in summary.people.insert + summary.people.update {
            let person = try upsert(record, in: &people, tombstones: &tombstones) { Person() }
            person.firstName = record.firstName
            person.lastName = record.lastName
            person.dateOfBirth = record.dateOfBirth.flatMap { InterchangeDay.parse($0) }
            person.sex = record.sex
            person.placeOfBirth = record.placeOfBirth
            person.address = record.address
            person.phone = record.phone
            person.email = record.email
            person.isUsualCrew = record.isUsualCrew
        }
        try remove(summary.people.remove, from: &people, tombstones: &tombstones)

        var aircraft = try index(Aircraft.self)
        for record in summary.aircraft.insert + summary.aircraft.update {
            let plane = try upsert(record, in: &aircraft, tombstones: &tombstones) { Aircraft() }
            plane.registration = record.registration
            plane.type = record.type
            plane.owner = record.owner
            plane.ownerAddress = record.ownerAddress
            plane.isAirplane = record.isAirplane
            plane.usualBase = record.usualBase
            plane.ownerPerson = lookup(record.ownerPersonId, in: people)
            plane.useCompanyOperator = record.useCompanyOperator
            plane.operatorName = record.operatorName
        }
        try remove(summary.aircraft.remove, from: &aircraft, tombstones: &tombstones)

        var trips = try index(Trip.self)
        for record in summary.trips.insert + summary.trips.update {
            let trip = try upsert(record, in: &trips, tombstones: &tombstones) { Trip() }
            trip.name = record.name
            trip.createdAt = try instant(record.createdAt)
            if record.extraFields.isEmpty {
                trip.extraFieldsData = nil
            } else {
                trip.extraFields = record.extraFields
            }
        }
        try remove(summary.trips.remove, from: &trips, tombstones: &tombstones)

        var documents = try index(TravelDocument.self)
        for record in summary.travelDocuments.insert + summary.travelDocuments.update {
            let document = try upsert(record, in: &documents, tombstones: &tombstones) { TravelDocument() }
            document.docType = record.docType
            document.docNumber = record.docNumber
            document.issuingCountry = record.issuingCountry
            document.expiryDate = record.expiryDate.flatMap { InterchangeDay.parse($0) }
            document.isActive = record.isActive
            document.person = lookup(record.personId, in: people)
        }
        try remove(summary.travelDocuments.remove, from: &documents, tombstones: &tombstones)

        var flights = try index(Flight.self)
        for record in summary.flights.insert + summary.flights.update {
            let flight = try upsert(record, in: &flights, tombstones: &tombstones) { Flight() }
            flight.originICAO = record.originICAO
            flight.destinationICAO = record.destinationICAO
            // The setters write the instant and the legacy pair together.
            flight.departureDateTime = try instant(record.departureInstant)
            flight.arrivalDateTime = try instant(record.arrivalInstant)
            flight.nature = record.nature
            flight.observations = record.observations
            flight.contact = record.contact
            flight.reasonForVisit = record.reasonForVisit
            flight.aircraft = lookup(record.aircraftId, in: aircraft)
            flight.responsiblePerson = lookup(record.responsiblePersonId, in: people)
            flight.trip = lookup(record.tripId, in: trips)
            flight.legOrder = record.legOrder
            flight.chosenDocNumbers = record.chosenDocNumbers

            // Membership rides with its flight: replaced wholesale for every
            // flight written, so someone taken off on the other device comes
            // off here too. Flights the merge does not write keep theirs.
            let rows = summary.flightPeople.filter { $0.flightId == record.id }
            flight.crew = members(rows, role: FlightPersonRecord.crew, people: people)
            flight.passengers = members(rows, role: FlightPersonRecord.passenger, people: people)
        }
        try remove(summary.flights.remove, from: &flights, tombstones: &tombstones)
    }

    // MARK: Helpers

    private func index<T: StableRecord>(_ type: T.Type) throws -> [UUID: T] {
        var byId: [UUID: T] = [:]
        for record in try context.fetch(FetchDescriptor<T>()) {
            guard let uuid = record.uuid, byId[uuid] == nil else { continue }
            byId[uuid] = record
        }
        return byId
    }

    /// The live record with `record.id`, or a new one keeping the file's id,
    /// with the file's `updatedAt`. A local tombstone for it goes: the merge
    /// only writes a live record over one when the file's edit is newer than
    /// the deletion here.
    private func upsert<T: StableRecord, R: InterchangeRecord>(
        _ record: R,
        in live: inout [UUID: T],
        tombstones: inout [DeletedRecord],
        make: () -> T
    ) throws -> T {
        guard let uuid = UUID(uuidString: record.id) else { throw InterchangeMerge.Failure.notOurFile }
        let model: T
        if let existing = live[uuid] {
            model = existing
        } else {
            model = make()
            model.uuid = uuid
            context.insert(model)
            live[uuid] = model
        }
        model.updatedAt = try instant(record.updatedAt)

        tombstones.removeAll { row in
            guard row.kind == T.recordKind, row.uuid == uuid else { return false }
            context.delete(row)
            return true
        }
        return model
    }

    /// Deletes each record the file says was deleted, and writes a local
    /// `DeletedRecord` so the deletion keeps travelling on the next export.
    private func remove<T: StableRecord, R: InterchangeRecord>(
        _ records: [R],
        from live: inout [UUID: T],
        tombstones: inout [DeletedRecord]
    ) throws {
        for record in records {
            guard let uuid = UUID(uuidString: record.id) else { throw InterchangeMerge.Failure.notOurFile }
            let deletedAt = try instant(record.deletedAt ?? record.updatedAt)
            if let existing = live.removeValue(forKey: uuid) {
                context.delete(existing)
            }
            if let row = tombstones.first(where: { $0.kind == T.recordKind && $0.uuid == uuid }) {
                // Already deleted here, earlier: carry the later deletion.
                row.deletedAt = max(row.deletedAt ?? deletedAt, deletedAt)
            } else {
                let row = DeletedRecord(uuid: uuid, kind: T.recordKind, deletedAt: deletedAt)
                context.insert(row)
                tombstones.append(row)
            }
        }
    }

    /// A reference that resolves neither locally nor in the file becomes nil.
    private func lookup<T>(_ id: String?, in live: [UUID: T]) -> T? {
        id.flatMap(UUID.init(uuidString:)).flatMap { live[$0] }
    }

    private func members(_ rows: [FlightPersonRecord], role: String, people: [UUID: Person]) -> [Person] {
        rows.filter { $0.role == role }
            .sorted { $0.seatOrder < $1.seatOrder }
            .compactMap { lookup($0.personId, in: people) }
    }

    /// A required instant the file should always carry. Unreadable means the
    /// file is not one of ours: refuse it whole rather than import part of it.
    private func instant(_ value: String) throws -> Date {
        guard let date = InterchangeTime.parse(value) else { throw InterchangeMerge.Failure.notOurFile }
        return date
    }
}

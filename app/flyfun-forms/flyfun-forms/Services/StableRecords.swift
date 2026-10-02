import Foundation
import SwiftData

// Stable identity and change tracking for "Move my data".
// See designs/future/move-my-data.md §7.
//
// `persistentModelID` is local to one store on one device, so a record needs
// its own `uuid` to be recognised in a file from another device, and an
// `updatedAt` so a merge can tell which copy is newer. Both are optional:
// CloudKit requires new attributes to be optional or defaulted, and a declared
// `= UUID()` default can be applied as one constant to every existing row
// during migration. Existing rows get a uuid from `StableRecords.backfill`;
// their `updatedAt` stays nil, which a merge treats as older than anything.

/// A model that travels in the interchange file.
protocol StableRecord: PersistentModel {
    var uuid: UUID? { get set }
    var updatedAt: Date? { get set }
    /// The interchange array it belongs to, as stored in `DeletedRecord.kind`.
    static var recordKind: String { get }
}

extension Person: StableRecord { static var recordKind: String { "person" } }
extension TravelDocument: StableRecord { static var recordKind: String { "travelDocument" } }
extension Aircraft: StableRecord { static var recordKind: String { "aircraft" } }
extension Flight: StableRecord { static var recordKind: String { "flight" } }
extension Trip: StableRecord { static var recordKind: String { "trip" } }

extension ModelContext {
    /// Deletes a record the user chose to delete, leaving a `DeletedRecord` so
    /// the deletion reaches other devices through the next export.
    ///
    /// Every user-initiated delete goes through here. "Delete all data" does
    /// not: erasing this device must not erase another one through a file.
    ///
    /// A person takes their travel documents with them, each with its own
    /// tombstone. Not a `.cascade` delete rule: a cascade would delete the
    /// documents without passing through here, so they would get no
    /// tombstone, and it would be a CloudKit schema change. See
    /// designs/ios-app.md.
    func deleteRecordingTombstone<T: StableRecord>(_ record: T, at date: Date = .now) {
        if let person = record as? Person {
            // One already deleted in this unsaved context keeps its first
            // tombstone. `deletedModelsArray` as well as `isDeleted`, which
            // has not always been set before the save.
            let pending = Set(deletedModelsArray.map { $0.persistentModelID })
            for document in person.documentList
            where !document.isDeleted && !pending.contains(document.persistentModelID) {
                deleteRecordingTombstone(document, at: date)
            }
        }
        // A record without a uuid was never exportable, so no other device can
        // know it and there is nothing to propagate.
        if let uuid = record.uuid {
            insert(DeletedRecord(uuid: uuid, kind: T.recordKind, deletedAt: date))
        }
        delete(record)
    }
}

@MainActor
enum StableRecords {

    static let models: [any StableRecord.Type] = [
        Person.self, TravelDocument.self, Aircraft.self, Flight.self, Trip.self,
    ]

    /// Gives every record without a `uuid` its own.
    ///
    /// Runs every launch rather than once, like `backfillScheduleInstants`: a
    /// device on an older build keeps creating records without one, and they
    /// arrive here through CloudKit. Saves only when something changed, so the
    /// steady state writes nothing, and without stamping `updatedAt` - giving a
    /// record an id is not an edit, and stamping "now" would let stale data win
    /// the next merge. Returns how many records it changed.
    @discardableResult
    static func backfill(in context: ModelContext) throws -> Int {
        var assigned = 0
        for type in models {
            assigned += try backfill(type, in: context)
        }
        if assigned > 0 {
            try UpdateStamper.withoutStamping { try context.save() }
        }
        return assigned
    }

    // MARK: - Orphan documents

    /// How long a travel document must have had no person, as seen on this
    /// device, and gone unedited, before the launch cleanup deletes it.
    static let orphanMargin: TimeInterval = 24 * 60 * 60

    /// Deletes travel documents left without a person, with a tombstone each.
    ///
    /// Builds before #44 deleted a person and left their documents behind,
    /// and a device still on such a build keeps doing it until it updates, so
    /// this runs every launch; the steady state finds nothing and saves
    /// nothing.
    ///
    /// A document can also look orphaned only because CloudKit delivered it
    /// before its person, typically on a fresh device. Deleting it then would
    /// sync the deletion back and lose the passport everywhere, so a document
    /// goes only once it has been seen without a person, on this device, for
    /// `orphanMargin` (`firstSeen`, kept by the caller between launches), and
    /// has not been edited within that margin either. `updatedAt` alone is not
    /// enough: every document from before stable ids has none.
    ///
    /// `firstSeen` comes back holding only the documents still orphaned and
    /// kept. Returns how many documents it deleted.
    @discardableResult
    static func deleteOrphanDocuments(
        in context: ModelContext,
        firstSeen: inout [UUID: Date],
        now: Date = .now
    ) throws -> Int {
        let cutoff = now.addingTimeInterval(-orphanMargin)
        var stillOrphaned: [UUID: Date] = [:]
        var deleted = 0
        for document in try context.fetch(FetchDescriptor<TravelDocument>()) where document.person == nil {
            // No uuid yet: the backfill gives it one, and the next launch can track it.
            guard let uuid = document.uuid else { continue }
            let seen = firstSeen[uuid] ?? now
            let unedited = (document.updatedAt ?? .distantPast) <= cutoff
            if seen <= cutoff && unedited {
                context.deleteRecordingTombstone(document, at: now)
                deleted += 1
            } else {
                stillOrphaned[uuid] = seen
            }
        }
        firstSeen = stillOrphaned
        // A cleanup, not an edit; see `backfill`.
        if deleted > 0 {
            try UpdateStamper.withoutStamping { try context.save() }
        }
        return deleted
    }

    private static let orphanFirstSeenKey = "orphanDocumentsFirstSeen"

    /// The launch step: `deleteOrphanDocuments` with `firstSeen` kept in
    /// `defaults`. Local to this device on purpose: the point is how long
    /// *this* store has seen the document without its person.
    static func deleteOrphanDocuments(in context: ModelContext, defaults: UserDefaults) throws {
        let stored = defaults.dictionary(forKey: orphanFirstSeenKey) as? [String: Date] ?? [:]
        var firstSeen: [UUID: Date] = [:]
        for (key, date) in stored {
            if let uuid = UUID(uuidString: key) { firstSeen[uuid] = date }
        }
        defer {
            if firstSeen.isEmpty {
                defaults.removeObject(forKey: orphanFirstSeenKey)
            } else {
                var updated: [String: Date] = [:]
                for (uuid, date) in firstSeen { updated[uuid.uuidString] = date }
                defaults.set(updated, forKey: orphanFirstSeenKey)
            }
        }
        try deleteOrphanDocuments(in: context, firstSeen: &firstSeen)
    }

    private static func backfill<T: StableRecord>(_ type: T.Type, in context: ModelContext) throws -> Int {
        let missing = try context.fetch(FetchDescriptor<T>(predicate: #Predicate { $0.uuid == nil }))
        for record in missing {
            record.uuid = UUID()
        }
        return missing.count
    }
}

/// Sets `updatedAt` on every inserted or changed `StableRecord` as it is saved.
///
/// One observer rather than a line in each edit view, where one would
/// inevitably be missed - most edits are bindings saved by autosave, with no
/// explicit save call to hang it on. Changes arriving from CloudKit are merged
/// in by the mirror, not saved through a `ModelContext`, so they keep the
/// `updatedAt` the other device gave them.
///
/// A change to a relationship counts as a change on both ends, so adding a
/// person to a flight also moves the person's `updatedAt`. That only makes the
/// person look a little newer than it is; accepted.
@MainActor
enum UpdateStamper {

    private static var observer: NSObjectProtocol?
    private static var isSuspended = false

    /// Starts stamping. Idempotent; call before the first save.
    static func install() {
        guard observer == nil else { return }
        // queue nil: the handler runs synchronously on the saving thread, inside
        // the save, so what it sets is part of the same save.
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: nil, queue: nil
        ) { notification in
            // Every ModelContext in the app is the main one. A background
            // context saving off the main thread would go unstamped rather
            // than touch main-actor state from the wrong thread.
            guard Thread.isMainThread, let context = notification.object as? ModelContext else { return }
            MainActor.assumeIsolated { stamp(context) }
        }
    }

    /// Runs `body` - which must save - without moving `updatedAt`.
    ///
    /// For writes that are not user edits: an import, which must keep the
    /// file's `updatedAt`, and the launch backfills. Synchronous on the main
    /// actor, so no other save can run in between. Anything else pending in
    /// the context when `body` saves goes unstamped too; the launch backfills
    /// run before the user can have edited anything.
    static func withoutStamping<R>(_ body: () throws -> R) rethrows -> R {
        let wasSuspended = isSuspended
        isSuspended = true
        defer { isSuspended = wasSuspended }
        return try body()
    }

    static func stamp(_ context: ModelContext, now: Date = .now) {
        for model in context.insertedModelsArray {
            guard let record = model as? any StableRecord else { continue }
            // Every init assigns a uuid; this catches anything created some
            // other way. Not a timestamp, so not subject to suspension.
            if record.uuid == nil { record.uuid = UUID() }
            if !isSuspended { record.updatedAt = now }
        }
        guard !isSuspended else { return }
        for model in context.changedModelsArray {
            guard let record = model as? any StableRecord else { continue }
            record.updatedAt = now
        }
    }
}

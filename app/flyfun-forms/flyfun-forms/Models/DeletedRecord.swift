import Foundation
import SwiftData

/// A deletion, remembered so "Move my data" can carry it to another device.
///
/// Deletes on iOS stay real deletes; this row is what is left behind. Without
/// it, importing a file from a device that still has the record would quietly
/// bring it back. Android keeps soft-deleted rows instead; this table exists so
/// iOS does not have to filter deleted rows out of every query and
/// relationship. See designs/future/move-my-data.md §7.
@Model
final class DeletedRecord {
    /// The deleted record's `uuid`.
    var uuid: UUID?
    /// Which array of the interchange file it belongs to: `StableRecord.recordKind`.
    var kind: String = ""
    var deletedAt: Date?

    init(uuid: UUID, kind: String, deletedAt: Date) {
        self.uuid = uuid
        self.kind = kind
        self.deletedAt = deletedAt
    }
}

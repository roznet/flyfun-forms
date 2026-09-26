import Foundation
import SwiftData

/// Every `@Model` type the app stores. The app's `ModelContainer` is built
/// from this list, so a new model cannot be added to the store without
/// `LocalDataEraser` deleting it too.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Person.self,
        TravelDocument.self,
        Aircraft.self,
        Flight.self,
        Trip.self,
    ]

    static var schema: Schema { Schema(models) }
}

/// Settings → Delete All Data (GDPR.md §7): removes everything the app holds
/// about people, their documents, aircraft, flights and trips.
///
/// The store is CloudKit-synced, so this deletes from iCloud and from every
/// device on the same Apple ID, not just this one. It leaves the FlightForms
/// account and the Keychain alone: the user stays signed in.
@MainActor
enum LocalDataEraser {
    /// Deletes every record of every `AppSchema` model, then every generated
    /// form still on disk. Returns how many records were deleted.
    ///
    /// Records are deleted one by one rather than with `delete(model:)`: a
    /// batch delete bypasses the context, and it is the context's per-object
    /// changes that the CloudKit mirror exports.
    @discardableResult
    static func eraseAll(
        in context: ModelContext,
        formFiles: GeneratedFormFiles = .standard
    ) throws -> Int {
        var deleted = 0
        for type in AppSchema.models {
            deleted += try deleteAll(type, in: context)
        }
        try context.save()
        formFiles.removeAll()
        return deleted
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        let records = try context.fetch(FetchDescriptor<T>())
        for record in records {
            context.delete(record)
        }
        return records.count
    }
}

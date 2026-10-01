import Foundation
import SwiftData

@Model
final class Trip {
    var name: String = ""
    var createdAt: Date = Date()
    var extraFieldsData: Data?

    // Move-my-data identity; see StableRecords.swift.
    var uuid: UUID?
    var updatedAt: Date?

    @Relationship(inverse: \Flight.trip)
    var legs: [Flight]?

    var extraFields: [String: String] {
        get {
            guard let data = extraFieldsData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            extraFieldsData = try? JSONEncoder().encode(newValue)
        }
    }

    var sortedLegs: [Flight] {
        (legs ?? []).sorted { $0.legOrder < $1.legOrder }
    }

    init(name: String = "") {
        self.uuid = UUID()
        self.name = name
    }
}

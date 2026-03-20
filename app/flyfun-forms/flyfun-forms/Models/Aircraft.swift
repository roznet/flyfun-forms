import Foundation
import SwiftData

@Model
final class Aircraft {
    var registration: String = ""
    var type: String = ""
    var owner: String?
    var ownerAddress: String?
    var isAirplane: Bool = true
    var usualBase: String?
    var ownerPerson: Person?

    // CloudKit inverse
    @Relationship(inverse: \Flight.aircraft)
    var flights: [Flight]?

    var displayName: String {
        let reg = registration.trimmingCharacters(in: .whitespaces)
        return reg.isEmpty ? String(localized: "New Aircraft") : reg
    }

    init(registration: String = "", type: String = "") {
        self.registration = registration
        self.type = type
    }
}

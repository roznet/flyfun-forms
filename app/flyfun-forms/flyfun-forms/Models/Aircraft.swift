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
    var useCompanyOperator: Bool = false
    var operatorName: String?

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

// MARK: - Choosing one for a new flight

extension Aircraft {
    /// The aircraft a new flight should start on, or nil when there is nothing
    /// to go on.
    ///
    /// Most pilots fly one aircraft, or the same one for a stretch, so leaving
    /// the picker on "None" asked every new flight for an answer that was
    /// already known. A wrong guess costs one tap in a picker the pilot can see;
    /// no guess costs one every time.
    ///
    /// The last one flown wins over the only one on file, so a second aircraft
    /// added mid-season doesn't keep offering the aircraft it replaced.
    ///
    /// Pure and static so the rule is unit-testable without a model context.
    static func defaultForNewFlight(flights: [Flight], available: [Aircraft]) -> Aircraft? {
        let lastFlown = flights
            .filter { $0.aircraft != nil }
            .max { $0.departureDateTime < $1.departureDateTime }?
            .aircraft
        if let lastFlown { return lastFlown }
        return available.count == 1 ? available.first : nil
    }
}

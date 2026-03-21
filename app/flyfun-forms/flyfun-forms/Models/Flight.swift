import Foundation
import SwiftData

@Model
final class Flight {
    var departureDate: Date = Date()
    var departureTimeUTC: String = ""
    var arrivalDate: Date = Date()
    var arrivalTimeUTC: String = ""
    var originICAO: String = ""
    var destinationICAO: String = ""
    var nature: String = "private"
    var observations: String?
    var contact: String?
    var reasonForVisit: String?
    var responsiblePerson: Person?

    // All relationships optional for CloudKit; inverses on the other side
    var aircraft: Aircraft?
    var crew: [Person]?
    var passengers: [Person]?

    var trip: Trip?
    var legOrder: Int = 0

    /// Combines departureDate with departureTimeUTC ("HH:mm") for accurate sorting.
    var departureDateTime: Date {
        guard !departureTimeUTC.isEmpty,
              let (h, m) = parseTime(departureTimeUTC) else { return departureDate }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: departureDate) ?? departureDate
    }

    private func parseTime(_ time: String) -> (Int, Int)? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }

    var displayName: String {
        let origin = originICAO.isEmpty ? "????" : originICAO
        let dest = destinationICAO.isEmpty ? "????" : destinationICAO
        return "\(origin) > \(dest)"
    }

    // Safe accessors for nil arrays
    var crewList: [Person] { crew ?? [] }
    var passengerList: [Person] { passengers ?? [] }

    init() {}
}

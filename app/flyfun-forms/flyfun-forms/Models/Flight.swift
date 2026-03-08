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

    // All relationships optional for CloudKit; inverses on the other side
    var aircraft: Aircraft?
    var crew: [Person]?
    var passengers: [Person]?

    var trip: Trip?
    var legOrder: Int = 0

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

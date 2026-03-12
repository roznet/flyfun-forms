import Foundation
import SwiftData

@Model
final class Person {
    var firstName: String = ""
    var lastName: String = ""
    var dateOfBirth: Date?
    var nationality: String?
    var idNumber: String?
    var idType: String?
    var idIssuingCountry: String?
    var idExpiry: Date?
    var sex: String?
    var placeOfBirth: String?
    var address: String?
    var phone: String?
    var isUsualCrew: Bool = false

    var documents: [TravelDocument]?

    // CloudKit inverses
    @Relationship(inverse: \Flight.crew)
    var crewFlights: [Flight]?

    @Relationship(inverse: \Flight.passengers)
    var passengerFlights: [Flight]?

    var documentList: [TravelDocument] { documents ?? [] }

    var fullName: String { "\(firstName) \(lastName)" }

    var displayName: String {
        let name = fullName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "New Person" : name
    }

    /// Most recent flight date across all crew and passenger flights.
    var lastFlightDate: Date? {
        let crewDates = (crewFlights ?? []).map(\.departureDate)
        let paxDates = (passengerFlights ?? []).map(\.departureDate)
        return (crewDates + paxDates).max()
    }

    /// All people who have been on at least one flight with this person.
    func coTravelers(minimumFlights: Int = 2) -> [Person: Int] {
        let allFlights = (crewFlights ?? []) + (passengerFlights ?? [])
        var counts: [PersistentIdentifier: (Person, Int)] = [:]

        for flight in allFlights {
            let others = (flight.crewList + flight.passengerList)
                .filter { $0.persistentModelID != self.persistentModelID }
            for person in others {
                let id = person.persistentModelID
                counts[id] = (person, (counts[id]?.1 ?? 0) + 1)
            }
        }
        return counts.values
            .filter { $0.1 >= minimumFlights }
            .reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    init(firstName: String = "", lastName: String = "") {
        self.firstName = firstName
        self.lastName = lastName
    }
}

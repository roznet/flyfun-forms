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

    init(firstName: String = "", lastName: String = "") {
        self.firstName = firstName
        self.lastName = lastName
    }
}

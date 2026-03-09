import Foundation
import SwiftData

@Model
final class TravelDocument {
    var docType: String = "Passport"       // "Passport", "Identity card", "Other"
    var docNumber: String = ""
    var issuingCountry: String?            // ISO alpha-3 (e.g. "FRA", "GBR")
    var expiryDate: Date?

    @Relationship(inverse: \Person.documents)
    var person: Person?

    var displayLabel: String {
        let country = issuingCountry ?? "?"
        let suffix = docNumber.isEmpty ? "" : " — \(docNumber.suffix(6))"
        return "\(docType) (\(country))\(suffix)"
    }

    init(docType: String = "Passport", docNumber: String = "", issuingCountry: String? = nil, expiryDate: Date? = nil) {
        self.docType = docType
        self.docNumber = docNumber
        self.issuingCountry = issuingCountry
        self.expiryDate = expiryDate
    }
}

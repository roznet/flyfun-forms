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

    var localizedDocType: String {
        switch docType {
        case "Passport": return String(localized: "Passport", comment: "Document type")
        case "Identity card": return String(localized: "Identity card", comment: "Document type")
        default: return String(localized: "Other", comment: "Document type")
        }
    }

    var displayLabel: String {
        let country = issuingCountry ?? "?"
        let suffix = docNumber.isEmpty ? "" : " — \(docNumber.suffix(6))"
        return "\(localizedDocType) (\(country))\(suffix)"
    }

    init(docType: String = "Passport", docNumber: String = "", issuingCountry: String? = nil, expiryDate: Date? = nil) {
        self.docType = docType
        self.docNumber = docNumber
        self.issuingCountry = issuingCountry
        self.expiryDate = expiryDate
    }
}

import Foundation
import SwiftData

/// Selects the best TravelDocument for a person given a target airport.
///
/// Resolution order:
/// 1. The document chosen for this flight (`chosenDocNumbers`)
/// 2. Region match (Schengen, UK, etc.) — prefer document from matching issuing country
/// 3. Tiebreak by latest expiry date
/// 4. Fallback to first document
enum DocumentResolver {

    // MARK: - Region definitions

    private enum Region {
        case schengen
        case uk
        case other
    }

    /// ICAO prefixes → region
    private static let prefixRegions: [String: Region] = [
        // Schengen / EU
        "LF": .schengen,  // France
        "LS": .schengen,  // Switzerland (Schengen associate)
        "ED": .schengen,  // Germany
        "EB": .schengen,  // Belgium
        "EH": .schengen,  // Netherlands
        "LE": .schengen,  // Spain
        "LI": .schengen,  // Italy
        "LP": .schengen,  // Portugal
        "LO": .schengen,  // Austria
        "EL": .schengen,  // Greece (also LG)
        "LG": .schengen,  // Greece
        "LK": .schengen,  // Czech Republic
        "EP": .schengen,  // Poland
        "LH": .schengen,  // Hungary
        "LJ": .schengen,  // Slovenia
        "EV": .schengen,  // Latvia
        "EY": .schengen,  // Lithuania
        "EE": .schengen,  // Estonia
        "LM": .schengen,  // Malta
        "BI": .schengen,  // Iceland (Schengen associate)
        "EN": .schengen,  // Norway (Schengen associate)
        "EF": .schengen,  // Finland
        "ES": .schengen,  // Sweden
        "EK": .schengen,  // Denmark
        "LR": .schengen,  // Romania
        "LB": .schengen,  // Bulgaria
        "LD": .schengen,  // Croatia
        "LC": .schengen,  // Cyprus
        // UK
        "EG": .uk,
    ]

    /// ISO alpha-3 country codes for EU/Schengen issuing countries
    private static let schengenCountries: Set<String> = [
        "FRA", "DEU", "BEL", "NLD", "ESP", "ITA", "PRT", "AUT", "LUX",
        "CHE", "GRC", "CZE", "POL", "HUN", "SVN", "LVA", "LTU", "EST",
        "MLT", "ISL", "NOR", "FIN", "SWE", "DNK", "ROU", "BGR", "HRV",
        "CYP", "SVK", "IRL",
    ]

    // MARK: - Public API

    /// Resolve the best document for a person given a target airport ICAO.
    ///
    /// `chosenDocNumbers` are the documents the pilot picked by hand for the
    /// flight (`Flight.chosenDocNumbers`); one of this person's active
    /// documents in that set wins over the automatic choice.
    static func resolve(person: Person, airport: String, chosenDocNumbers: [String] = []) -> TravelDocument? {
        let docs = person.documentList.filter(\.isActive)
        guard !docs.isEmpty else { return nil }
        if docs.count == 1 { return docs[0] }

        // 1. The pilot's choice for this flight
        if let doc = chosen(person: person, in: chosenDocNumbers) {
            return doc
        }

        let prefix = String(airport.prefix(2))

        // 2. Region match
        let region = prefixRegions[prefix] ?? .other

        let regionMatches: [TravelDocument]
        switch region {
        case .schengen:
            regionMatches = docs.filter { schengenCountries.contains($0.issuingCountry ?? "") }
        case .uk:
            regionMatches = docs.filter { $0.issuingCountry == "GBR" }
        case .other:
            regionMatches = []
        }

        // 3. Pick from region matches (or all docs) by latest expiry
        let candidates = regionMatches.isEmpty ? docs : regionMatches
        return candidates.sorted { ($0.expiryDate ?? .distantPast) > ($1.expiryDate ?? .distantPast) }.first
    }

    // MARK: - Per-flight choice

    /// The person's active document picked by hand, if any.
    ///
    /// Choices are keyed by document number: unlike a model identifier it is
    /// stable across launches and devices, and syncs through CloudKit.
    static func chosen(person: Person, in chosenDocNumbers: [String]) -> TravelDocument? {
        guard !chosenDocNumbers.isEmpty else { return nil }
        return person.documentList.first { $0.isActive && !$0.docNumber.isEmpty && chosenDocNumbers.contains($0.docNumber) }
    }

    /// `chosenDocNumbers` with the person's choice set to `document`, or
    /// cleared back to automatic when `document` is nil.
    static func choosing(_ document: TravelDocument?, for person: Person, in chosenDocNumbers: [String]) -> [String] {
        let personNumbers = Set(person.documentList.map(\.docNumber))
        var result = chosenDocNumbers.filter { !personNumbers.contains($0) }
        if let document, !document.docNumber.isEmpty {
            result.append(document.docNumber)
        }
        return result
    }
}

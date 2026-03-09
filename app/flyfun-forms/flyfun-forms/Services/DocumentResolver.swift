import Foundation
import SwiftData

/// Selects the best TravelDocument for a person given a target airport.
///
/// Resolution order:
/// 1. User override (remembered choice for this person + airport prefix)
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
    static func resolve(person: Person, airport: String) -> TravelDocument? {
        let docs = person.documentList
        guard !docs.isEmpty else { return nil }
        if docs.count == 1 { return docs[0] }

        let prefix = String(airport.prefix(2))

        // 1. Check user override
        if let overrideID = userOverride(personID: person.persistentModelID.hashValue, prefix: prefix),
           let doc = docs.first(where: { $0.persistentModelID.hashValue == overrideID }) {
            return doc
        }

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

    // MARK: - User overrides (UserDefaults)

    private static let overridesKey = "documentPreferences"

    static func setOverride(personID: Int, prefix: String, documentID: Int) {
        var prefs = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Int] ?? [:]
        prefs["\(personID)_\(prefix)"] = documentID
        UserDefaults.standard.set(prefs, forKey: overridesKey)
    }

    private static func userOverride(personID: Int, prefix: String) -> Int? {
        let prefs = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Int] ?? [:]
        return prefs["\(personID)_\(prefix)"]
    }
}

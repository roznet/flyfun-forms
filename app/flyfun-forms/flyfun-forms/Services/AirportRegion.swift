import Foundation

/// The immigration region an airport sits in, for choosing a travel document
/// (`DocumentResolver`) and for counting days per region (`StayReport`).
///
/// Lookup order: exact ICAO override, then the two-letter ICAO prefix, then
/// `.other`. The table started life as a passport-choice hint, where a small
/// error is harmless; counting days needs it right, so a wrong entry here
/// shows up as days in the wrong row of the stay report.
///
/// Longer term this belongs in rzflight (see `designs/future/stay-report.md`).
/// Android keeps the same table in `core-logic/.../DocumentResolver.kt`;
/// change both together.
nonisolated enum AirportRegion: String, CaseIterable, Hashable, Sendable {
    /// The Schengen area: the region the 90/180 rule applies to.
    case schengen
    /// United Kingdom, including the Channel Islands and the Isle of Man.
    case uk
    /// EU members outside Schengen: Ireland and Cyprus.
    case euNonSchengen
    /// Everything else, including unknown prefixes.
    case other

    /// The region of an airport by ICAO code.
    static func region(for icao: String) -> AirportRegion {
        let code = icao.trimmingCharacters(in: .whitespaces).uppercased()
        if let region = exactRegions[code] { return region }
        return prefixRegions[String(code.prefix(2))] ?? .other
    }

    /// Airports whose territory is outside the region of their country prefix.
    static let exactRegions: [String: AirportRegion] = [
        "ENSB": .other,  // Svalbard: Norwegian, but outside Schengen
        "EKVG": .other,  // Faroe Islands: Danish, but outside Schengen and the EU
    ]

    /// ICAO country prefixes → region.
    static let prefixRegions: [String: AirportRegion] = [
        // Schengen
        "LF": .schengen,  // France
        "LS": .schengen,  // Switzerland (Schengen associate)
        "ED": .schengen,  // Germany
        "EB": .schengen,  // Belgium
        "EH": .schengen,  // Netherlands
        "EL": .schengen,  // Luxembourg
        "LE": .schengen,  // Spain
        "GC": .schengen,  // Canary Islands (Spain)
        "LI": .schengen,  // Italy
        "LP": .schengen,  // Portugal (incl. Azores, Madeira)
        "LO": .schengen,  // Austria
        "LG": .schengen,  // Greece
        "LK": .schengen,  // Czech Republic
        "LZ": .schengen,  // Slovakia
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
        // EU, not Schengen
        "EI": .euNonSchengen,  // Ireland
        "LC": .euNonSchengen,  // Cyprus
        // UK (incl. Channel Islands and Isle of Man)
        "EG": .uk,
        // Gibraltar (LX) is deliberately absent: it falls to `.other`.
    ]

    /// ISO alpha-3 codes of the EU and Schengen countries that issue travel
    /// documents. A holder of one of these is not subject to the Schengen
    /// short-stay rule, and an airport in `.schengen` or `.euNonSchengen`
    /// prefers a document from one of them.
    static let euOrSchengenCountries: Set<String> = [
        "FRA", "DEU", "BEL", "NLD", "ESP", "ITA", "PRT", "AUT", "LUX",
        "CHE", "GRC", "CZE", "POL", "HUN", "SVN", "LVA", "LTU", "EST",
        "MLT", "ISL", "NOR", "FIN", "SWE", "DNK", "ROU", "BGR", "HRV",
        "CYP", "SVK", "IRL",
    ]
}

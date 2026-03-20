import Foundation
import RZFlight
import FMDB

/// Singleton service wrapping RZFlight's KnownAirports for airport search.
/// Loads from a bundled `airports.db` SQLite database.
/// Call `load()` early at app startup to avoid first-access latency.
@Observable
final class AirportDatabase: @unchecked Sendable {
    static let shared = AirportDatabase()

    private var knownAirports: KnownAirports?
    private var db: FMDatabase?
    private var loadTask: Task<Void, Never>?

    var isLoaded: Bool { knownAirports != nil }

    private init() {}

    /// Trigger background loading of the airport database.
    /// Safe to call multiple times — only the first call does work.
    func load() {
        guard loadTask == nil else { return }
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard let dbPath = Bundle.main.path(forResource: "airports", ofType: "db") else {
                print("AirportDatabase: airports.db not found in bundle")
                return
            }
            let database = FMDatabase(path: dbPath)
            guard database.open() else {
                print("AirportDatabase: failed to open airports.db")
                return
            }
            let airports = KnownAirports(db: database)
            await MainActor.run {
                self.db = database
                self.knownAirports = airports
            }
        }
    }

    /// Wait until the database is ready. Returns immediately if already loaded.
    func ready() async {
        await loadTask?.value
    }

    /// Search airports by ICAO code or name. Returns up to `limit` results.
    /// Results are ranked by relevance:
    ///   1. ICAO starts with needle  (e.g. "LO" → LOWW, LOWI)
    ///   2. ICAO contains needle     (e.g. "LO" → EGLO, KALO)
    ///   3. Name word starts with needle (e.g. "lon" → London City)
    ///   4. Name contains needle      (e.g. "lo" → San Carlos)
    /// Within each tier, results are sorted alphabetically by ICAO.
    func search(needle: String, limit: Int = 20) -> [Airport] {
        guard let knownAirports, !needle.isEmpty else { return [] }
        let matches = knownAirports.matching(needle: needle)
        let ranked = Self.ranked(matches, needle: needle)
        return Array(ranked.prefix(limit))
    }

    /// Assign a relevance tier (lower = better) to an airport for the given needle.
    private static func tier(for airport: Airport, needle: String) -> Int {
        let icao = airport.icao.lowercased()
        let lowerNeedle = needle.lowercased()

        if icao.hasPrefix(lowerNeedle) { return 0 }
        if icao.contains(lowerNeedle) { return 1 }

        // Check if any word in the name starts with the needle
        let nameWords = airport.name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        if nameWords.contains(where: { $0.hasPrefix(lowerNeedle) }) { return 2 }

        return 3
    }

    /// Sort airports by relevance tier, then alphabetically by ICAO within each tier.
    static func ranked(_ airports: [Airport], needle: String) -> [Airport] {
        airports.sorted { a, b in
            let ta = tier(for: a, needle: needle)
            let tb = tier(for: b, needle: needle)
            if ta != tb { return ta < tb }
            return a.icao < b.icao
        }
    }

    /// Look up a single airport by ICAO code.
    func airport(icao: String) -> Airport? {
        guard let knownAirports, !icao.isEmpty else { return nil }
        return knownAirports.airport(icao: icao)
    }
}

import Foundation
import RZFlight
import FMDB

/// Singleton service wrapping RZFlight's KnownAirports for airport search.
/// Loads from a bundled `airports.db` SQLite database.
@Observable
final class AirportDatabase {
    static let shared = AirportDatabase()

    private var knownAirports: KnownAirports?
    private var db: FMDatabase?

    var isLoaded: Bool { knownAirports != nil }

    private init() {
        loadDatabase()
    }

    private func loadDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "airports", ofType: "db") else {
            print("AirportDatabase: airports.db not found in bundle")
            return
        }
        let database = FMDatabase(path: dbPath)
        guard database.open() else {
            print("AirportDatabase: failed to open airports.db")
            return
        }
        self.db = database
        self.knownAirports = KnownAirports(db: database)
    }

    /// Search airports by ICAO code or name. Returns up to `limit` results.
    func search(needle: String, limit: Int = 20) -> [Airport] {
        guard let knownAirports, !needle.isEmpty else { return [] }
        let results = knownAirports.matching(needle: needle)
        return Array(results.prefix(limit))
    }

    /// Look up a single airport by ICAO code.
    func airport(icao: String) -> Airport? {
        guard let knownAirports, !icao.isEmpty else { return nil }
        return knownAirports.airport(icao: icao)
    }
}

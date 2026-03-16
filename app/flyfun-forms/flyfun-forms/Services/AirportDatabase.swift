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

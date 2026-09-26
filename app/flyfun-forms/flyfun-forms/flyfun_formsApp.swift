import SwiftUI
import SwiftData

@main
struct flyfun_formsApp: App {
    @State private var appState = AppState()
    let catalog = AirportCatalog(baseURL: APIConfig.baseURL)

    init() {
        #if DEBUG
        if UITestMode.isMocked {
            UITestURLProtocol.install()
        }
        #endif
        // A filled form is removed once its share sheet or mail composer is
        // done with it, but one handed to another app (or left by a crash, or
        // by a build before the cleanup) can outlive that: nothing from a
        // previous run is still in use.
        GeneratedFormFiles.standard.removeAll()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = AppSchema.schema
        #if DEBUG
        if UITestMode.isActive {
            return UITestFixtures.makeContainer(schema: schema)
        }
        #endif
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.net.ro-z.flyfun-forms")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    ContentView()
                        .id(appState.localDataEpoch)
                        .environment(\.airportCatalog, catalog)
                        .task(id: appState.jwt) {
                            catalog.jwt = appState.jwt
                            await catalog.sync()
                        }
                } else {
                    LoginView()
                }
            }
            .environment(appState)
            .task { migrateDocuments() }
            .task { backfillScheduleInstants() }
            .task { await preloadAirportData() }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        #endif
    }

    /// Preload the airport database and warm timezone cache for airports used in recent flights.
    private func preloadAirportData() async {
        AirportDatabase.shared.load()
        await AirportDatabase.shared.ready()

        // Collect unique ICAOs from recent flights to pre-warm timezone cache
        let context = sharedModelContainer.mainContext
        var descriptor = FetchDescriptor<Flight>(sortBy: [SortDescriptor(\.departureDate, order: .reverse)])
        descriptor.fetchLimit = 20
        guard let flights = try? context.fetch(descriptor) else { return }

        var icaos = Set<String>()
        for flight in flights {
            icaos.insert(flight.originICAO)
            icaos.insert(flight.destinationICAO)
        }
        icaos.remove("")

        await AirportTimezoneCache.shared.preload(icaos: icaos)
    }

    /// Backfill each flight's canonical departure/arrival instants from the
    /// legacy date + UTC-time pair, and repair any that have drifted.
    ///
    /// Runs every launch rather than once, unlike `migrateDocuments()`. While
    /// the legacy pair is still authoritative, an edit made on a device running
    /// an older build moves the pair without knowing the instants exist, so
    /// they have to be re-derived whenever the two disagree. Writing only on a
    /// real difference keeps this a no-op in the steady state, so it does not
    /// churn CloudKit on every launch.
    private func backfillScheduleInstants() {
        let context = sharedModelContainer.mainContext
        guard let flights = try? context.fetch(FetchDescriptor<Flight>()) else { return }

        var updated = 0
        for flight in flights {
            let departure = flight.departureDateTime
            if flight.departureInstant != departure {
                flight.departureInstant = departure
                updated += 1
            }
            let arrival = flight.arrivalDateTime
            if flight.arrivalInstant != arrival {
                flight.arrivalInstant = arrival
                updated += 1
            }
        }

        if updated > 0 {
            try? context.save()
        }
    }

    /// One-time migration: create TravelDocument from legacy flat fields on Person.
    private func migrateDocuments() {
        let context = sharedModelContainer.mainContext
        guard let people = try? context.fetch(FetchDescriptor<Person>()) else { return }

        var migrated = 0
        for person in people {
            // Skip if already has documents or no legacy data
            guard person.documentList.isEmpty, let number = person.idNumber, !number.isEmpty else { continue }

            let doc = TravelDocument(
                docType: person.idType ?? "Passport",
                docNumber: number,
                issuingCountry: person.idIssuingCountry,
                expiryDate: person.idExpiry
            )
            doc.person = person
            context.insert(doc)

            // Clear legacy fields so passport data doesn't exist in two places
            person.idNumber = nil
            person.idType = nil
            person.idIssuingCountry = nil
            person.idExpiry = nil

            migrated += 1
        }

        if migrated > 0 {
            try? context.save()
        }
    }
}

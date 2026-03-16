import SwiftUI
import SwiftData

@main
struct flyfun_formsApp: App {
    @State private var appState = AppState()
    let catalog = AirportCatalog(baseURL: APIConfig.baseURL)

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Person.self,
            TravelDocument.self,
            Aircraft.self,
            Flight.self,
            Trip.self,
        ])
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
            .onOpenURL { url in
                appState.handleAuthCallback(url: url)
            }
            .task { migrateDocuments() }
            .task { await preloadAirportData() }
        }
        .modelContainer(sharedModelContainer)
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

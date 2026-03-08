import SwiftUI
import SwiftData

@main
struct flyfun_formsApp: App {
    let catalog = AirportCatalog(baseURL: APIConfig.baseURL)

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Person.self,
            Aircraft.self,
            Flight.self,
            Trip.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.aero.flyfun.flightforms")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.airportCatalog, catalog)
                .task {
                    await catalog.sync()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

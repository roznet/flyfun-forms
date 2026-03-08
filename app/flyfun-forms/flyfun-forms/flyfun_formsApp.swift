import SwiftUI
import SwiftData

@main
struct flyfun_formsApp: App {
    @State private var appState = AppState()
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
        }
        .modelContainer(sharedModelContainer)
    }
}

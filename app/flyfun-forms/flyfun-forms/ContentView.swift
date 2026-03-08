import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Tab("People", systemImage: "person.2") {
                NavigationStack {
                    PeopleListView()
                }
            }

            Tab("Aircraft", systemImage: "airplane") {
                NavigationStack {
                    AircraftListView()
                }
            }

            Tab("Flights", systemImage: "arrow.triangle.swap") {
                NavigationStack {
                    FlightsListView()
                }
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    Form {
                        Section {
                            Button("Sign Out", role: .destructive) {
                                appState.logout()
                            }
                        }
                    }
                    .navigationTitle("Settings")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Person.self, Aircraft.self, Flight.self, Trip.self], inMemory: true)
}

import SwiftUI
import SwiftData

struct ContentView: View {
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
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Person.self, Aircraft.self, Flight.self, Trip.self], inMemory: true)
}

import SwiftUI
import SwiftData

struct FlightsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    var body: some View {
        List {
            ForEach(flights) { flight in
                NavigationLink(value: flight) {
                    VStack(alignment: .leading) {
                        Text(flight.displayName)
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text(flight.departureDate, style: .date)
                                .font(.caption)
                            if let ac = flight.aircraft {
                                Text(ac.registration)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete(perform: deleteFlights)
        }
        .navigationTitle("Flights")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let flight = Flight()
                    modelContext.insert(flight)
                } label: {
                    Label("Add Flight", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Flight.self) { flight in
            FlightEditView(flight: flight)
        }
    }

    private func deleteFlights(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(flights[index])
        }
    }
}

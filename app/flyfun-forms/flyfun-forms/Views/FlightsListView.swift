import SwiftUI
import SwiftData

struct FlightsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]
    @State private var showNewFlightFlow = false
    @State private var selectedFlight: Flight?

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
                    showNewFlightFlow = true
                } label: {
                    Label("Add Flight", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewFlightFlow) {
            NewFlightFlow { flight in
                selectedFlight = flight
            }
        }
        .navigationDestination(for: Flight.self) { flight in
            FlightEditView(flight: flight)
        }
        .navigationDestination(item: $selectedFlight) { flight in
            FlightEditView(flight: flight)
        }
    }

    private func deleteFlights(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(flights[index])
        }
    }
}

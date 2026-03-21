import SwiftUI
import SwiftData

struct FlightsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]
    @State private var showNewFlightFlow = false
    @State private var selectedFlight: Flight?
    @State private var showPastFlights = false

    private var sortedFlights: [Flight] {
        flights.sorted { a, b in
            let dateA = a.departureDateTime
            let dateB = b.departureDateTime
            return dateA > dateB
        }
    }

    private var upcomingFlights: [Flight] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return sortedFlights.filter { $0.departureDate >= startOfToday }
    }

    private var pastFlights: [Flight] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return sortedFlights.filter { $0.departureDate < startOfToday }
    }

    var body: some View {
        List {
            Section("Upcoming") {
                if upcomingFlights.isEmpty {
                    Text("No upcoming flights")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(upcomingFlights) { flight in
                        flightRow(flight)
                    }
                    .onDelete { offsets in
                        deleteFlights(offsets, from: upcomingFlights)
                    }
                }
            }

            if !pastFlights.isEmpty {
                Section(isExpanded: $showPastFlights) {
                    ForEach(pastFlights) { flight in
                        flightRow(flight)
                    }
                    .onDelete { offsets in
                        deleteFlights(offsets, from: pastFlights)
                    }
                } header: {
                    Button {
                        withAnimation { showPastFlights.toggle() }
                    } label: {
                        HStack {
                            Text("Past Flights")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showPastFlights ? 90 : 0))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
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

    private func flightRow(_ flight: Flight) -> some View {
        NavigationLink(value: flight) {
            VStack(alignment: .leading) {
                Text(flight.displayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(flight.departureDate, style: .date)
                        .font(.caption)
                    if !flight.departureTimeUTC.isEmpty {
                        Text(flight.departureTimeUTC + "z")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let ac = flight.aircraft {
                        Text(ac.registration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func deleteFlights(_ offsets: IndexSet, from list: [Flight]) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }
}

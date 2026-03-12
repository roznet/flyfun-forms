import SwiftUI
import SwiftData

/// Two-step sheet for creating a new flight: Route & schedule, then people.
/// Only inserts the Flight into the model context on "Create Flight".
struct NewFlightFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]

    @State private var step: Step = .route
    @State private var originICAO = ""
    @State private var destinationICAO = ""
    @State private var departureDate = Date()
    @State private var arrivalDate = Date()
    @State private var departureTimeUTC = ""
    @State private var arrivalTimeUTC = ""
    @State private var selectedAircraft: Aircraft?
    @State private var selectedCrew: [Person] = []
    @State private var selectedPassengers: [Person] = []
    @State private var showAirportPicker = false
    @State private var showPeoplePicker = false

    /// Called with the newly created flight so the parent can navigate to it.
    var onCreated: (Flight) -> Void

    enum Step {
        case route, people
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .route:
                    routeStep
                case .people:
                    peopleStep
                }
            }
            .navigationTitle(step == .route ? "New Flight" : "Add People")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .people {
                        Button("Back") { step = .route }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .route {
                        Button("Next") { step = .people }
                            .disabled(originICAO.isEmpty && destinationICAO.isEmpty)
                    } else {
                        Button("Create Flight") { createFlight() }
                    }
                }
            }
            .sheet(isPresented: $showAirportPicker) {
                AirportPickerView(originICAO: $originICAO, destinationICAO: $destinationICAO)
            }
            .sheet(isPresented: $showPeoplePicker) {
                PeoplePickerView(selectedCrew: $selectedCrew, selectedPassengers: $selectedPassengers)
            }
            .onChange(of: originICAO) {
                AirportTimezoneCache.shared.resolve(icao: originICAO)
            }
            .onChange(of: destinationICAO) {
                AirportTimezoneCache.shared.resolve(icao: destinationICAO)
            }
            .onChange(of: departureDate) { oldValue, newValue in
                if Calendar.current.isDate(arrivalDate, inSameDayAs: oldValue) {
                    arrivalDate = newValue
                }
            }
        }
    }

    // MARK: - Route Step

    @ViewBuilder
    private var routeStep: some View {
        Section("Route") {
            Button {
                showAirportPicker = true
            } label: {
                HStack {
                    Text("Route")
                    Spacer()
                    if originICAO.isEmpty && destinationICAO.isEmpty {
                        Text("Tap to select")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(originICAO.isEmpty ? "----" : originICAO) → \(destinationICAO.isEmpty ? "----" : destinationICAO)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }

        Section("Schedule") {
            DatePicker("Departure Date", selection: $departureDate, displayedComponents: .date)
            LabeledContent("Departure Time") {
                TimeEntryView(
                    utcTimeString: $departureTimeUTC,
                    airportICAO: originICAO,
                    originICAO: originICAO,
                    destinationICAO: destinationICAO
                )
            }
            DatePicker("Arrival Date", selection: $arrivalDate, displayedComponents: .date)
            LabeledContent("Arrival Time") {
                TimeEntryView(
                    utcTimeString: $arrivalTimeUTC,
                    airportICAO: destinationICAO,
                    originICAO: originICAO,
                    destinationICAO: destinationICAO
                )
            }
        }

        Section("Aircraft") {
            Picker("Aircraft", selection: $selectedAircraft) {
                Text("None").tag(nil as Aircraft?)
                ForEach(allAircraft) { ac in
                    Text("\(ac.registration) (\(ac.type))").tag(ac as Aircraft?)
                }
            }
        }
    }

    // MARK: - People Step

    @ViewBuilder
    private var peopleStep: some View {
        Section("Crew") {
            if selectedCrew.isEmpty {
                Text("No crew selected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedCrew) { person in
                    Text(person.displayName)
                }
            }
        }

        Section("Passengers") {
            if selectedPassengers.isEmpty {
                Text("No passengers selected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedPassengers) { person in
                    Text(person.displayName)
                }
            }
        }

        Section {
            Button {
                showPeoplePicker = true
            } label: {
                Label("Select People", systemImage: "person.badge.plus")
            }
        }
    }

    // MARK: - Create

    private func createFlight() {
        let flight = Flight()
        flight.originICAO = originICAO
        flight.destinationICAO = destinationICAO
        flight.departureDate = departureDate
        flight.arrivalDate = arrivalDate
        flight.departureTimeUTC = departureTimeUTC
        flight.arrivalTimeUTC = arrivalTimeUTC
        flight.aircraft = selectedAircraft
        flight.crew = selectedCrew.isEmpty ? nil : selectedCrew
        flight.passengers = selectedPassengers.isEmpty ? nil : selectedPassengers

        modelContext.insert(flight)
        dismiss()
        onCreated(flight)
    }
}

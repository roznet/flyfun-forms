import SwiftUI
import SwiftData
import RZFlight
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Two-step sheet for creating a new flight: Route & schedule, then people.
/// Only inserts the Flight into the model context on "Create Flight".
struct NewFlightFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]

    @State private var step: Step = .route
    @State private var originICAO = ""
    @State private var destinationICAO = ""
    @State private var departureInstant = Flight.defaultScheduleInstant()
    @State private var arrivalInstant = Flight.defaultScheduleInstant()
    @State private var selectedAircraft: Aircraft?
    @State private var selectedCrew: [Person] = []
    @State private var selectedPassengers: [Person] = []
    @State private var showAirportPicker = false
    @State private var showPeoplePicker = false
    @State private var showWeatherImport = false

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
            .sheet(isPresented: $showWeatherImport) {
                WeatherFlightPickerView { exchange in
                    applyWeatherImport(exchange)
                }
            }
            .onChange(of: departureInstant) { oldValue, newValue in
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = .gmt
                guard utc.isDate(arrivalInstant, inSameDayAs: oldValue) else { return }
                arrivalInstant = Flight.alignUTCDay(of: arrivalInstant, to: newValue)
            }
        }
    }

    // MARK: - Route Step

    @ViewBuilder
    private var routeStep: some View {
        Section {
            HStack(spacing: 8) {
                Text("Import")
                Spacer(minLength: 8)
                Button {
                    pasteFlightPlan()
                } label: {
                    Label("Flight Plan", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    showWeatherImport = true
                } label: {
                    Label("Weather", systemImage: "cloud.sun")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

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
            FlightDateTimeField(
                label: "Departure",
                instant: $departureInstant,
                primaryICAO: originICAO,
                zoneICAOs: [originICAO, destinationICAO]
            )
            FlightDateTimeField(
                label: "Arrival",
                instant: $arrivalInstant,
                primaryICAO: destinationICAO,
                zoneICAOs: [originICAO, destinationICAO]
            )
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

    // MARK: - Import

    private func pasteFlightPlan() {
        #if os(iOS)
        guard let text = UIPasteboard.general.string else { return }
        #else
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        #endif

        guard let plan = ICAOFlightPlanParser.parse(text) else { return }

        applyRoute(
            plan.route,
            registration: plan.aircraftRegistration,
            aircraftType: plan.aircraftType
        )

        // A plan carrying DOF/ but no usable field 13 time yields no route
        // instant. Apply the day anyway, keeping the default time of day, so
        // the pilot only has to correct the time.
        if plan.route.departureTime == nil, let dayOfFlight = plan.dateOfFlight {
            departureInstant = Flight.alignUTCDay(of: departureInstant, to: dayOfFlight)
            arrivalInstant = Flight.alignUTCDay(of: arrivalInstant, to: dayOfFlight)
        }
    }

    /// Map a flight imported from the weather app onto the route step. Only the
    /// origin/destination/time/aircraft subset forms cares about is consumed;
    /// waypoints and coordinates are ignored.
    private func applyWeatherImport(_ exchange: FlightExchange) {
        applyRoute(
            exchange.route,
            registration: exchange.aircraft?.registration,
            aircraftType: exchange.aircraft?.type ?? exchange.route.aircraftType
        )
    }

    /// Apply a route onto the route step. The pilot reviews it and taps Create
    /// Flight; there is no separate persistence path.
    ///
    /// Both import paths land here because both now carry the same type.
    /// `RZFlight.ICAOFlightPlanParser` composes field 13 and DOF/ into a UTC
    /// instant and derives the arrival from EET/ itself, so the pasted-plan path
    /// no longer has to add two "HH:mm" strings by hand. That arithmetic wrapped at
    /// 24h and left the arrival date a day behind on any overnight leg.
    private func applyRoute(_ route: Route, registration: String?, aircraftType: String?) {
        if !route.departure.isEmpty { originICAO = route.departure }
        if !route.destination.isEmpty { destinationICAO = route.destination }

        if let departure = route.departureTime {
            departureInstant = departure
            // Default the arrival onto the departure day; overwritten below
            // when the route carries an arrival time of its own.
            arrivalInstant = Flight.alignUTCDay(of: arrivalInstant, to: departure)
        }
        if let arrival = route.arrivalTime {
            arrivalInstant = arrival
        }

        if let registration, !registration.isEmpty {
            resolveOrCreateAircraft(registration: registration, type: aircraftType ?? "")
        }
    }

    /// Select an existing aircraft matching `registration` (ignoring dashes /
    /// case), or insert a new one. Shared by the paste and weather-import flows.
    private func resolveOrCreateAircraft(registration: String, type: String) {
        let normalizedReg = registration.replacingOccurrences(of: "-", with: "").uppercased()
        if let existing = allAircraft.first(where: { ac in
            ac.registration.replacingOccurrences(of: "-", with: "").uppercased() == normalizedReg
        }) {
            selectedAircraft = existing
        } else {
            let ac = Aircraft(registration: registration, type: type)
            modelContext.insert(ac)
            selectedAircraft = ac
        }
    }

    // MARK: - Create

    private func createFlight() {
        let flight = Flight()
        flight.originICAO = originICAO
        flight.destinationICAO = destinationICAO
        flight.departureDateTime = departureInstant
        flight.arrivalDateTime = arrivalInstant
        flight.aircraft = selectedAircraft
        flight.crew = selectedCrew.isEmpty ? nil : selectedCrew
        flight.passengers = selectedPassengers.isEmpty ? nil : selectedPassengers

        modelContext.insert(flight)
        dismiss()
        onCreated(flight)
    }
}

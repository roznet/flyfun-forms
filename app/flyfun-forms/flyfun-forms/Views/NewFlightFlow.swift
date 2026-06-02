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
    @Environment(AppState.self) private var appState
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

    // MARK: - Import Flight Plan

    private func pasteFlightPlan() {
        #if os(iOS)
        guard let text = UIPasteboard.general.string else { return }
        #else
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        #endif

        guard let parsed = ICAOFlightPlanParser.parse(text) else { return }

        if let icao = parsed.originICAO, !icao.isEmpty {
            originICAO = icao
        }
        if let icao = parsed.destinationICAO, !icao.isEmpty {
            destinationICAO = icao
        }
        if let time = parsed.departureTimeUTC {
            departureTimeUTC = time
        }
        if let dof = parsed.dateOfFlight {
            departureDate = dof
            arrivalDate = dof
        }
        // Compute arrival time from departure + EET
        if let depTime = parsed.departureTimeUTC, let eet = parsed.eet {
            arrivalTimeUTC = addTime(depTime, eet)
        }
        // Match aircraft by registration, or create if not found
        if let reg = parsed.aircraftRegistration {
            let normalizedReg = reg.replacingOccurrences(of: "-", with: "").uppercased()
            if let existing = allAircraft.first(where: { ac in
                ac.registration.replacingOccurrences(of: "-", with: "").uppercased() == normalizedReg
            }) {
                selectedAircraft = existing
            } else {
                let ac = Aircraft(registration: reg, type: parsed.aircraftType ?? "")
                modelContext.insert(ac)
                selectedAircraft = ac
            }
        }
    }

    /// Add two HH:mm time strings, wrapping at 24h.
    private func addTime(_ base: String, _ offset: String) -> String {
        let parts1 = base.split(separator: ":")
        let parts2 = offset.split(separator: ":")
        guard parts1.count == 2, parts2.count == 2,
              let h1 = Int(parts1[0]), let m1 = Int(parts1[1]),
              let h2 = Int(parts2[0]), let m2 = Int(parts2[1]) else { return base }
        let total = (h1 * 60 + m1) + (h2 * 60 + m2)
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    // MARK: - Import from Weather

    /// Map an imported `FlightExchange` onto the route step, mirroring
    /// `pasteFlightPlan()`. The pilot then reviews and taps Create Flight —
    /// no separate persistence path. Only the origin/destination/time/aircraft
    /// subset forms cares about is consumed; waypoints/coords are ignored.
    private func applyWeatherImport(_ exchange: FlightExchange) {
        let route = exchange.route

        if !route.departure.isEmpty { originICAO = route.departure }
        if !route.destination.isEmpty { destinationICAO = route.destination }

        if let dep = route.departureTime {
            let (day, hhmm) = utcDayAndTime(dep)
            departureDate = day
            departureTimeUTC = hhmm
            // Default arrival to the departure day; overwritten below if the
            // payload carries an arrival time.
            arrivalDate = day
        }
        if let arr = route.arrivalTime {
            let (day, hhmm) = utcDayAndTime(arr)
            arrivalDate = day
            arrivalTimeUTC = hhmm
        }

        // Aircraft: match an existing one by normalized registration, else
        // create it — the same dedup the pasted-flight-plan flow uses.
        let type = exchange.aircraft?.type ?? route.aircraftType ?? ""
        if let reg = exchange.aircraft?.registration, !reg.isEmpty {
            let normalizedReg = reg.replacingOccurrences(of: "-", with: "").uppercased()
            if let existing = allAircraft.first(where: { ac in
                ac.registration.replacingOccurrences(of: "-", with: "").uppercased() == normalizedReg
            }) {
                selectedAircraft = existing
            } else {
                let ac = Aircraft(registration: reg, type: type)
                modelContext.insert(ac)
                selectedAircraft = ac
            }
        }
    }

    /// Split a UTC instant into a date (midnight UTC) and an "HH:mm" string —
    /// forms stores departure/arrival as a separate date + UTC time-of-day,
    /// and `Flight.departureDateTime` recombines them with a UTC calendar.
    private func utcDayAndTime(_ date: Date) -> (day: Date, hhmm: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? date
        let hhmm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        return (day, hhmm)
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

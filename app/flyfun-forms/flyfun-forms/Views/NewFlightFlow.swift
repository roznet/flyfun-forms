import SwiftUI
import SwiftData
import RZFlight

/// Two-step sheet for creating a new flight: Route & schedule, then people.
/// Only inserts the Flight into the model context on "Create Flight".
struct NewFlightFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]
    @Query(sort: \Flight.departureDate, order: .reverse) private var allFlights: [Flight]
    @Query private var allPeople: [Person]

    @State private var step: Step = .route
    @State private var originICAO = ""
    @State private var destinationICAO = ""
    @State private var departureInstant = Flight.defaultScheduleInstant()
    @State private var arrivalInstant = Flight.defaultScheduleInstant()
    @State private var selectedAircraft: Aircraft?
    @State private var selectedCrew: [Person] = []
    @State private var selectedPassengers: [Person] = []
    @State private var selectedResponsiblePerson: Person?
    @State private var nature: String?
    @State private var contact: String?
    @State private var observations: String?
    @State private var showAirportPicker = false
    @State private var showPeoplePicker = false
    @State private var showCrewSourcePicker = false

    /// The import method whose picker is up, if any. One piece of state for all
    /// of them: only one import can be in flight at a time.
    @State private var activeImport: FlightImportMethod?
    @State private var showMethodList = false
    /// Set when a method is chosen from the list, and started only once that
    /// list has fully dismissed. Presenting the picker in the same turn as the
    /// list's dismissal collides and SwiftUI drops the second transition.
    @State private var pendingMethod: FlightImportMethod?
    /// What the last import brought in, shown as confirmation under the control.
    @State private var importSummary: String?
    @State private var importError: String?
    /// Whether the current crew/passenger selection came from an import rather
    /// than from the pilot. A later import replaces what an import wrote and
    /// leaves a hand-picked selection alone.
    @State private var peopleCameFromImport = false
    /// Whether the account has linked Autorouter, or nil until the check lands.
    @State private var autorouterLinked: Bool?
    /// `onAppear` fires again on the way back from a sheet, so the default
    /// aircraft is applied once — a pilot who sets the picker to None means it.
    @State private var hasDefaultedAircraft = false

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
                            .accessibilityIdentifier("newFlightNextButton")
                    } else {
                        Button("Create Flight") { createFlight() }
                            .accessibilityIdentifier("createFlightButton")
                    }
                }
            }
            .sheet(isPresented: $showAirportPicker) {
                AirportPickerView(originICAO: $originICAO, destinationICAO: $destinationICAO)
            }
            .sheet(isPresented: $showPeoplePicker, onDismiss: {
                // The pilot chose these, so a later import must not clear them.
                peopleCameFromImport = false
            }) {
                PeoplePickerView(selectedCrew: $selectedCrew, selectedPassengers: $selectedPassengers)
            }
            .sheet(isPresented: $showCrewSourcePicker) {
                CrewSourcePickerView { crew, passengers in
                    applyPeople(crew: crew, passengers: passengers)
                }
            }
            .sheet(item: $activeImport) { method in
                importSheet(for: method)
            }
            .sheet(isPresented: $showMethodList, onDismiss: {
                // Start the chosen method only once the list is gone, so its
                // picker isn't competing with the list's own dismissal.
                guard let method = pendingMethod else { return }
                pendingMethod = nil
                beginImport(method)
            }) {
                FlightImportMethodList(context: importContext) { method in
                    pendingMethod = method
                    showMethodList = false
                }
            }
            .alert(
                "Import Failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .onAppear { applyDefaultAircraft() }
            .task {
                // So the list can say "Link your Autorouter account" up front
                // rather than after a spinner and a 409.
                guard appState.isAuthenticated else { return }
                autorouterLinked = await AutorouterImportService(
                    baseURL: APIConfig.baseURL, session: appState.rollingSession
                ).isLinked()
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
            FlightImportControl(context: importContext) {
                showMethodList = true
            }
            if let importSummary {
                Text(importSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("importSummary")
            }
        } header: {
            Text("Import")
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
            .accessibilityIdentifier("newFlightRouteButton")
        }

        Section("Schedule") {
            FlightDateTimeField(
                end: .departure,
                instant: $departureInstant,
                primaryICAO: originICAO,
                zoneICAOs: [originICAO, destinationICAO]
            )
            FlightDateTimeField(
                end: .arrival,
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
            .accessibilityIdentifier("newFlightAircraftPicker")
        }
    }

    // MARK: - People Step

    @ViewBuilder
    private var peopleStep: some View {
        if selectedCrew.isEmpty && selectedPassengers.isEmpty,
           let suggestion = peopleSuggestion {
            Section {
                Button {
                    applyPeople(crew: suggestion.crew, passengers: suggestion.passengers)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.badge.plus")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.label)
                            Text(suggestion.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("peopleSuggestionButton")

                // The chip picks the flight itself; this is the same copy with
                // the choice handed back, for a pilot who flies with different
                // people on different trips.
                Button {
                    showCrewSourcePicker = true
                } label: {
                    Label("Choose another flight…", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("crewSourceButton")
            } header: {
                Text("Suggestion")
            }
        }

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

    /// Who was on board last time, for the one-tap chip. The people step only
    /// shows it while nothing is selected, so an import that brought its own
    /// people (a repeated flight) hides it.
    private var peopleSuggestion: PeopleSuggestion? {
        PeopleSuggestion.suggest(
            from: allFlights,
            aircraft: selectedAircraft,
            usualCrew: allPeople.filter(\.isUsualCrew)
        )
    }

    // MARK: - Import

    private var importContext: FlightImportContext {
        let mostRecent = allFlights
            .sorted { $0.departureDateTime > $1.departureDateTime }
            .first { !$0.originICAO.isEmpty || !$0.destinationICAO.isEmpty }
        return FlightImportContext(
            hasPastFlights: mostRecent != nil,
            clipboardHasText: FlightImportContext.pasteboardHasText,
            isSignedIn: appState.isAuthenticated,
            autorouterLinked: autorouterLinked,
            mostRecentRoute: mostRecent?.displayName
        )
    }

    /// Start the form on the aircraft the pilot last flew, or on the only one
    /// they have. An import that carries a registration overwrites this, and a
    /// choice already made — including an import's — is left alone.
    private func applyDefaultAircraft() {
        guard !hasDefaultedAircraft else { return }
        hasDefaultedAircraft = true
        guard selectedAircraft == nil else { return }
        selectedAircraft = Aircraft.defaultForNewFlight(
            flights: allFlights, available: allAircraft
        )
    }

    /// Take a crew the pilot chose — from the suggestion chip or the
    /// copy-from-a-flight picker. Chosen people are not import-owned, so a
    /// later import leaves them alone.
    private func applyPeople(crew: [Person], passengers: [Person]) {
        selectedCrew = crew
        selectedPassengers = passengers
        peopleCameFromImport = false
    }

    /// Begin an import. The clipboard resolves in place; the others present a
    /// picker that hands back a draft.
    private func beginImport(_ method: FlightImportMethod) {
        switch method {
        case .clipboardFPL:
            pasteFlightPlan()
        case .previousFlight, .weather, .autorouter:
            activeImport = method
        }
    }

    @ViewBuilder
    private func importSheet(for method: FlightImportMethod) -> some View {
        switch method {
        case .previousFlight:
            PreviousFlightPickerView { flight in
                apply(FlightDraft(repeating: flight, zone: originZone(for: flight.originICAO)))
            }
        case .weather:
            WeatherFlightPickerView { exchange in
                let id = exchange.source?.flightId ?? ""
                apply(FlightDraft(exchange, provenance: .weather(flightID: id)))
            }
        case .autorouter:
            AutorouterRoutePickerView { draft in
                apply(draft)
            }
        case .clipboardFPL:
            // Resolved in `beginImport(_:)` without a sheet; never presented.
            EmptyView()
        }
    }

    private func pasteFlightPlan() {
        do {
            let plan = try ClipboardFlightPlan.read()
            apply(FlightDraft(plan))

            // A plan carrying DOF/ but no usable field 13 time yields no route
            // instant. Apply the day anyway, keeping the default time of day, so
            // the pilot only has to correct the time.
            if let dayOfFlight = FlightDraft.fallbackDayOfFlight(plan) {
                departureInstant = Flight.alignUTCDay(of: departureInstant, to: dayOfFlight)
                arrivalInstant = Flight.alignUTCDay(of: arrivalInstant, to: dayOfFlight)
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    /// The origin airport's timezone when it has been resolved, so a repeated
    /// flight keeps its local time of day rather than its UTC one.
    ///
    /// Resolution is a reverse-geocode, so a cold cache returns nil here and
    /// the reschedule falls back to UTC. The cache is on disk and shared with
    /// the date/time field, so it is warm for any airport the pilot has seen.
    private func originZone(for icao: String) -> TimeZone? {
        guard !icao.isEmpty else { return nil }
        AirportTimezoneCache.shared.resolve(icao: icao)
        return AirportTimezoneCache.shared.timezone(for: icao)
    }

    /// Write an imported draft onto the route step. The pilot reviews it and
    /// taps Create Flight; there is no separate persistence path.
    ///
    /// This is the only writer of form state, so every import method — and
    /// every method added later — lands here and nowhere else.
    private func apply(_ draft: FlightDraft) {
        let route = draft.route
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

        if let registration = draft.registration, !registration.isEmpty {
            resolveOrCreateAircraft(
                registration: registration, type: draft.aircraftType ?? ""
            )
        }

        // People and the form-level fields are *replaced*, not merged, so a
        // second import is not silently mixed with the first. Importing a
        // previous flight and then changing your mind and importing a route
        // from the clipboard used to leave the first flight's crew in place —
        // on a customs form, the wrong people.
        //
        // Only what an import last wrote is cleared, tracked by
        // `peopleCameFromImport`: a pilot who picked their crew by hand, went
        // Back, and re-imported the route to fix a typo keeps that crew.
        if draft.hasPeople {
            selectedCrew = draft.crew
            selectedPassengers = draft.passengers
            peopleCameFromImport = true
        } else if peopleCameFromImport {
            selectedCrew = []
            selectedPassengers = []
            peopleCameFromImport = false
        }

        // These have no editor in this flow, so an import is their only
        // source and replacing unconditionally cannot discard a pilot's entry.
        selectedResponsiblePerson = draft.responsiblePerson
        nature = draft.nature
        contact = draft.contact
        observations = draft.observations

        importSummary = draft.provenance.summary
    }

    /// Select an existing aircraft matching `registration` (ignoring dashes /
    /// case), or insert a new one. Shared by every import method that carries a
    /// registration.
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
        flight.responsiblePerson = selectedResponsiblePerson
        if let nature { flight.nature = nature }
        flight.contact = contact
        flight.observations = observations

        modelContext.insert(flight)
        dismiss()
        onCreated(flight)
    }
}

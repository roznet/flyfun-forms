import QuickLook
import SwiftUI
import SwiftData

struct FlightEditView: View {
    @Bindable var flight: Flight
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]
    @Query(sort: \Person.lastName) private var allPeople: [Person]
    @Environment(\.airportCatalog) private var catalog
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showAirportPicker = false
    @State private var showPeoplePicker = false
    @State private var editingCrew: [Person] = []
    @State private var editingPassengers: [Person] = []
    @State private var isGenerating = false
    @State private var generatingForm: String?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var previewURL: URL?
    @State private var formDetails: [String: [FormInfo]] = [:]
    @State private var extraFieldValues: [String: [String: ExtraFieldValue]] = [:]
    @State private var previousDepartureDate: Date?

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let reasonOptions = [
        "Business",
        "Pleasure",
        "Transit",
        "Other",
    ]

    var body: some View {
        Group {
            if sizeClass == .regular {
                wideLayout
            } else {
                compactLayout
            }
        }
        .navigationTitle(flight.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { oldURL, _ in
            if let oldURL {
                try? FileManager.default.removeItem(at: oldURL)
            }
        }
        .sheet(isPresented: $showAirportPicker) {
            AirportPickerView(originICAO: $flight.originICAO, destinationICAO: $flight.destinationICAO)
        }
        .sheet(isPresented: $showPeoplePicker, onDismiss: applyPeopleSelection) {
            PeoplePickerView(selectedCrew: $editingCrew, selectedPassengers: $editingPassengers)
        }
        .onChange(of: flight.originICAO) {
            fetchFormDetails(icao: flight.originICAO)
        }
        .onChange(of: flight.destinationICAO) {
            fetchFormDetails(icao: flight.destinationICAO)
        }
        .onChange(of: flight.departureDate) { oldValue, newValue in
            autoSyncArrivalDate(oldDeparture: oldValue, newDeparture: newValue)
        }
        .onAppear {
            previousDepartureDate = flight.departureDate
            fetchFormDetails(icao: flight.originICAO)
            fetchFormDetails(icao: flight.destinationICAO)
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        Form {
            routeSection
            scheduleSection
            aircraftSection
            flightDetailsSection
            crewSection
            passengersSection
            formSections
            actionsSection
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                routeSection
                scheduleSection
                aircraftSection
                flightDetailsSection
                formSections
                actionsSection
            }
            .frame(minWidth: 0, maxWidth: .infinity)

            Form {
                crewSection
                passengersSection
            }
            .frame(minWidth: 0, maxWidth: .infinity)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var routeSection: some View {
        Section("Route") {
            Button {
                showAirportPicker = true
            } label: {
                HStack {
                    let origin = flight.originICAO.isEmpty ? "----" : flight.originICAO
                    let dest = flight.destinationICAO.isEmpty ? "----" : flight.destinationICAO
                    Text("\(origin)  \(Image(systemName: "arrow.right"))  \(dest)")
                        .font(.system(.title3, design: .monospaced).bold())
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Departure Date", selection: $flight.departureDate, displayedComponents: .date)
            LabeledContent("Departure Time") {
                TimeEntryView(
                    utcTimeString: $flight.departureTimeUTC,
                    airportICAO: flight.originICAO,
                    originICAO: flight.originICAO,
                    destinationICAO: flight.destinationICAO
                )
            }
            DatePicker("Arrival Date", selection: $flight.arrivalDate, displayedComponents: .date)
            LabeledContent("Arrival Time") {
                TimeEntryView(
                    utcTimeString: $flight.arrivalTimeUTC,
                    airportICAO: flight.destinationICAO,
                    originICAO: flight.originICAO,
                    destinationICAO: flight.destinationICAO
                )
            }
        }
    }

    @ViewBuilder
    private var aircraftSection: some View {
        Section("Aircraft") {
            Picker("Aircraft", selection: $flight.aircraft) {
                Text("None").tag(nil as Aircraft?)
                ForEach(allAircraft) { ac in
                    Text("\(ac.registration) (\(ac.type))").tag(ac as Aircraft?)
                }
            }
        }
    }

    @ViewBuilder
    private var flightDetailsSection: some View {
        Section("Flight Details") {
            Picker("Nature", selection: $flight.nature) {
                Text("Private").tag("private")
                Text("Commercial").tag("commercial")
            }
            Picker("Reason for Visit", selection: reasonForVisitBinding) {
                Text("—").tag("")
                ForEach(Self.reasonOptions, id: \.self) { reason in
                    Text(reason).tag(reason)
                }
            }
            Picker("Responsible Person", selection: responsiblePersonBinding) {
                Text("—").tag("")
                ForEach(allPeople) { person in
                    Text(person.displayName).tag(person.displayName)
                }
            }
            if let person = flight.responsiblePerson {
                if let phone = person.phone, !phone.isEmpty {
                    LabeledContent("Phone", value: phone)
                        .foregroundStyle(.secondary)
                }
                if let address = person.address, !address.isEmpty {
                    LabeledContent("Address", value: address)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Observations", text: Binding(
                get: { flight.observations ?? "" },
                set: { flight.observations = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...4)
        }
    }

    @ViewBuilder
    private var crewSection: some View {
        Section("Crew") {
            ForEach(flight.crewList) { person in
                Text(person.displayName)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            flight.crew?.removeAll { $0.persistentModelID == person.persistentModelID }
                        }
                    }
            }
            Button {
                editingCrew = flight.crewList
                editingPassengers = flight.passengerList
                showPeoplePicker = true
            } label: {
                Label("Edit Crew & Passengers", systemImage: "person.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var passengersSection: some View {
        Section("Passengers") {
            ForEach(flight.passengerList) { person in
                Text(person.displayName)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            flight.passengers?.removeAll { $0.persistentModelID == person.persistentModelID }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var formSections: some View {
        if !flight.destinationICAO.isEmpty {
            formSection(airport: flight.destinationICAO, direction: "arrival")
        }
        if !flight.originICAO.isEmpty {
            formSection(airport: flight.originICAO, direction: "departure")
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section("Actions") {
            Button {
                createReturnFlight()
            } label: {
                Label("Create Return Flight", systemImage: "arrow.uturn.left")
            }
            Button {
                duplicateFlight()
            } label: {
                Label("Duplicate Flight", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Bindings

    private var reasonForVisitBinding: Binding<String> {
        Binding(
            get: { flight.reasonForVisit ?? "" },
            set: { flight.reasonForVisit = $0.isEmpty ? nil : $0 }
        )
    }

    private var responsiblePersonBinding: Binding<String> {
        Binding(
            get: { flight.responsiblePerson?.displayName ?? "" },
            set: { newValue in
                if let person = allPeople.first(where: { $0.displayName == newValue }) {
                    flight.responsiblePerson = person
                    // Also sync contact field for backward compat
                    flight.contact = person.phone
                } else {
                    flight.responsiblePerson = nil
                    flight.contact = nil
                }
            }
        )
    }

    // MARK: - Arrival Date Auto-sync

    private func autoSyncArrivalDate(oldDeparture: Date, newDeparture: Date) {
        // Only sync if arrival was matching old departure (user hasn't manually changed it)
        if Calendar.current.isDate(flight.arrivalDate, inSameDayAs: oldDeparture) {
            flight.arrivalDate = newDeparture
        }
    }

    // MARK: - Form Sections

    @ViewBuilder
    private func formSection(airport: String, direction: String) -> some View {
        let forms = formDetails[airport] ?? []
        if !forms.isEmpty {
            ForEach(forms) { formInfo in
                Section("\(airport) — \(formInfo.label) (\(direction))") {
                    extraFieldsView(airport: airport, formInfo: formInfo)

                    Button {
                        Task { await generateForm(airport: airport, form: formInfo.id) }
                    } label: {
                        HStack {
                            Label("Generate", systemImage: "doc.text")
                            Spacer()
                            if generatingForm == "\(airport)_\(formInfo.id)" {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .disabled(isGenerating)
                }
            }
        }
    }

    @ViewBuilder
    private func extraFieldsView(airport: String, formInfo: FormInfo) -> some View {
        let formKey = "\(airport)_\(formInfo.id)"
        let hiddenKeys: Set<String> = ["reason_for_visit", "responsible_person"]
        ForEach(formInfo.extraFields.filter({ !hiddenKeys.contains($0.key) })) { field in
            switch field.type {
            case "choice":
                Picker(field.label, selection: extraFieldBinding(formKey: formKey, fieldKey: field.key, defaultValue: field.options?.first ?? "")) {
                    ForEach(field.options ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            case "person":
                let allPeopleOnFlight = flight.crewList + flight.passengerList
                Picker(field.label, selection: personExtraFieldBinding(formKey: formKey, fieldKey: field.key, people: allPeopleOnFlight)) {
                    Text("—").tag("")
                    ForEach(allPeopleOnFlight) { person in
                        Text(person.displayName).tag(person.displayName)
                    }
                }
                if case .person(let dict) = extraFieldValues[formKey]?[field.key],
                   !dict.isEmpty {
                    TextField("Address", text: personAddressBinding(formKey: formKey, fieldKey: field.key))
                        .foregroundStyle(.secondary)
                }
            default:
                TextField(field.label, text: textExtraFieldBinding(formKey: formKey, fieldKey: field.key))
            }
        }
    }

    // MARK: - Extra field bindings

    private func extraFieldBinding(formKey: String, fieldKey: String, defaultValue: String) -> Binding<String> {
        Binding(
            get: {
                if case .text(let val) = extraFieldValues[formKey]?[fieldKey] { return val }
                return defaultValue
            },
            set: { newValue in
                if extraFieldValues[formKey] == nil { extraFieldValues[formKey] = [:] }
                extraFieldValues[formKey]?[fieldKey] = .text(newValue)
            }
        )
    }

    private func textExtraFieldBinding(formKey: String, fieldKey: String) -> Binding<String> {
        extraFieldBinding(formKey: formKey, fieldKey: fieldKey, defaultValue: "")
    }

    private func personExtraFieldBinding(formKey: String, fieldKey: String, people: [Person]) -> Binding<String> {
        Binding(
            get: {
                if case .person(let dict) = extraFieldValues[formKey]?[fieldKey] { return dict["name"] ?? "" }
                return ""
            },
            set: { newValue in
                if extraFieldValues[formKey] == nil { extraFieldValues[formKey] = [:] }
                if let person = people.first(where: { $0.displayName == newValue }) {
                    extraFieldValues[formKey]?[fieldKey] = .person([
                        "name": person.displayName,
                        "address": person.address ?? "",
                    ])
                } else {
                    extraFieldValues[formKey]?[fieldKey] = .person([:])
                }
            }
        )
    }

    private func personAddressBinding(formKey: String, fieldKey: String) -> Binding<String> {
        Binding(
            get: {
                if case .person(let dict) = extraFieldValues[formKey]?[fieldKey] { return dict["address"] ?? "" }
                return ""
            },
            set: { newValue in
                if case .person(var dict) = extraFieldValues[formKey]?[fieldKey] {
                    dict["address"] = newValue
                    extraFieldValues[formKey]?[fieldKey] = .person(dict)
                }
            }
        )
    }

    // MARK: - Fetch form details

    private func fetchFormDetails(icao: String) {
        guard !icao.isEmpty, formDetails[icao] == nil else { return }
        let formService = FormService(baseURL: APIConfig.baseURL, jwt: appState.jwt)
        Task {
            if let detail = try? await formService.airportDetail(icao: icao) {
                formDetails[icao] = detail.forms
            }
        }
    }

    private func generateForm(airport: String, form: String) async {
        isGenerating = true
        generatingForm = "\(airport)_\(form)"
        defer {
            isGenerating = false
            generatingForm = nil
        }

        let formService = FormService(baseURL: APIConfig.baseURL, jwt: appState.jwt)
        let request = buildRequest(airport: airport, form: form)
        do {
            let (data, filename) = try await formService.generate(request: request, flatten: true)
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(filename)
            try data.write(to: fileURL)
            previewURL = fileURL
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func buildRequest(airport: String, form: String) -> GenerateRequest {
        // Derive contact from responsible person
        let contactValue = flight.responsiblePerson?.phone ?? flight.contact

        let flightPayload = FlightPayload(
            origin: flight.originICAO,
            destination: flight.destinationICAO,
            departureDate: dateFmt.string(from: flight.departureDate),
            departureTimeUtc: flight.departureTimeUTC,
            arrivalDate: dateFmt.string(from: flight.arrivalDate),
            arrivalTimeUtc: flight.arrivalTimeUTC,
            nature: flight.nature,
            contact: contactValue
        )

        let aircraftPayload: AircraftPayload
        if let ac = flight.aircraft {
            aircraftPayload = AircraftPayload(
                registration: ac.registration,
                type: ac.type,
                owner: ac.owner,
                ownerAddress: ac.ownerAddress,
                isAirplane: ac.isAirplane,
                usualBase: ac.usualBase
            )
        } else {
            aircraftPayload = AircraftPayload(registration: "", type: "")
        }

        let crewPayloads = flight.crewList.enumerated().map { (i, p) in
            personPayload(p, function: i == 0 ? "Pilot" : "Crew", airport: airport)
        }
        let paxPayloads = flight.passengerList.map { personPayload($0, airport: airport) }

        let formKey = "\(airport)_\(form)"
        var extras = extraFieldValues[formKey] ?? [:]

        // Inject reason_for_visit into extra fields for forms that need it
        if let reason = flight.reasonForVisit, !reason.isEmpty {
            extras["reason_for_visit"] = .text(reason)
        }

        // Inject responsible_person into extra fields for forms that need it
        if let person = flight.responsiblePerson {
            extras["responsible_person"] = .person([
                "name": person.displayName,
                "address": person.address ?? "",
            ])
        }

        return GenerateRequest(
            airport: airport,
            form: form,
            flight: flightPayload,
            aircraft: aircraftPayload,
            crew: crewPayloads,
            passengers: paxPayloads,
            extraFields: extras.isEmpty ? nil : extras,
            observations: flight.observations
        )
    }

    private func personPayload(_ p: Person, function: String? = nil, airport: String) -> PersonPayload {
        let doc = DocumentResolver.resolve(person: p, airport: airport)
        return PersonPayload(
            function: function,
            firstName: p.firstName,
            lastName: p.lastName,
            dob: p.dateOfBirth.map { dateFmt.string(from: $0) },
            nationality: doc?.issuingCountry,
            idNumber: doc?.docNumber,
            idType: doc?.docType,
            idIssuingCountry: doc?.issuingCountry,
            idExpiry: doc?.expiryDate.map { dateFmt.string(from: $0) },
            sex: p.sex,
            placeOfBirth: p.placeOfBirth,
            address: p.address
        )
    }

    private var availablePeople: [Person] {
        let crewIDs = Set(flight.crewList.map(\.persistentModelID))
        let paxIDs = Set(flight.passengerList.map(\.persistentModelID))
        return allPeople.filter { !crewIDs.contains($0.persistentModelID) && !paxIDs.contains($0.persistentModelID) }
    }

    // MARK: - People Picker

    private func applyPeopleSelection() {
        flight.crew = editingCrew.isEmpty ? nil : editingCrew
        flight.passengers = editingPassengers.isEmpty ? nil : editingPassengers
    }

    // MARK: - Return / Duplicate

    @Environment(\.modelContext) private var modelContext

    private func createReturnFlight() {
        let newFlight = Flight()
        newFlight.originICAO = flight.destinationICAO
        newFlight.destinationICAO = flight.originICAO
        newFlight.departureDate = flight.arrivalDate
        newFlight.arrivalDate = flight.arrivalDate
        newFlight.aircraft = flight.aircraft
        newFlight.crew = flight.crew
        newFlight.passengers = flight.passengers
        newFlight.nature = flight.nature
        newFlight.contact = flight.contact
        newFlight.reasonForVisit = flight.reasonForVisit
        newFlight.responsiblePerson = flight.responsiblePerson
        modelContext.insert(newFlight)
    }

    private func duplicateFlight() {
        let newFlight = Flight()
        newFlight.originICAO = flight.originICAO
        newFlight.destinationICAO = flight.destinationICAO
        newFlight.departureDate = flight.departureDate
        newFlight.departureTimeUTC = flight.departureTimeUTC
        newFlight.arrivalDate = flight.arrivalDate
        newFlight.arrivalTimeUTC = flight.arrivalTimeUTC
        newFlight.aircraft = flight.aircraft
        newFlight.crew = flight.crew
        newFlight.passengers = flight.passengers
        newFlight.nature = flight.nature
        newFlight.contact = flight.contact
        newFlight.observations = flight.observations
        newFlight.reasonForVisit = flight.reasonForVisit
        newFlight.responsiblePerson = flight.responsiblePerson
        modelContext.insert(newFlight)
    }
}

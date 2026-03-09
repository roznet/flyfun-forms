import QuickLook
import SwiftUI
import SwiftData

struct FlightEditView: View {
    @Bindable var flight: Flight
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]
    @Query(sort: \Person.lastName) private var allPeople: [Person]
    @Environment(\.airportCatalog) private var catalog
    @Environment(AppState.self) private var appState

    @State private var isGenerating = false
    @State private var generatingForm: String?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var previewURL: URL?
    @State private var formDetails: [String: [FormInfo]] = [:]  // icao -> forms
    @State private var extraFieldValues: [String: [String: ExtraFieldValue]] = [:]  // "airport_form" -> values
    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        Form {
            Section("Route") {
                TextField("Origin (ICAO)", text: $flight.originICAO)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                TextField("Destination (ICAO)", text: $flight.destinationICAO)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
            }

            Section("Schedule") {
                DatePicker("Departure Date", selection: $flight.departureDate, displayedComponents: .date)
                TextField("Departure Time (UTC, e.g. 08:00)", text: $flight.departureTimeUTC)
                DatePicker("Arrival Date", selection: $flight.arrivalDate, displayedComponents: .date)
                TextField("Arrival Time (UTC, e.g. 09:00)", text: $flight.arrivalTimeUTC)
            }

            Section("Aircraft") {
                Picker("Aircraft", selection: $flight.aircraft) {
                    Text("None").tag(nil as Aircraft?)
                    ForEach(allAircraft) { ac in
                        Text("\(ac.registration) (\(ac.type))").tag(ac as Aircraft?)
                    }
                }
            }

            Section("Crew") {
                ForEach(flight.crewList) { person in
                    Text(person.displayName)
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                flight.crew?.removeAll { $0.persistentModelID == person.persistentModelID }
                            }
                        }
                }
                Menu("Add Crew") {
                    ForEach(availablePeople) { person in
                        Button(person.displayName) {
                            if flight.crew == nil { flight.crew = [] }
                            flight.crew?.append(person)
                        }
                    }
                }
                .disabled(availablePeople.isEmpty)
            }

            Section("Passengers") {
                ForEach(flight.passengerList) { person in
                    Text(person.displayName)
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                flight.passengers?.removeAll { $0.persistentModelID == person.persistentModelID }
                            }
                        }
                }
                Menu("Add Passenger") {
                    ForEach(availablePeople) { person in
                        Button(person.displayName) {
                            if flight.passengers == nil { flight.passengers = [] }
                            flight.passengers?.append(person)
                        }
                    }
                }
                .disabled(availablePeople.isEmpty)
            }

            Section("Flight Details") {
                Picker("Nature", selection: $flight.nature) {
                    Text("Private").tag("private")
                    Text("Commercial").tag("commercial")
                }
                TextField("Contact (phone, email)", text: Binding(
                    get: { flight.contact ?? "" },
                    set: { flight.contact = $0.isEmpty ? nil : $0 }
                ))
                TextField("Observations", text: Binding(
                    get: { flight.observations ?? "" },
                    set: { flight.observations = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
            }

            // Dynamic form sections per airport
            if !flight.destinationICAO.isEmpty {
                formSection(airport: flight.destinationICAO, direction: "arrival")
            }
            if !flight.originICAO.isEmpty {
                formSection(airport: flight.originICAO, direction: "departure")
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
        .onChange(of: flight.originICAO) { fetchFormDetails(icao: flight.originICAO) }
        .onChange(of: flight.destinationICAO) { fetchFormDetails(icao: flight.destinationICAO) }
        .onAppear {
            fetchFormDetails(icao: flight.originICAO)
            fetchFormDetails(icao: flight.destinationICAO)
        }
    }

    @ViewBuilder
    private func formSection(airport: String, direction: String) -> some View {
        let forms = formDetails[airport] ?? []
        if !forms.isEmpty {
            ForEach(forms) { formInfo in
                Section("\(airport) — \(formInfo.label) (\(direction))") {
                    // Extra fields for this form
                    extraFieldsView(airport: airport, formInfo: formInfo)

                    // Generate button
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
        ForEach(formInfo.extraFields) { field in
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
                // Show address of selected person
                if case .person(let dict) = extraFieldValues[formKey]?[field.key],
                   !dict.isEmpty {
                    TextField("Address", text: personAddressBinding(formKey: formKey, fieldKey: field.key))
                        .foregroundStyle(.secondary)
                }
            default: // text
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
        let flightPayload = FlightPayload(
            origin: flight.originICAO,
            destination: flight.destinationICAO,
            departureDate: dateFmt.string(from: flight.departureDate),
            departureTimeUtc: flight.departureTimeUTC,
            arrivalDate: dateFmt.string(from: flight.arrivalDate),
            arrivalTimeUtc: flight.arrivalTimeUTC,
            nature: flight.nature,
            contact: flight.contact
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
        let extras = extraFieldValues[formKey]

        return GenerateRequest(
            airport: airport,
            form: form,
            flight: flightPayload,
            aircraft: aircraftPayload,
            crew: crewPayloads,
            passengers: paxPayloads,
            extraFields: extras?.isEmpty == false ? extras : nil,
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
}


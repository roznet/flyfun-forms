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

            if !flight.originICAO.isEmpty && !flight.destinationICAO.isEmpty {
                Section("Available Forms") {
                    let destForms = catalog.formsForAirport(icao: flight.destinationICAO)
                    let originForms = catalog.formsForAirport(icao: flight.originICAO)

                    if !destForms.isEmpty {
                        ForEach(destForms, id: \.self) { form in
                            formButton(airport: flight.destinationICAO, form: form, label: "arrival")
                        }
                    }
                    if !originForms.isEmpty {
                        ForEach(originForms, id: \.self) { form in
                            formButton(airport: flight.originICAO, form: form, label: "departure")
                        }
                    }
                    if destForms.isEmpty && originForms.isEmpty {
                        Text("No forms required for this route")
                            .foregroundStyle(.secondary)
                    }
                }
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
    }

    @ViewBuilder
    private func formButton(airport: String, form: String, label: String) -> some View {
        Button {
            Task { await generateForm(airport: airport, form: form) }
        } label: {
            HStack {
                Label("\(airport) — \(form) (\(label))", systemImage: "doc.text")
                Spacer()
                if generatingForm == "\(airport)_\(form)" {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(isGenerating)
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

        let crewPayloads = flight.crewList.map { personPayload($0) }
        let paxPayloads = flight.passengerList.map { personPayload($0) }

        return GenerateRequest(
            airport: airport,
            form: form,
            flight: flightPayload,
            aircraft: aircraftPayload,
            crew: crewPayloads,
            passengers: paxPayloads,
            observations: flight.observations
        )
    }

    private func personPayload(_ p: Person) -> PersonPayload {
        PersonPayload(
            firstName: p.firstName,
            lastName: p.lastName,
            dob: p.dateOfBirth.map { dateFmt.string(from: $0) },
            nationality: p.nationality,
            idNumber: p.idNumber,
            idType: p.idType,
            idIssuingCountry: p.idIssuingCountry,
            idExpiry: p.idExpiry.map { dateFmt.string(from: $0) },
            sex: p.sex,
            placeOfBirth: p.placeOfBirth
        )
    }

    private var availablePeople: [Person] {
        let crewIDs = Set(flight.crewList.map(\.persistentModelID))
        let paxIDs = Set(flight.passengerList.map(\.persistentModelID))
        return allPeople.filter { !crewIDs.contains($0.persistentModelID) && !paxIDs.contains($0.persistentModelID) }
    }
}


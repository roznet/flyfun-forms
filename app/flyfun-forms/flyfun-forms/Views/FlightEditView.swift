import SwiftUI
import SwiftData

struct FlightEditView: View {
    @Bindable var flight: Flight
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]
    @Query(sort: \Person.lastName) private var allPeople: [Person]
    @Environment(\.airportCatalog) private var catalog

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
                            Label("\(flight.destinationICAO) — \(form) (arrival)",
                                  systemImage: "doc.text")
                        }
                    }
                    if !originForms.isEmpty {
                        ForEach(originForms, id: \.self) { form in
                            Label("\(flight.originICAO) — \(form) (departure)",
                                  systemImage: "doc.text")
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
    }

    private var availablePeople: [Person] {
        let crewIDs = Set(flight.crewList.map(\.persistentModelID))
        let paxIDs = Set(flight.passengerList.map(\.persistentModelID))
        return allPeople.filter { !crewIDs.contains($0.persistentModelID) && !paxIDs.contains($0.persistentModelID) }
    }
}

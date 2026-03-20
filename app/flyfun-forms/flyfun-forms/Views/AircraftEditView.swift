import SwiftUI
import SwiftData
import RZFlight

struct AircraftEditView: View {
    @Bindable var aircraft: Aircraft

    @State private var showOwnerPicker = false
    @State private var showBasePicker = false

    private let airportDB = AirportDatabase.shared

    var body: some View {
        Form {
            Section("Aircraft") {
                TextField("Registration", text: $aircraft.registration)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                TextField("Type", text: $aircraft.type)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                Picker("Category", selection: $aircraft.isAirplane) {
                    Text("Airplane").tag(true)
                    Text("Helicopter").tag(false)
                }
            }

            Section("Owner") {
                Button {
                    showOwnerPicker = true
                } label: {
                    HStack {
                        Text("Owner")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(aircraft.ownerPerson?.displayName ?? "Select…")
                            .foregroundStyle(aircraft.ownerPerson == nil ? .secondary : .primary)
                    }
                }

                if let person = aircraft.ownerPerson {
                    if let email = person.email, !email.isEmpty {
                        LabeledContent("Email", value: email)
                            .foregroundStyle(.secondary)
                    }
                    if let phone = person.phone, !phone.isEmpty {
                        LabeledContent("Phone", value: phone)
                            .foregroundStyle(.secondary)
                    }
                    if let address = person.address, !address.isEmpty {
                        LabeledContent("Address") {
                            Text(address)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            Section("Base") {
                Button {
                    showBasePicker = true
                } label: {
                    HStack {
                        Text("Usual Base")
                            .foregroundStyle(.primary)
                        Spacer()
                        if let icao = aircraft.usualBase, !icao.isEmpty {
                            VStack(alignment: .trailing) {
                                Text(icao)
                                    .font(.system(.body, design: .monospaced).bold())
                                if let airport = airportDB.airport(icao: icao) {
                                    Text(airport.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("Select…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(aircraft.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showOwnerPicker) {
            SinglePersonPickerView(selectedPerson: $aircraft.ownerPerson, title: "Owner")
        }
        .sheet(isPresented: $showBasePicker) {
            SingleAirportPickerView(
                selectedICAO: Binding(
                    get: { aircraft.usualBase ?? "" },
                    set: { aircraft.usualBase = $0.isEmpty ? nil : $0 }
                ),
                title: "Usual Base"
            )
        }
        .onChange(of: aircraft.ownerPerson) {
            // Sync owner fields from the selected person for API payloads
            if let person = aircraft.ownerPerson {
                aircraft.owner = person.displayName
                aircraft.ownerAddress = person.address
            } else {
                aircraft.owner = nil
                aircraft.ownerAddress = nil
            }
        }
    }
}

import SwiftUI

struct AircraftEditView: View {
    @Bindable var aircraft: Aircraft

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
                TextField("Owner Name", text: Binding(
                    get: { aircraft.owner ?? "" },
                    set: { aircraft.owner = $0.isEmpty ? nil : $0 }
                ))
                TextField("Owner Address", text: Binding(
                    get: { aircraft.ownerAddress ?? "" },
                    set: { aircraft.ownerAddress = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
            }

            Section("Base") {
                TextField("Usual Base (ICAO)", text: Binding(
                    get: { aircraft.usualBase ?? "" },
                    set: { aircraft.usualBase = $0.isEmpty ? nil : $0.uppercased() }
                ))
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
            }
        }
        .navigationTitle(aircraft.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

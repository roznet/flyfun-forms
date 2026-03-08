import SwiftUI

struct PersonEditView: View {
    @Bindable var person: Person

    private static let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .year, value: -120, to: Date())!
        return earliest...Date()
    }()

    var body: some View {
        Form {
            Section("Name") {
                TextField("First Name", text: $person.firstName)
                    .textContentType(.givenName)
                TextField("Last Name", text: $person.lastName)
                    .textContentType(.familyName)
            }

            Section("Details") {
                OptionalDatePicker("Date of Birth", selection: $person.dateOfBirth, in: Self.dateRange)
                TextField("Nationality (e.g. FRA)", text: Binding(
                    get: { person.nationality ?? "" },
                    set: { person.nationality = $0.isEmpty ? nil : $0.uppercased() }
                ))
                TextField("Place of Birth", text: Binding(
                    get: { person.placeOfBirth ?? "" },
                    set: { person.placeOfBirth = $0.isEmpty ? nil : $0 }
                ))
                Picker("Sex", selection: Binding(
                    get: { person.sex ?? "" },
                    set: { person.sex = $0.isEmpty ? nil : $0 }
                )) {
                    Text("—").tag("")
                    Text("Male").tag("Male")
                    Text("Female").tag("Female")
                }
            }

            Section("Identity Document") {
                Picker("Document Type", selection: Binding(
                    get: { person.idType ?? "" },
                    set: { person.idType = $0.isEmpty ? nil : $0 }
                )) {
                    Text("—").tag("")
                    Text("Passport").tag("Passport")
                    Text("Identity card").tag("Identity card")
                    Text("Other").tag("Other")
                }
                TextField("Document Number", text: Binding(
                    get: { person.idNumber ?? "" },
                    set: { person.idNumber = $0.isEmpty ? nil : $0 }
                ))
                TextField("Issuing Country (e.g. FRA)", text: Binding(
                    get: { person.idIssuingCountry ?? "" },
                    set: { person.idIssuingCountry = $0.isEmpty ? nil : $0.uppercased() }
                ))
                OptionalDatePicker("Expiry Date", selection: $person.idExpiry)
            }

            Section {
                Toggle("Usual Crew Member", isOn: $person.isUsualCrew)
            }
        }
        .navigationTitle(person.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// Helper for optional Date bindings with DatePicker
struct OptionalDatePicker: View {
    let label: String
    @Binding var selection: Date?
    var range: ClosedRange<Date>?

    init(_ label: String, selection: Binding<Date?>, in range: ClosedRange<Date>? = nil) {
        self.label = label
        self._selection = selection
        self.range = range
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let date = selection {
                Group {
                    if let range {
                        DatePicker("", selection: Binding(
                            get: { date },
                            set: { selection = $0 }
                        ), in: range, displayedComponents: .date)
                    } else {
                        DatePicker("", selection: Binding(
                            get: { date },
                            set: { selection = $0 }
                        ), displayedComponents: .date)
                    }
                }
                .labelsHidden()
                Button { selection = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Set") { selection = Date() }
                    .foregroundStyle(.blue)
            }
        }
    }
}

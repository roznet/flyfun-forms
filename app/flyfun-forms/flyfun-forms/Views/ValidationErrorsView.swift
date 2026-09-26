import FlyFunCommon
import SwiftData
import SwiftUI

/// The fields a form request was rejected for, each with the control that
/// fixes it where there is one, and a way to send the form again.
///
/// Edits go straight to the flight, people and aircraft, so a value filled in
/// here is there for the next flight too. Without a `context` (or for an error
/// `ValidationFixContext` cannot map) a row only reads the error.
struct ValidationErrorsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Aircraft.registration) private var allAircraft: [Aircraft]

    let errors: [ServerValidationError]
    var context: ValidationFixContext?
    @Binding var extraFieldValues: [String: [String: ExtraFieldValue]]
    var isRetrying = false
    var onRetry: (() -> Void)?

    @State private var showResponsiblePersonPicker = false

    var body: some View {
        NavigationStack {
            Form {
                ForEach(errors) { error in
                    let fix = context?.fix(for: error) ?? .none
                    Section {
                        errorLabel(error, fix: fix)
                        fixRows(fix)
                    }
                }

                if let onRetry {
                    Section {
                        Button(action: onRetry) {
                            HStack {
                                Text("Try Again")
                                Spacer()
                                if isRetrying { ProgressView() }
                            }
                        }
                        .disabled(isRetrying)
                        .accessibilityIdentifier("validationRetryButton")
                    }
                }
            }
            .platformFormStyle()
            .navigationTitle("Validation Errors")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showResponsiblePersonPicker) {
                if let flight = context?.flight {
                    SinglePersonPickerView(selectedPerson: Binding(
                        get: { flight.responsiblePerson },
                        set: { flight.setResponsiblePerson($0) }
                    ))
                }
            }
        }
    }

    private func errorLabel(_ error: ServerValidationError, fix: ValidationFix) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error.displayField)
                .font(.headline)
            if let person = fix.person {
                Text(person.displayName)
                    .font(.subheadline)
            }
            Text(error.error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let value = error.value, !value.isEmpty {
                Text("Sent: \"\(value)\"")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("validationError-\(error.field)")
    }

    // MARK: - Editors

    @ViewBuilder
    private func fixRows(_ fix: ValidationFix) -> some View {
        switch fix {
        case .reasonForVisit(let options):
            if let flight = context?.flight {
                Picker("Reason for Visit", selection: Binding(
                    get: { flight.reasonForVisit ?? "" },
                    set: { flight.reasonForVisit = $0.isEmpty ? nil : $0 }
                )) {
                    Text("—").tag("")
                    ForEach(options, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                }
                .accessibilityIdentifier("validationFix-reasonForVisit")
            }
        case .responsiblePerson:
            Button {
                showResponsiblePersonPicker = true
            } label: {
                HStack {
                    Text("Responsible Person")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(context?.flight.responsiblePerson?.displayName ?? String(localized: "Select…"))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("validationFix-responsiblePerson")
        case .personText(let person, let field):
            PersonTextFixRow(person: person, field: field)
        case .personDateOfBirth(let person):
            OptionalDatePicker("Date of Birth", selection: Binding(
                get: { person.dateOfBirth },
                set: { person.dateOfBirth = $0 }
            ), in: PersonEditView.dateRange)
        case .personSex(let person):
            Picker("Sex", selection: Binding(
                get: { person.sex ?? "" },
                set: { person.sex = $0.isEmpty ? nil : $0 }
            )) {
                Text("—").tag("")
                Text("Male", comment: "Sex/gender option").tag("Male")
                Text("Female", comment: "Sex/gender option").tag("Female")
            }
        case .document(let person, let field):
            if let document = context?.document(for: person) {
                DocumentFixRow(document: document, field: field)
            } else {
                Button("Add Document") {
                    let document = TravelDocument()
                    document.person = person
                    modelContext.insert(document)
                }
                .accessibilityIdentifier("validationFix-addDocument")
            }
        case .aircraftText(let aircraft, let field):
            AircraftTextFixRow(aircraft: aircraft, field: field)
        case .openAircraft(let aircraft):
            NavigationLink("Edit \(aircraft.displayName)") {
                AircraftEditView(aircraft: aircraft)
            }
        case .chooseAircraft:
            if let flight = context?.flight {
                Picker("Aircraft", selection: Binding(
                    get: { flight.aircraft },
                    set: { flight.aircraft = $0 }
                )) {
                    Text("None").tag(nil as Aircraft?)
                    ForEach(allAircraft) { ac in
                        Text("\(ac.registration) (\(ac.type))").tag(ac as Aircraft?)
                    }
                }
            }
        case .extraText(let key):
            TextField(extraFieldLabel(key), text: extraFieldBinding(key))
                .accessibilityIdentifier("validationFix-extra-\(key)")
        case .extraChoice(let key, let options):
            Picker(extraFieldLabel(key), selection: extraFieldBinding(key)) {
                Text("—").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case .none:
            EmptyView()
        }
    }

    private func extraFieldLabel(_ key: String) -> String {
        context?.formInfo?.extraFields.first { $0.key == key }?.label
            ?? ServerValidationError(field: key, error: "").displayField
    }

    /// Same storage as the flight's own extra field rows, so the value shows
    /// there too once the sheet is closed.
    private func extraFieldBinding(_ key: String) -> Binding<String> {
        let formKey = context?.formKey ?? ""
        return Binding(
            get: {
                if case .text(let value) = extraFieldValues[formKey]?[key] { return value }
                return ""
            },
            set: { newValue in
                extraFieldValues[formKey, default: [:]][key] = .text(newValue)
            }
        )
    }
}

private struct PersonTextFixRow: View {
    @Bindable var person: Person
    let field: ValidationFix.PersonTextField

    var body: some View {
        switch field {
        case .firstName:
            TextField("First Name", text: $person.firstName)
                .textContentType(.givenName)
        case .lastName:
            TextField("Last Name", text: $person.lastName)
                .textContentType(.familyName)
        case .placeOfBirth:
            TextField("Place of Birth", text: optional(\.placeOfBirth))
        case .address:
            TextField("Address", text: optional(\.address), axis: .vertical)
                .lineLimit(2...3)
        case .phone:
            TextField("Phone", text: optional(\.phone))
                .textContentType(.telephoneNumber)
                #if os(iOS)
                .keyboardType(.phonePad)
                #endif
                .accessibilityIdentifier("validationFix-phone")
        case .email:
            TextField("Email", text: optional(\.email))
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier("validationFix-email")
        }
    }

    private func optional(_ keyPath: ReferenceWritableKeyPath<Person, String?>) -> Binding<String> {
        Binding(
            get: { person[keyPath: keyPath] ?? "" },
            set: { person[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct DocumentFixRow: View {
    @Bindable var document: TravelDocument
    let field: ValidationFix.DocumentField

    var body: some View {
        switch field {
        case .number:
            TextField("Document Number", text: $document.docNumber)
                .accessibilityIdentifier("validationFix-documentNumber")
        case .type:
            Picker("Document Type", selection: $document.docType) {
                Text("Passport", comment: "Document type").tag("Passport")
                Text("Identity card", comment: "Document type").tag("Identity card")
                Text("Other", comment: "Document type").tag("Other")
            }
        case .issuingCountry:
            TextField("Issuing Country (e.g. FRA)", text: Binding(
                get: { document.issuingCountry ?? "" },
                set: { document.issuingCountry = $0.isEmpty ? nil : $0.uppercased() }
            ))
        case .expiry:
            OptionalDatePicker("Expiry Date", selection: $document.expiryDate)
        }
    }
}

private struct AircraftTextFixRow: View {
    @Bindable var aircraft: Aircraft
    let field: ValidationFix.AircraftTextField

    var body: some View {
        switch field {
        case .registration:
            TextField("Registration", text: $aircraft.registration)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
        case .type:
            TextField("Type", text: $aircraft.type)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
        }
    }
}

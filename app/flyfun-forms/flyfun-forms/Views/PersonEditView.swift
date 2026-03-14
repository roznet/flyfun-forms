import SwiftUI
import SwiftData

struct PersonEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var person: Person
    #if os(iOS)
    @State private var showingScanSheet = false
    @State private var scanProcessingResult: MRZProcessingResult?
    #endif

    private static let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .year, value: -120, to: Date())!
        return earliest...Date()
    }()

    var body: some View {
        Group {
            if sizeClass == .compact {
                Form {
                    personInfoSections
                    documentsSections
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Form {
                        personInfoSections
                    }
                    .frame(maxWidth: .infinity)
                    NavigationStack {
                        Form {
                            documentsSections
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(person.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingScanSheet = true
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                }
            }
        }
        .sheet(isPresented: $showingScanSheet) {
            ScanDocumentSheet { result in
                let processing = MRZResultProcessor.process(result, context: .person(person), modelContext: modelContext)
                scanProcessingResult = processing
            }
        }
        .sheet(item: $scanProcessingResult) { processing in
            MRZResultActionView(
                processingResult: processing,
                onDismiss: { scanProcessingResult = nil }
            )
        }
        #endif
    }

    @ViewBuilder
    private var personInfoSections: some View {
        Section("Name") {
            TextField("First Name", text: $person.firstName)
                .textContentType(.givenName)
            TextField("Last Name", text: $person.lastName)
                .textContentType(.familyName)
        }

        Section("Details") {
            OptionalDatePicker("Date of Birth", selection: $person.dateOfBirth, in: Self.dateRange)
            TextField("Place of Birth", text: Binding(
                get: { person.placeOfBirth ?? "" },
                set: { person.placeOfBirth = $0.isEmpty ? nil : $0 }
            ))
            Picker("Sex", selection: Binding(
                get: { person.sex ?? "" },
                set: { person.sex = $0.isEmpty ? nil : $0 }
            )) {
                Text("—").tag("")
                Text("Male", comment: "Sex/gender option").tag("Male")
                Text("Female", comment: "Sex/gender option").tag("Female")
            }
            TextField("Phone", text: Binding(
                get: { person.phone ?? "" },
                set: { person.phone = $0.isEmpty ? nil : $0 }
            ))
            .textContentType(.telephoneNumber)
            TextField("Address", text: Binding(
                get: { person.address ?? "" },
                set: { person.address = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...3)
        }
    }

    @ViewBuilder
    private var documentsSections: some View {
        Section("Documents") {
            ForEach(person.documentList) { doc in
                NavigationLink(destination: DocumentEditView(document: doc)) {
                    VStack(alignment: .leading) {
                        Text(doc.displayLabel)
                        if let expiry = doc.expiryDate {
                            Text("Expires \(expiry, format: .dateTime.day().month().year())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                let docs = person.documentList
                for i in offsets {
                    modelContext.delete(docs[i])
                }
            }

            Button("Add Document") {
                let doc = TravelDocument()
                doc.person = person
                modelContext.insert(doc)
            }
        }

        Section {
            Toggle("Usual Crew Member", isOn: $person.isUsualCrew)
        }
    }
}

struct DocumentEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: TravelDocument
    #if os(iOS)
    @State private var showingScanSheet = false
    @State private var scanProcessingResult: MRZProcessingResult?
    #endif

    var body: some View {
        Form {
            Picker("Document Type", selection: $document.docType) {
                Text("Passport", comment: "Document type").tag("Passport")
                Text("Identity card", comment: "Document type").tag("Identity card")
                Text("Other", comment: "Document type").tag("Other")
            }
            TextField("Document Number", text: $document.docNumber)
            TextField("Issuing Country (e.g. FRA)", text: Binding(
                get: { document.issuingCountry ?? "" },
                set: { document.issuingCountry = $0.isEmpty ? nil : $0.uppercased() }
            ))
            OptionalDatePicker("Expiry Date", selection: $document.expiryDate)
        }
        .navigationTitle(document.displayLabel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingScanSheet = true
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                }
            }
        }
        .sheet(isPresented: $showingScanSheet) {
            ScanDocumentSheet { result in
                let processing = MRZResultProcessor.process(result, context: .document(document), modelContext: modelContext)
                if !processing.namesMismatch && processing.duplicateDocument == nil {
                    MRZResultProcessor.fillDocument(document, from: result)
                    if let person = document.person {
                        MRZResultProcessor.fillPerson(person, from: result)
                    }
                } else {
                    scanProcessingResult = processing
                }
            }
        }
        .sheet(item: $scanProcessingResult) { processing in
            MRZResultActionView(
                processingResult: processing,
                onDismiss: { scanProcessingResult = nil }
            )
        }
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

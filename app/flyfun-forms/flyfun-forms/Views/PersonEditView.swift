import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PersonEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var person: Person
    #if os(iOS)
    @State private var showingScanSheet = false
    #else
    @State private var showFilePicker = false
    #endif
    @State private var scanProcessingResult: MRZProcessingResult?
    @State private var imageOCR = ImageOCRManager()
    @State private var showScanError = false

    private static let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .year, value: -120, to: Date())!
        return earliest...Date()
    }()

    var body: some View {
        Group {
            if isWide {
                wideLayout
            } else {
                Form {
                    personInfoSections
                    crewFlagSection
                    documentsSections
                }
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
        #else
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFilePicker = true
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                imageOCR.scan(url: url)
            }
        }
        .onChange(of: imageOCR.status) { _, newStatus in
            if newStatus == .success, let scanResult = imageOCR.result {
                let processing = MRZResultProcessor.process(scanResult, context: .person(person), modelContext: modelContext)
                if !processing.namesMismatch && processing.duplicateDocument == nil {
                    MRZResultProcessor.fillPerson(person, from: scanResult)
                    MRZResultProcessor.createDocument(for: person, from: scanResult, in: modelContext)
                } else {
                    scanProcessingResult = processing
                }
            } else if newStatus == .noMRZFound {
                showScanError = true
            }
        }
        .alert("No Document Found", isPresented: $showScanError) {
            Button("OK") {}
        } message: {
            Text("No machine-readable zone (MRZ) was found in the file. Try a clearer image or PDF of the passport page.")
        }
        #endif
        .sheet(item: $scanProcessingResult) { processing in
            MRZResultActionView(
                processingResult: processing,
                onDismiss: { scanProcessingResult = nil }
            )
        }
    }

    private var isWide: Bool { sizeClass != .compact }

    /// Identity on the left, travel documents on the right.
    ///
    /// The documents column used to be a `NavigationStack` nested inside the
    /// split view's detail column, so opening a passport pushed a second stack
    /// inside a half-width pane. Here a document opens in place.
    private var wideLayout: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 0) {
                FormColumn {
                    personInfoSections
                    crewFlagSection
                }
                Divider()
                FormColumn {
                    documentsSections
                }
            }
        }
    }

    private var header: some View {
        DetailHeader {
            Text(person.displayName)
                .font(.title2.bold())
            HStack(spacing: 6) {
                if let nationality = person.nationality, !nationality.isEmpty {
                    Text(verbatim: nationality)
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                }
                Text(activeDocuments.count == 1
                     ? String(localized: "1 document")
                     : String(localized: "\(activeDocuments.count) documents"))
                if let warning = documentWarning {
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Label(warning.text, systemImage: warning.symbol)
                        .foregroundStyle(warning.tint)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var activeDocuments: [TravelDocument] {
        person.documentList.filter(\.isActive)
    }

    /// The worst expiry state across the person's active documents, so a stale
    /// passport is visible before a form generation fails on it.
    private var documentWarning: (text: String, symbol: String, tint: Color)? {
        let states = activeDocuments.map { DocumentExpiry(date: $0.expiryDate) }
        if states.contains(.expired) {
            return (String(localized: "Document expired"), "exclamationmark.triangle.fill", .red)
        }
        if states.contains(.expiringSoon) {
            return (String(localized: "Expires soon"), "exclamationmark.circle.fill", .orange)
        }
        return nil
    }

    /// A person-level flag; it used to sit unlabelled under Documents, where it
    /// read as a property of the passport above it.
    @ViewBuilder
    private var crewFlagSection: some View {
        Section("Role") {
            Toggle("Usual Crew Member", isOn: $person.isUsualCrew)
        }
    }

    @ViewBuilder
    private var personInfoSections: some View {
        Section("Name") {
            TextField("First Name", text: $person.firstName)
                .textContentType(.givenName)
                .accessibilityIdentifier("personFirstNameField")
            TextField("Last Name", text: $person.lastName)
                .textContentType(.familyName)
                .accessibilityIdentifier("personLastNameField")
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
            TextField("Email", text: Binding(
                get: { person.email ?? "" },
                set: { person.email = $0.isEmpty ? nil : $0 }
            ))
            .textContentType(.emailAddress)
            #if os(iOS)
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            #endif
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
                if isWide {
                    DisclosureGroup {
                        DocumentFields(document: doc)
                        Button("Delete Document", role: .destructive) {
                            modelContext.delete(doc)
                        }
                    } label: {
                        documentLabel(doc)
                    }
                } else {
                    NavigationLink(destination: DocumentEditView(document: doc)) {
                        documentLabel(doc)
                    }
                    .accessibilityIdentifier("documentRow-\(doc.issuingCountry ?? "new")")
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
            .accessibilityIdentifier("addDocumentButton")
        }
    }

    @ViewBuilder
    private func documentLabel(_ doc: TravelDocument) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(doc.displayLabel)
                if !doc.isActive {
                    Text("Inactive")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            if let expiry = doc.expiryDate {
                let state = doc.isActive ? DocumentExpiry(date: expiry) : .valid
                Text("Expires \(expiry, format: .dateTime.day().month().year())")
                    .font(.caption)
                    .foregroundStyle(state.tint)
                    .accessibilityValue(state.spokenState ?? "")
            }
        }
        .opacity(doc.isActive ? 1 : 0.5)
    }
}

/// How close a travel document is to being unusable. Six months is the margin
/// most destinations ask for beyond the date of travel, so it is the point at
/// which the row stops being plain grey text.
enum DocumentExpiry {
    case valid, expiringSoon, expired

    init(date: Date?) {
        guard let date else { self = .valid; return }
        if date < Date() {
            self = .expired
        } else if date < Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? date {
            self = .expiringSoon
        } else {
            self = .valid
        }
    }

    /// Said alongside the expiry date, so the state is not carried by the
    /// row's colour alone. Nil when there is nothing to flag.
    var spokenState: String? {
        switch self {
        case .valid: nil
        case .expiringSoon: String(localized: "Expires soon")
        case .expired: String(localized: "Document expired")
        }
    }

    var tint: Color {
        switch self {
        case .valid: .secondary
        case .expiringSoon: .orange
        case .expired: .red
        }
    }
}

/// The fields of a travel document, without any container, so the same rows
/// serve the pushed editor on iPhone and the in-place disclosure on a wide
/// layout.
struct DocumentFields: View {
    @Bindable var document: TravelDocument

    var body: some View {
        Picker("Document Type", selection: $document.docType) {
            Text("Passport", comment: "Document type").tag("Passport")
            Text("Identity card", comment: "Document type").tag("Identity card")
            Text("Other", comment: "Document type").tag("Other")
        }
        TextField("Document Number", text: $document.docNumber)
            .accessibilityIdentifier("documentNumberField")
        TextField("Issuing Country (e.g. FRA)", text: Binding(
            get: { document.issuingCountry ?? "" },
            set: { document.issuingCountry = $0.isEmpty ? nil : $0.uppercased() }
        ))
        .accessibilityIdentifier("documentCountryField")
        OptionalDatePicker("Expiry Date", selection: $document.expiryDate)
        Toggle("Active", isOn: $document.isActive)
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
            DocumentFields(document: document)
        }
        .platformFormStyle()
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

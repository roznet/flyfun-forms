#if os(iOS)
import SwiftUI
import SwiftData

/// Presents the result of an MRZ scan and lets the user choose how to handle it.
struct MRZResultActionView: View {
    let processingResult: MRZProcessingResult
    let onDismiss: () -> Void
    /// Called when a person is created or selected so the caller can navigate to them.
    var onPersonSelected: ((Person) -> Void)?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                scannedInfoSection
                if let dup = processingResult.duplicateDocument {
                    duplicateWarningSection(dup)
                }
                actionsSection
            }
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Scanned Info

    @ViewBuilder
    private var scannedInfoSection: some View {
        let r = processingResult.scanResult
        Section("Scanned Document") {
            LabeledContent("Name", value: "\(r.givenNames) \(r.surname)")
            LabeledContent("Document", value: "\(r.format == .td1 ? String(localized: "ID Card") : String(localized: "Passport", comment: "Document type")) \(r.passportNumber)")
            LabeledContent("Nationality", value: r.nationality)
            LabeledContent("Date of Birth", value: r.dateOfBirth, format: .dateTime.day().month().year())
            LabeledContent("Expiry", value: r.expiryDate, format: .dateTime.day().month().year())
        }
    }

    // MARK: - Duplicate Warning

    @ViewBuilder
    private func duplicateWarningSection(_ doc: TravelDocument) -> some View {
        Section {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("Document already exists")
                        .font(.subheadline.weight(.semibold))
                    if let owner = doc.person {
                        Text("Assigned to \(owner.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        switch processingResult.context {
        case .document(let doc):
            documentContextActions(doc)
        case .person(let person):
            personContextActions(person)
        case .standalone:
            standaloneActions
        }
    }

    // Workflow A: scanning from document edit
    @ViewBuilder
    private func documentContextActions(_ doc: TravelDocument) -> some View {
        let result = processingResult.scanResult
        let isDuplicate = processingResult.duplicateDocument != nil

        Section(isDuplicate ? "Actions (document already exists)" : "Actions") {
            if !isDuplicate {
                Button {
                    MRZResultProcessor.fillDocument(doc, from: result)
                    if let person = doc.person {
                        MRZResultProcessor.fillPerson(person, from: result)
                    }
                    onDismiss()
                } label: {
                    Label("Fill document fields", systemImage: "doc.text.fill")
                }
            }

            if processingResult.namesMismatch, let person = doc.person {
                Button {
                    MRZResultProcessor.fillDocument(doc, from: result)
                    MRZResultProcessor.fillPerson(person, from: result, overwriteName: true)
                    onDismiss()
                } label: {
                    Label("Fill and update name to \(result.givenNames) \(result.surname)", systemImage: "person.text.rectangle")
                }

                if !isDuplicate {
                    Button {
                        MRZResultProcessor.fillDocument(doc, from: result)
                        onDismiss()
                    } label: {
                        Label("Fill document only (keep name \(person.displayName))", systemImage: "doc.text")
                    }
                }
            }
        }
    }

    // Workflow C: scanning from person edit
    @ViewBuilder
    private func personContextActions(_ person: Person) -> some View {
        let result = processingResult.scanResult
        let isDuplicate = processingResult.duplicateDocument != nil

        Section(isDuplicate ? "Actions (document already exists)" : "Actions") {
            if !isDuplicate {
                Button {
                    MRZResultProcessor.createDocument(for: person, from: result, in: modelContext)
                    MRZResultProcessor.fillPerson(person, from: result)
                    onDismiss()
                } label: {
                    Label("Add document to \(person.displayName)", systemImage: "plus.rectangle.on.folder")
                }
            }

            if processingResult.namesMismatch {
                if !isDuplicate {
                    Button {
                        MRZResultProcessor.createDocument(for: person, from: result, in: modelContext)
                        MRZResultProcessor.fillPerson(person, from: result, overwriteName: true)
                        onDismiss()
                    } label: {
                        Label("Add document and update name", systemImage: "person.text.rectangle")
                    }
                }

                Button {
                    let newPerson = MRZResultProcessor.createPersonWithDocument(from: result, in: modelContext)
                    onDismiss()
                    onPersonSelected?(newPerson)
                } label: {
                    Label("Create new person instead", systemImage: "person.badge.plus")
                }
            }
        }
    }

    // Workflow B: standalone scan from people list
    @ViewBuilder
    private var standaloneActions: some View {
        let result = processingResult.scanResult
        let isDuplicate = processingResult.duplicateDocument != nil
        let matches = processingResult.matchingPeople

        if !matches.isEmpty {
            Section("Matching People") {
                ForEach(matches) { person in
                    Button {
                        if !isDuplicate {
                            MRZResultProcessor.createDocument(for: person, from: result, in: modelContext)
                        }
                        MRZResultProcessor.fillPerson(person, from: result)
                        onDismiss()
                        onPersonSelected?(person)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(person.displayName)
                                    .foregroundStyle(.primary)
                                if let nat = person.nationality {
                                    Text(nat)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }

        Section(matches.isEmpty ? "Actions" : "Or") {
            Button {
                let person = MRZResultProcessor.createPersonWithDocument(from: result, in: modelContext)
                onDismiss()
                onPersonSelected?(person)
            } label: {
                Label("Create new person", systemImage: "person.badge.plus")
            }
        }
    }
}
#endif

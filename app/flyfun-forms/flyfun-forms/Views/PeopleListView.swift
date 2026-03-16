import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PeopleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.lastName) private var people: [Person]
    @State private var showingImporter = false
    @State private var importResult: ImportResult?
    @State private var searchText = ""
    @State private var sortByLastUsed = false
    @State private var newPerson: Person?
    @State private var showingScanSheet = false
    @State private var scanProcessingResult: MRZProcessingResult?
    @State private var navigateToPerson: Person?
    #if os(macOS)
    @State private var showFilePicker = false
    @State private var imageOCR = ImageOCRManager()
    @State private var showingExporter = false
    #endif

    private var filteredPeople: [Person] {
        let needle = searchText.lowercased()
        let filtered = needle.isEmpty ? people : people.filter {
            $0.firstName.lowercased().contains(needle) ||
            $0.lastName.lowercased().contains(needle)
        }
        if sortByLastUsed {
            return filtered.sorted {
                ($0.lastFlightDate ?? .distantPast) > ($1.lastFlightDate ?? .distantPast)
            }
        }
        return filtered
    }

    var body: some View {
        List {
            ForEach(filteredPeople) { person in
                NavigationLink(value: person) {
                    VStack(alignment: .leading) {
                        Text(person.displayName)
                            .font(.headline)
                        HStack(spacing: 8) {
                            if let nationality = person.nationality {
                                Text(nationality)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if person.isUsualCrew {
                                Text("Crew")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            if sortByLastUsed, let date = person.lastFlightDate {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete(perform: deletePeople)
        }
        .searchable(text: $searchText, prompt: "Search by name")
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sortByLastUsed.toggle()
                } label: {
                    Label(
                        sortByLastUsed ? "Sort A-Z" : "Sort by Recent",
                        systemImage: sortByLastUsed ? "textformat.abc" : "clock"
                    )
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        let person = Person()
                        modelContext.insert(person)
                        newPerson = person
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                    #if os(iOS)
                    Button {
                        showingScanSheet = true
                    } label: {
                        Label("Scan Document", systemImage: "doc.text.viewfinder")
                    }
                    #else
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Scan Document", systemImage: "doc.text.viewfinder")
                    }
                    #endif
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from CSV", systemImage: "square.and.arrow.down")
                    }
                    #if os(macOS)
                    Divider()
                    Button {
                        showingExporter = true
                    } label: {
                        Label("Export to CSV", systemImage: "square.and.arrow.up")
                    }
                    #endif
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            importResult?.title ?? "",
            isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })
        ) {
            Button("OK") { importResult = nil }
        } message: {
            Text(importResult?.message ?? "")
        }
        .navigationDestination(for: Person.self) { person in
            PersonEditView(person: person)
        }
        .navigationDestination(item: $newPerson) { person in
            PersonEditView(person: person)
        }
        #if os(iOS)
        .sheet(isPresented: $showingScanSheet) {
            ScanDocumentSheet { result in
                let processing = MRZResultProcessor.process(result, context: .standalone, modelContext: modelContext)
                scanProcessingResult = processing
            }
        }
        #else
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
            if newStatus == .success, let result = imageOCR.result {
                let processing = MRZResultProcessor.process(result, context: .standalone, modelContext: modelContext)
                scanProcessingResult = processing
            } else if newStatus == .noMRZFound {
                importResult = ImportResult(
                    title: String(localized: "No Document Found"),
                    message: String(localized: "No machine-readable zone (MRZ) was found in the file. Try a clearer image or PDF of the passport page.")
                )
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVExportDocument(people: people),
            contentType: .commaSeparatedText,
            defaultFilename: "people.csv"
        ) { _ in }
        #endif
        .sheet(item: $scanProcessingResult) { processing in
            MRZResultActionView(
                processingResult: processing,
                onDismiss: { scanProcessingResult = nil },
                onPersonSelected: { person in
                    navigateToPerson = person
                }
            )
        }
        .navigationDestination(item: $navigateToPerson) { person in
            PersonEditView(person: person)
        }
    }

    private func deletePeople(at offsets: IndexSet) {
        let filtered = filteredPeople
        for index in offsets {
            modelContext.delete(filtered[index])
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importResult = ImportResult(
                    title: String(localized: "Error"),
                    message: String(localized: "Could not access file.")
                )
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let (imported, skipped) = try PeopleCSVImporter.importInto(modelContext, from: data)
                var parts: [String] = []
                if imported > 0 { parts.append(String(localized: "\(imported) imported")) }
                if skipped > 0 { parts.append(String(localized: "\(skipped) already existed")) }
                importResult = ImportResult(
                    title: String(localized: "Import Complete"),
                    message: parts.joined(separator: ", ").capitalized + "."
                )
            } catch {
                importResult = ImportResult(title: String(localized: "Import Failed"), message: error.localizedDescription)
            }
        case .failure(let error):
            importResult = ImportResult(title: String(localized: "Error"), message: error.localizedDescription)
        }
    }

}

// MARK: - CSV Export

struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let csvData: Data

    init(people: [Person]) {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        var rows: [[String]] = []
        rows.append(["First Name", "Last Name", "Gender", "DoB", "Nationality",
                      "Doc Type", "Doc Number", "Doc Expiry", "Doc Issuing State", "Type"])

        for person in people {
            let docs = person.documentList
            if docs.isEmpty {
                rows.append([
                    person.firstName,
                    person.lastName,
                    person.sex ?? "",
                    person.dateOfBirth.map { dateFmt.string(from: $0) } ?? "",
                    person.nationality ?? "",
                    "", "", "", "",
                    person.isUsualCrew ? "Crew" : ""
                ])
            } else {
                for doc in docs {
                    rows.append([
                        person.firstName,
                        person.lastName,
                        person.sex ?? "",
                        person.dateOfBirth.map { dateFmt.string(from: $0) } ?? "",
                        person.nationality ?? "",
                        doc.docType,
                        doc.docNumber,
                        doc.expiryDate.map { dateFmt.string(from: $0) } ?? "",
                        doc.issuingCountry ?? "",
                        person.isUsualCrew ? "Crew" : ""
                    ])
                }
            }
        }

        let csv = rows.map { row in
            row.map { field in
                if field.contains(",") || field.contains("\"") || field.contains("\n") {
                    return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return field
            }.joined(separator: ",")
        }.joined(separator: "\n")

        self.csvData = Data(csv.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        csvData = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: csvData)
    }
}

private struct ImportResult {
    let title: String
    let message: String
}

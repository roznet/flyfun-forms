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
    @State private var navigateToPerson: Person?
    @State private var addRequest: AddPersonMethod?
    #if os(macOS)
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
                .accessibilityIdentifier("personRow-\(person.lastName)")
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
                    AddPersonMenuItems(request: $addRequest)
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
                .accessibilityIdentifier("addPersonMenu")
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
        .addPersonFlows(request: $addRequest) { person, method in
            if method == .blank {
                newPerson = person
            } else {
                navigateToPerson = person
            }
        }
        .navigationDestination(for: Person.self) { person in
            PersonEditView(person: person)
        }
        .navigationDestination(item: $newPerson) { person in
            PersonEditView(person: person)
        }
        .onChange(of: newPerson) { left, _ in
            // Backed out of Add Person without typing anything.
            if let left, left.isBlank {
                modelContext.delete(left)
            }
        }
        #if os(macOS)
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVExportDocument(people: people),
            contentType: .commaSeparatedText,
            defaultFilename: "people.csv"
        ) { _ in }
        #endif
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
                let (imported, documentsAdded, skipped) = try PeopleCSVImporter.importInto(modelContext, from: data)
                var parts: [String] = []
                if imported > 0 { parts.append(String(localized: "\(imported) imported")) }
                if documentsAdded > 0 { parts.append(String(localized: "\(documentsAdded) documents added")) }
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

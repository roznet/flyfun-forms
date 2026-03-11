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
    #if os(iOS)
    @State private var showingScanSheet = false
    @State private var scanProcessingResult: MRZProcessingResult?
    @State private var navigateToPerson: Person?
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
            ToolbarItem(placement: .topBarLeading) {
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
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                    #if os(iOS)
                    Button {
                        showingScanSheet = true
                    } label: {
                        Label("Scan Document", systemImage: "doc.text.viewfinder")
                    }
                    #endif
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from CSV", systemImage: "square.and.arrow.down")
                    }
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
        #if os(iOS)
        .sheet(isPresented: $showingScanSheet) {
            ScanDocumentSheet { result in
                let processing = MRZResultProcessor.process(result, context: .standalone, modelContext: modelContext)
                scanProcessingResult = processing
            }
        }
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
        #endif
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
                importResult = ImportResult(title: "Error", message: "Could not access file.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let (imported, skipped) = try PeopleCSVImporter.importInto(modelContext, from: data)
                var parts: [String] = []
                if imported > 0 { parts.append("\(imported) imported") }
                if skipped > 0 { parts.append("\(skipped) already existed") }
                importResult = ImportResult(
                    title: "Import Complete",
                    message: parts.joined(separator: ", ").capitalized + "."
                )
            } catch {
                importResult = ImportResult(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            importResult = ImportResult(title: "Error", message: error.localizedDescription)
        }
    }
}

private struct ImportResult {
    let title: String
    let message: String
}

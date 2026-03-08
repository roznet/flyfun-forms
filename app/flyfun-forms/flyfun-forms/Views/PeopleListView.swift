import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PeopleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.lastName) private var people: [Person]
    @State private var showingImporter = false
    @State private var importResult: ImportResult?

    var body: some View {
        List {
            ForEach(people) { person in
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
                        }
                    }
                }
            }
            .onDelete(perform: deletePeople)
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        let person = Person()
                        modelContext.insert(person)
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
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
    }

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(people[index])
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

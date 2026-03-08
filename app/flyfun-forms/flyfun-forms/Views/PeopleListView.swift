import SwiftUI
import SwiftData

struct PeopleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.lastName) private var people: [Person]

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
                Button {
                    let person = Person()
                    modelContext.insert(person)
                } label: {
                    Label("Add Person", systemImage: "plus")
                }
            }
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
}

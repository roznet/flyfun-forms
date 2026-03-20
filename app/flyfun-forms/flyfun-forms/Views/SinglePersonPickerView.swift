import SwiftUI
import SwiftData

/// Single-select person picker with search and last-used sorting.
/// Same look and feel as PeoplePickerView but allows only one selection.
struct SinglePersonPickerView: View {
    @Binding var selectedPerson: Person?
    var title: String = "Responsible Person"
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.lastName) private var allPeople: [Person]

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search people...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif

                List {
                    if let person = selectedPerson {
                        Section("Selected") {
                            HStack {
                                Text(person.displayName)
                                    .font(.body)
                                Spacer()
                                Button {
                                    selectedPerson = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    let people = filteredPeople
                    if !people.isEmpty {
                        Section("People") {
                            ForEach(people) { person in
                                let isCurrentSelection = selectedPerson?.persistentModelID == person.persistentModelID
                                Button {
                                    selectedPerson = person
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(person.displayName)
                                            HStack(spacing: 8) {
                                                if person.isUsualCrew {
                                                    Text("Crew")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(.blue.opacity(0.15))
                                                        .clipShape(Capsule())
                                                }
                                                if let date = person.lastFlightDate {
                                                    Text(date, style: .date)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        Spacer()
                                        if isCurrentSelection {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    private var filteredPeople: [Person] {
        let needle = searchText.lowercased()
        let people: [Person]

        if needle.isEmpty {
            people = allPeople
        } else {
            people = allPeople.filter {
                $0.firstName.lowercased().contains(needle) ||
                $0.lastName.lowercased().contains(needle)
            }
        }

        return people.sorted { a, b in
            if a.isUsualCrew != b.isUsualCrew { return a.isUsualCrew }
            let aDate = a.lastFlightDate ?? .distantPast
            let bDate = b.lastFlightDate ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.lastName < b.lastName
        }
    }
}

import SwiftUI
import SwiftData

/// Multi-select people picker with search, last-used sorting, and co-traveler group suggestions.
/// Shows crew/passenger toggle for each selected person.
struct PeoplePickerView: View {
    @Binding var selectedCrew: [Person]
    @Binding var selectedPassengers: [Person]
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
                    selectedSection
                    matchingPeopleSection
                    groupSuggestionsSection
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
            .navigationTitle("People")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Selected People

    @ViewBuilder
    private var selectedSection: some View {
        let selected = selectedCrew + selectedPassengers
        if !selected.isEmpty {
            Section("Selected") {
                ForEach(selectedCrew) { person in
                    selectedPersonRow(person: person, role: "Crew") {
                        selectedCrew.removeAll { $0.persistentModelID == person.persistentModelID }
                    } onToggle: {
                        selectedCrew.removeAll { $0.persistentModelID == person.persistentModelID }
                        selectedPassengers.append(person)
                    }
                }
                ForEach(selectedPassengers) { person in
                    selectedPersonRow(person: person, role: "Passenger") {
                        selectedPassengers.removeAll { $0.persistentModelID == person.persistentModelID }
                    } onToggle: {
                        selectedPassengers.removeAll { $0.persistentModelID == person.persistentModelID }
                        selectedCrew.append(person)
                    }
                }
            }
        }
    }

    private func selectedPersonRow(person: Person, role: String, onRemove: @escaping () -> Void, onToggle: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(person.displayName)
                    .font(.body)
                Button(role) {
                    onToggle()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Spacer()
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - People Results

    @ViewBuilder
    private var matchingPeopleSection: some View {
        let people = filteredPeople
        if !people.isEmpty {
            Section("People") {
                ForEach(people) { person in
                    Button {
                        addPerson(person)
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
                            if isSelected(person) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected(person))
                }
            }
        }
    }

    // MARK: - Group Suggestions

    @ViewBuilder
    private var groupSuggestionsSection: some View {
        let groups = coTravelerGroups
        if !groups.isEmpty && searchText.isEmpty {
            Section("Groups") {
                ForEach(groups, id: \.name) { group in
                    Button {
                        for person in group.members {
                            addPerson(person)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(group.name)
                                .font(.subheadline.bold())
                            Text(group.members.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private var selectedIDs: Set<PersistentIdentifier> {
        Set((selectedCrew + selectedPassengers).map(\.persistentModelID))
    }

    private func isSelected(_ person: Person) -> Bool {
        selectedIDs.contains(person.persistentModelID)
    }

    private func addPerson(_ person: Person) {
        guard !isSelected(person) else { return }
        if person.isUsualCrew {
            selectedCrew.append(person)
        } else {
            selectedPassengers.append(person)
        }
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

        // Sort: usual crew first, then by last flight date (most recent first), then by name
        return people.sorted { a, b in
            if a.isUsualCrew != b.isUsualCrew { return a.isUsualCrew }
            let aDate = a.lastFlightDate ?? .distantPast
            let bDate = b.lastFlightDate ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.lastName < b.lastName
        }
    }

    /// Detect co-traveler groups from existing selected crew's flight history.
    private var coTravelerGroups: [PeopleGroup] {
        // Find people who frequently fly together based on the first selected person
        guard let anchor = selectedCrew.first ?? selectedPassengers.first else {
            // If no one selected yet, try to find groups from usual crew
            return usualCrewGroup
        }

        let coTravelers = anchor.coTravelers(minimumFlights: 2)
        guard !coTravelers.isEmpty else { return [] }

        let members = coTravelers.sorted { $0.value > $1.value }.map(\.key)
            .filter { !isSelected($0) }

        guard !members.isEmpty else { return [] }
        return [PeopleGroup(name: "Frequent with \(anchor.displayName)", members: members)]
    }

    private var usualCrewGroup: [PeopleGroup] {
        let crew = allPeople.filter { $0.isUsualCrew && !isSelected($0) }
        guard !crew.isEmpty else { return [] }
        return [PeopleGroup(name: "Usual Crew", members: crew)]
    }
}

private struct PeopleGroup: Hashable {
    let name: String
    let members: [Person]

    static func == (lhs: PeopleGroup, rhs: PeopleGroup) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

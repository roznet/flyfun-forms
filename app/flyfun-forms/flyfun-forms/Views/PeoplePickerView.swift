import SwiftUI
import SwiftData

/// Multi-select people picker with search, last-used sorting, and co-traveler group suggestions.
/// Shows crew/passenger toggle for each selected person. Someone not in the
/// app yet can be added from here (blank, scanned or from a contact) and goes
/// straight into the selection.
struct PeoplePickerView: View {
    @Binding var selectedCrew: [Person]
    @Binding var selectedPassengers: [Person]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.lastName) private var allPeople: [Person]

    @State private var searchText = ""
    @State private var addRequest: AddPersonMethod?
    /// The person open in the editor pushed over the picker.
    @State private var editingPerson: Person?
    /// A person this picker created empty: taken away again if the editor
    /// closes with nothing entered.
    @State private var createdPersonID: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search people...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("peopleSearchField")
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif

                List {
                    selectedSection
                    matchingPeopleSection
                    addSearchedPersonSection
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
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        AddPersonMenuItems(request: $addRequest, addPersonIdentifier: "pickerAddPersonButton")
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("pickerAddPersonMenu")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .addPersonFlows(request: $addRequest) { person, method in
                addNewPerson(person, method: method)
            }
            .navigationDestination(item: $editingPerson) { person in
                PersonEditView(person: person)
            }
            .onChange(of: editingPerson) { left, _ in
                discardIfBlank(left)
            }
        }
        // On the stack, not its root: the root also disappears when the editor
        // is pushed over it, while the person is still empty.
        .onDisappear {
            // Swiped away with the editor still open.
            discardIfBlank(editingPerson)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
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
                .accessibilityIdentifier("selectedRole-\(person.lastName)")
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

    // MARK: - Add Searched Person

    /// The search found nobody: offer to create them under the name typed.
    @ViewBuilder
    private var addSearchedPersonSection: some View {
        let name = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && filteredPeople.isEmpty {
            Section {
                Button {
                    let person = Person()
                    (person.firstName, person.lastName) = Self.splitName(name)
                    modelContext.insert(person)
                    addNewPerson(person, method: .blank)
                } label: {
                    Label("Add “\(name)” as new person", systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("addSearchedPersonButton")
            }
        }
    }

    /// "Smith" is a last name; "Jane van Dijk" is Jane + van Dijk.
    static func splitName(_ name: String) -> (first: String, last: String) {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return ("", name) }
        return (String(words[0]), words.dropFirst().joined(separator: " "))
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

    /// Select a person the add flows ended with. A scan has already filled in
    /// the name and document; a blank or contact person still needs them, so
    /// the editor opens over the picker.
    private func addNewPerson(_ person: Person, method: AddPersonMethod) {
        addPerson(person)
        searchText = ""
        switch method {
        case .blank:
            createdPersonID = person.persistentModelID
            editingPerson = person
        case .contact:
            editingPerson = person
        case .scan:
            break
        }
    }

    private func discardIfBlank(_ person: Person?) {
        guard let person, person.persistentModelID == createdPersonID else { return }
        createdPersonID = nil
        Self.discardIfBlank(person, crew: &selectedCrew, passengers: &selectedPassengers, in: modelContext)
    }

    /// Take a person this picker created off the selection and out of the
    /// store if nothing was entered for them. Only for a person the picker
    /// created: one picked through a scan match or contact merge was already
    /// there, and stays whatever it holds.
    @discardableResult
    static func discardIfBlank(
        _ person: Person, crew: inout [Person], passengers: inout [Person], in context: ModelContext
    ) -> Bool {
        guard person.isBlank else { return false }
        let id = person.persistentModelID
        crew.removeAll { $0.persistentModelID == id }
        passengers.removeAll { $0.persistentModelID == id }
        context.delete(person)
        return true
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
        return [PeopleGroup(name: String(localized: "Frequent with \(anchor.displayName)"), members: members)]
    }

    private var usualCrewGroup: [PeopleGroup] {
        let crew = allPeople.filter { $0.isUsualCrew && !isSelected($0) }
        guard !crew.isEmpty else { return [] }
        return [PeopleGroup(name: String(localized: "Usual Crew"), members: crew)]
    }
}

private struct PeopleGroup: Hashable {
    let name: String
    let members: [Person]

    static func == (lhs: PeopleGroup, rhs: PeopleGroup) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

import SwiftUI
import SwiftData
import Contacts
import ContactsUI

// MARK: - Resolve View (shown after contact is picked)

/// Shows the imported contact details and offers to create a new person
/// or merge into an existing fuzzy match.
struct ContactResolveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.lastName) private var allPeople: [Person]

    let contact: ImportedContact
    var onPersonSelected: ((Person) -> Void)?

    @State private var selectedPhone: String
    @State private var selectedEmail: String
    @State private var selectedAddress: String
    @State private var overrideExisting = false
    @State private var matches: [Person] = []

    init(contact: ImportedContact, onPersonSelected: ((Person) -> Void)? = nil) {
        self.contact = contact
        self.onPersonSelected = onPersonSelected
        _selectedPhone = State(initialValue: contact.phones.first ?? "")
        _selectedEmail = State(initialValue: contact.emails.first ?? "")
        _selectedAddress = State(initialValue: contact.addresses.first ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                contactSection
                createSection
                if !matches.isEmpty {
                    mergeSection
                }
            }
            .navigationTitle("Import Contact")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                matches = findMatches()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var contactSection: some View {
        Section("Contact") {
            LabeledContent("Name", value: "\(contact.firstName) \(contact.lastName)")
            if contact.phones.count > 1 {
                Picker("Phone", selection: $selectedPhone) {
                    ForEach(contact.phones, id: \.self) { Text($0).tag($0) }
                }
            } else if let phone = contact.phone {
                LabeledContent("Phone", value: phone)
            }
            if contact.emails.count > 1 {
                Picker("Email", selection: $selectedEmail) {
                    ForEach(contact.emails, id: \.self) { Text($0).tag($0) }
                }
            } else if let email = contact.email {
                LabeledContent("Email", value: email)
            }
            if let dob = contact.dateOfBirth {
                LabeledContent("Date of Birth", value: dob, format: .dateTime.day().month().year())
            }
            if contact.addresses.count > 1 {
                Picker("Address", selection: $selectedAddress) {
                    ForEach(contact.addresses, id: \.self) { Text($0).tag($0) }
                }
            } else if let address = contact.address {
                LabeledContent("Address", value: address)
            }
        }
    }

    @ViewBuilder
    private var createSection: some View {
        Section {
            Button {
                let person = createNewPerson()
                onPersonSelected?(person)
                dismiss()
            } label: {
                Label("Create as New Person", systemImage: "person.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var mergeSection: some View {
        Section("Update Existing") {
            Picker("Import Mode", selection: $overrideExisting) {
                Text("Fill Missing Only").tag(false)
                Text("Override All").tag(true)
            }
            .pickerStyle(.segmented)

            ForEach(matches) { person in
                Button {
                    updatePerson(person)
                    onPersonSelected?(person)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(person.displayName)
                            existingDetails(for: person)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func existingDetails(for person: Person) -> some View {
        let parts = [person.nationality, person.phone, person.email].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Matching

    private func findMatches() -> [Person] {
        let firstName = contact.firstName.lowercased()
        let lastName = contact.lastName.lowercased()
        guard !firstName.isEmpty || !lastName.isEmpty else { return [] }

        return allPeople.filter { person in
            let pFirst = person.firstName.lowercased()
            let pLast = person.lastName.lowercased()

            if pLast == lastName && (pFirst == firstName ||
                pFirst.hasPrefix(String(firstName.prefix(3))) ||
                firstName.hasPrefix(String(pFirst.prefix(3)))) {
                return true
            }
            if !lastName.isEmpty && !pLast.isEmpty &&
               levenshtein(pLast, lastName) <= 2 && levenshtein(pFirst, firstName) <= 2 {
                return true
            }
            return false
        }
        .sorted { a, b in
            let aExact = a.lastName.lowercased() == lastName && a.firstName.lowercased() == firstName
            let bExact = b.lastName.lowercased() == lastName && b.firstName.lowercased() == firstName
            if aExact != bExact { return aExact }
            return a.lastName < b.lastName
        }
    }

    private func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1), b = Array(s2)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                dist[i][j] = min(dist[i-1][j] + 1, dist[i][j-1] + 1, dist[i-1][j-1] + cost)
            }
        }
        return dist[a.count][b.count]
    }

    // MARK: - Create / Update

    private func createNewPerson() -> Person {
        let person = Person(firstName: contact.firstName, lastName: contact.lastName)
        person.phone = selectedPhone.isEmpty ? nil : selectedPhone
        person.email = selectedEmail.isEmpty ? nil : selectedEmail
        person.address = selectedAddress.isEmpty ? nil : selectedAddress
        person.dateOfBirth = contact.dateOfBirth
        modelContext.insert(person)
        return person
    }

    private func updatePerson(_ person: Person) {
        if overrideExisting {
            person.firstName = contact.firstName
            person.lastName = contact.lastName
            if !selectedPhone.isEmpty { person.phone = selectedPhone }
            if !selectedEmail.isEmpty { person.email = selectedEmail }
            if !selectedAddress.isEmpty { person.address = selectedAddress }
            if let dob = contact.dateOfBirth { person.dateOfBirth = dob }
        } else {
            if person.phone == nil || person.phone?.isEmpty == true, !selectedPhone.isEmpty {
                person.phone = selectedPhone
            }
            if person.email == nil || person.email?.isEmpty == true, !selectedEmail.isEmpty {
                person.email = selectedEmail
            }
            if person.address == nil || person.address?.isEmpty == true, !selectedAddress.isEmpty {
                person.address = selectedAddress
            }
            if person.dateOfBirth == nil { person.dateOfBirth = contact.dateOfBirth }
        }
    }
}

// MARK: - Imported Contact Model

struct ImportedContact: Identifiable {
    let id = UUID()
    let firstName: String
    let lastName: String
    let phones: [String]
    let emails: [String]
    let dateOfBirth: Date?
    let addresses: [String]

    var phone: String? { phones.first }
    var email: String? { emails.first }
    var address: String? { addresses.first }

    init(from contact: CNContact) {
        self.firstName = contact.givenName
        self.lastName = contact.familyName
        self.phones = contact.phoneNumbers.map(\.value.stringValue)
        self.emails = contact.emailAddresses.map { $0.value as String }
        self.dateOfBirth = contact.birthday.flatMap { Calendar.current.date(from: $0) }
        self.addresses = contact.postalAddresses.compactMap { labeled in
            let postal = labeled.value
            let parts = [postal.street, postal.city, postal.postalCode, postal.country]
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }
}

// MARK: - Contact Picker Helper

/// Fetches a full CNContact with all needed keys from an identifier.
private let contactFetchKeys: [CNKeyDescriptor] = [
    CNContactGivenNameKey as CNKeyDescriptor,
    CNContactFamilyNameKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactBirthdayKey as CNKeyDescriptor,
    CNContactPostalAddressesKey as CNKeyDescriptor,
]

func fetchFullContact(identifier: String) -> CNContact? {
    try? CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: contactFetchKeys)
}

// MARK: - iOS Contact Picker

#if os(iOS)
struct ContactPickerSheet: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        init(onSelect: @escaping (CNContact) -> Void) { self.onSelect = onSelect }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            if let full = fetchFullContact(identifier: contact.identifier) {
                onSelect(full)
            } else {
                onSelect(contact)
            }
        }
    }
}
#else
// MARK: - macOS Contact Search

struct ContactSearchView: View {
    let onSelect: (CNContact) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [CNContact] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search contacts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onChange(of: searchText) { searchContacts() }

                List(results, id: \.identifier) { contact in
                    Button {
                        onSelect(contact)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(contact.givenName) \(contact.familyName)")
                            if let phone = contact.phoneNumbers.first?.value.stringValue {
                                Text(phone).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Choose Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .onAppear { searchContacts() }
    }

    private func searchContacts() {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: contactFetchKeys)
        if !searchText.isEmpty {
            request.predicate = CNContact.predicateForContacts(matchingName: searchText)
        }
        var contacts: [CNContact] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }
        results = contacts.sorted { "\($0.familyName) \($0.givenName)" < "\($1.familyName) \($1.givenName)" }
    }
}
#endif

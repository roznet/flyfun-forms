import SwiftUI

/// A reusable autocomplete component that shows a search field and sectioned results.
/// Generic over the item type. Supports single-select and multi-select modes.
struct AutocompletePickerView<Item: Identifiable & Hashable, RowContent: View>: View {
    let placeholder: String
    @Binding var searchText: String
    let sections: [AutocompleteSection<Item>]
    let selection: AutocompleteSelection<Item>
    @ViewBuilder let rowContent: (Item) -> RowContent

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            List {
                // Selected items (multi-select only)
                if case .multi(let items, let onRemove) = selection, !items.isEmpty {
                    Section("Selected") {
                        ForEach(items) { item in
                            HStack {
                                rowContent(item)
                                Spacer()
                                Button {
                                    onRemove(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Result sections
                ForEach(sections) { section in
                    if !section.items.isEmpty {
                        Section(section.title) {
                            ForEach(section.items) { item in
                                Button {
                                    handleTap(item)
                                } label: {
                                    HStack {
                                        rowContent(item)
                                        Spacer()
                                        if isSelected(item) {
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
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
    }

    private func handleTap(_ item: Item) {
        switch selection {
        case .single(_, let onSelect):
            onSelect(item)
        case .multi(let items, let onRemove):
            if items.contains(where: { $0.id == item.id }) {
                onRemove(item)
            } else {
                // For multi, onRemove doubles as toggle — caller handles add via onSelect in section
                // Actually we need an onAdd callback
                break
            }
        case .multiWithAdd(let items, let onAdd, let onRemove):
            if items.contains(where: { $0.id == item.id }) {
                onRemove(item)
            } else {
                onAdd(item)
            }
        }
    }

    private func isSelected(_ item: Item) -> Bool {
        switch selection {
        case .single(let selected, _):
            return selected?.id == item.id
        case .multi(let items, _):
            return items.contains(where: { $0.id == item.id })
        case .multiWithAdd(let items, _, _):
            return items.contains(where: { $0.id == item.id })
        }
    }
}

struct AutocompleteSection<Item: Identifiable & Hashable>: Identifiable {
    let id: String
    let title: String
    let items: [Item]

    init(_ title: String, items: [Item]) {
        self.id = title
        self.title = title
        self.items = items
    }
}

enum AutocompleteSelection<Item: Identifiable & Hashable> {
    case single(selected: Item?, onSelect: (Item) -> Void)
    case multi(selected: [Item], onRemove: (Item) -> Void)
    case multiWithAdd(selected: [Item], onAdd: (Item) -> Void, onRemove: (Item) -> Void)
}

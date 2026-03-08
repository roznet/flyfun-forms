import SwiftUI
import SwiftData

struct AircraftListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Aircraft.registration) private var aircraft: [Aircraft]

    var body: some View {
        List {
            ForEach(aircraft) { ac in
                NavigationLink(value: ac) {
                    VStack(alignment: .leading) {
                        Text(ac.displayName)
                            .font(.headline)
                        if !ac.type.isEmpty {
                            Text(ac.type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete(perform: deleteAircraft)
        }
        .navigationTitle("Aircraft")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let ac = Aircraft()
                    modelContext.insert(ac)
                } label: {
                    Label("Add Aircraft", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Aircraft.self) { ac in
            AircraftEditView(aircraft: ac)
        }
    }

    private func deleteAircraft(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(aircraft[index])
        }
    }
}

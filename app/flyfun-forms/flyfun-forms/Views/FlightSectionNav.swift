import SwiftUI

/// One entry in the flight-edit section selector.
struct FlightSection: Identifiable, Equatable {
    let id: String
    let title: String

    init(_ id: String, _ title: String) {
        self.id = id
        self.title = title
    }
}

/// Horizontally-scrollable pill bar that picks which section of a long `Form`
/// is on screen. Compact width only — the wide layout already splits the flight
/// across two columns.
///
/// This is the flyfun-weather briefing rail's *focus mode*, not its scroll-spy.
/// The scroll-spy could not come across: it rests on `.scrollTargetLayout()`,
/// `ScrollPosition` and `onScrollTargetVisibilityChange`, which only exist for
/// `ScrollView`, and the flight editor is a `List`-backed `Form`. Working
/// around that meant injecting anchor rows (a `List` row cannot be zero-height,
/// so each one drew a stray separator), measuring geometry inside row hosts
/// (a `.named(_:)` space declared on the `Form` does not resolve there) and
/// `scrollTo` calls that never landed.
///
/// Selecting instead of scrolling removes the whole class of problem: the pill
/// *is* the state, so there is nothing to keep in sync and nothing to measure.
struct FlightSectionNavBar: View {
    /// Shows every section, and the default.
    static let allSectionID = "all"

    /// Section pills, in document order. "All" is not among them — it is
    /// pinned, see below.
    let sections: [FlightSection]
    let selected: String
    let onSelect: (String) -> Void

    /// Keeps the chosen pill in view when the selection changes from elsewhere.
    @State private var pillPosition = ScrollPosition(idType: String.self)

    var body: some View {
        HStack(spacing: 8) {
            // "All" sits OUTSIDE the scroller. Focusing a section late in the
            // list used to scroll the bar with it, leaving the way back several
            // swipes to the left; pinned, it is always one tap away.
            pill(FlightSection(Self.allSectionID, String(localized: "All")))

            Divider().frame(height: 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sections) { section in
                        pill(section)
                    }
                }
                .padding(.trailing, 16)
                .scrollTargetLayout()
            }
            .scrollPosition($pillPosition)
            .onChange(of: selected) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    pillPosition.scrollTo(id: newValue, anchor: .center)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 0.5)
        }
        .accessibilityIdentifier("flightSectionNavBar")
    }

    @ViewBuilder
    private func pill(_ section: FlightSection) -> some View {
        let isSelected = section.id == selected
        Button { onSelect(section.id) } label: {
            Text(section.title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: isSelected ? 0 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .id(section.id)
        .accessibilityIdentifier("flightSectionPill_\(section.id)")
    }
}

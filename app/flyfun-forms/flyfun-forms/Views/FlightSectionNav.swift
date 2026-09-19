import SwiftUI

/// One jump target in the flight-edit section navigator.
struct FlightSection: Identifiable, Equatable {
    let id: String
    let title: String

    init(_ id: String, _ title: String) {
        self.id = id
        self.title = title
    }
}

/// Horizontally-scrollable pill bar that jumps between the sections of a long
/// `Form`, mirroring the flyfun-weather briefing's scroll-spy rail: it
/// highlights whichever section is nearest the top and scrolls to one on tap.
///
/// Compact width only. The wide layout already splits the flight across two
/// columns, so it has nothing to jump between.
struct FlightSectionNavBar: View {
    let sections: [FlightSection]
    let active: String?
    let onTap: (String) -> Void

    /// Keeps the active pill in view as the content scrolls under it.
    @State private var pillPosition = ScrollPosition(idType: String.self)

    /// Pill ids are namespaced. The bar sits inside the same `ScrollViewReader`
    /// as the `Form` it drives, so a bare `section.id` here would collide with
    /// the section anchor and `scrollTo` could scroll the pill strip instead of
    /// the form.
    private func pillID(_ id: String) -> String { "pill-\(id)" }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { section in
                    pill(section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .scrollTargetLayout()
        }
        .scrollPosition($pillPosition)
        .onChange(of: active) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                pillPosition.scrollTo(id: pillID(newValue), anchor: .center)
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 0.5)
        }
        .accessibilityIdentifier("flightSectionNavBar")
    }

    @ViewBuilder
    private func pill(_ section: FlightSection) -> some View {
        let isActive = section.id == active
        Button { onTap(section.id) } label: {
            Text(section.title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isActive ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: isActive ? 0 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .id(pillID(section.id))
        .accessibilityIdentifier("flightSectionPill_\(section.id)")
    }
}

extension View {
    /// Marks a `Form` section header as a jump target for `FlightSectionNavBar`.
    ///
    /// `.id` is what `ScrollViewProxy.scrollTo` addresses — it works for rows a
    /// lazy `List` has not materialised yet, which is the whole point. The
    /// visibility report is what keeps the active pill honest;
    /// `onScrollVisibilityChange` is a *per-view* modifier, so unlike the
    /// scroll-container-scoped `onScrollTargetVisibilityChange` that
    /// flyfun-weather's `ScrollSpyScroll` uses, it also fires inside a
    /// `List`-backed `Form`.
    ///
    /// Anchoring on the header (rather than the first row) means a jump lands
    /// with the section title at the top, so you can see where you arrived.
    ///
    /// `tracking` is false in layouts that show no nav bar: the `.id` still
    /// applies unconditionally, because dropping it would change the row's
    /// SwiftUI identity between size classes.
    func flightSectionAnchor(
        _ id: String,
        visible: Binding<Set<String>>,
        tracking: Bool = true
    ) -> some View {
        self.id(id)
            .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                guard tracking else { return }
                if isVisible {
                    visible.wrappedValue.insert(id)
                } else {
                    visible.wrappedValue.remove(id)
                }
            }
    }
}

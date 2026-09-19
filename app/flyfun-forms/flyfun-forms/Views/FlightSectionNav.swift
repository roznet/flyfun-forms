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

/// Tracks which flight section is at the top of the screen.
///
/// Each section's anchor row reports where its top edge sits on screen, and the
/// active section is the deepest anchor that has reached the top of the form.
/// Positions rather than visibility events, so `switchToFlight` swapping the
/// flight under the same view has nothing to reset, and so scrolling inside a
/// section taller than the screen keeps the highlight on that section instead
/// of jumping ahead to the next header creeping in from the bottom.
///
/// Only `active` is observable. Positions churn on every scroll frame and must
/// not re-evaluate the enclosing view.
@Observable
final class FlightSectionSpy {
    /// How far below the form's top edge an anchor may sit and still count as
    /// the current section. Roughly one section-header height, so the pill
    /// flips as the heading arrives at the top rather than after it has gone.
    private static let passedThreshold: CGFloat = 40

    private(set) var active: String?

    /// Each anchor's top edge in screen space, paired with the scroll offset it
    /// was measured at.
    ///
    /// Screen space, not a named ancestor space: `List` hosts its rows in
    /// separate contexts, and a `.named(_:)` space declared on the `Form` does
    /// not resolve from inside them — every row then reports the same number
    /// and the "deepest" anchor becomes whichever one the dictionary happens to
    /// yield.
    ///
    /// The paired offset is what makes this robust to a row's geometry callback
    /// not re-firing while the list scrolls: scrolling translates rows 1:1 with
    /// the content offset, so a measurement taken at a known offset stays exact
    /// once corrected by how far we have scrolled since. The scroll offset
    /// itself comes from a modifier on the scroll container, which does report
    /// continuously.
    @ObservationIgnored private var tops: [String: (top: CGFloat, offset: CGFloat)] = [:]
    @ObservationIgnored private var formTop: CGFloat = 0
    @ObservationIgnored private var scrollOffset: CGFloat = 0

    func reportFormTop(_ y: CGFloat) {
        formTop = y
        recompute()
    }

    func reportScrollOffset(_ y: CGFloat) {
        scrollOffset = y
        recompute()
    }

    /// `top == nil` drops an anchor the lazy `List` has recycled.
    func report(_ id: String, top: CGFloat?) {
        if let top {
            tops[id] = (top: top, offset: scrollOffset)
        } else {
            tops.removeValue(forKey: id)
        }
        recompute()
    }

    /// Where an anchor sits now, correcting its measurement for scrolling since.
    private func currentTop(_ entry: (top: CGFloat, offset: CGFloat)) -> CGFloat {
        entry.top - (scrollOffset - entry.offset)
    }

    private func recompute() {
        let passed = tops.filter { currentTop($0.value) - formTop <= Self.passedThreshold }
        // Closest to the top edge from above wins. When nothing qualifies — we
        // are above the first anchor, or deep inside a long section whose
        // anchor has been recycled — the previous answer still holds.
        guard let deepest = passed.max(by: { currentTop($0.value) < currentTop($1.value) })?.key
        else { return }
        if deepest != active { active = deepest }
    }
}

/// Marks where a section begins, as a zero-height row at the top of it.
///
/// It has to be a row. In a `List`, section headers are not addressable by
/// `ScrollViewProxy.scrollTo` and do not take part in row geometry, so
/// anchoring on them leaves taps dead and the highlight stuck — which is
/// exactly what the first cut of this did.
///
/// `tracking` is false in layouts with no nav bar. The `.id` still applies
/// unconditionally: dropping it would change the row's identity by size class.
struct FlightSectionAnchor: View {
    let id: String
    let spy: FlightSectionSpy
    var tracking: Bool = true

    var body: some View {
        Color.clear
            .frame(height: 0)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
            .id(id)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                guard tracking else { return }
                spy.report(id, top: top)
            }
            .onDisappear {
                guard tracking else { return }
                spy.report(id, top: nil)
            }
    }
}

/// Horizontally-scrollable pill bar that jumps between the sections of a long
/// `Form`, mirroring the flyfun-weather briefing's scroll-spy rail: it
/// highlights whichever section is at the top and scrolls to one on tap.
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

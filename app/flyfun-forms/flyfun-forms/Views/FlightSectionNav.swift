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

/// Tracks which flight section the user is looking at.
///
/// Every section header reports its offset from the top of the `Form` whenever
/// its frame moves, and the active section is the deepest header that has
/// reached the top edge. This is *position* truth rather than *event* truth,
/// which matters twice:
///
/// - `switchToFlight` swaps the flight under the same `FlightEditView`
///   instance, so a set of "these ids were seen" would carry over from the old
///   flight with no event to correct it. Offsets carry over too, but they stay
///   correct, because they describe where the headers actually are.
/// - While scrolling inside a section taller than the screen, no header is on
///   screen at all. A "topmost visible header" rule would jump the highlight to
///   the *next* section as its header crept in from the bottom; holding the
///   last header that passed the top keeps it on the section being read.
///
/// Only `active` is observable. The offsets churn on every scroll frame and
/// must not re-evaluate the enclosing view.
@Observable
final class FlightSectionSpy {
    /// Coordinate space the offsets are measured in — the `Form` itself, so 0
    /// is its top edge and a header scrolled past it reads negative.
    static let coordinateSpace = "flightSections"

    /// A header counts as passed once its top is within this many points of the
    /// form's top edge, so the pill flips as the title arrives rather than only
    /// after it has scrolled away.
    private static let passedThreshold: CGFloat = 24

    private(set) var active: String?

    @ObservationIgnored private var offsets: [String: CGFloat] = [:]

    /// `offset == nil` drops a header the lazy `List` has recycled.
    func report(_ id: String, offset: CGFloat?) {
        if let offset {
            offsets[id] = offset
        } else {
            offsets.removeValue(forKey: id)
        }

        // Closest to the top edge from above wins. When nothing qualifies — we
        // are above the first header, or deep inside a long section whose
        // header has been recycled — the previous answer still holds.
        let passed = offsets.filter { $0.value <= Self.passedThreshold }
        guard let deepest = passed.max(by: { $0.value < $1.value })?.key else { return }
        if deepest != active { active = deepest }
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
    /// lazy `List` has not materialised yet, which is the whole point.
    /// Anchoring on the header (rather than the first row) means a jump lands
    /// with the section title at the top, so you can see where you arrived.
    ///
    /// The geometry report is what keeps the active pill honest. It is measured
    /// against the `Form`'s own named coordinate space rather than
    /// `.scrollView`, so it does not depend on that space resolving inside a
    /// `List`, and `onDisappear` drops headers the `List` recycles.
    ///
    /// `tracking` is false in layouts that show no nav bar: the `.id` still
    /// applies unconditionally, because dropping it would change the row's
    /// SwiftUI identity between size classes.
    func flightSectionAnchor(
        _ id: String,
        spy: FlightSectionSpy,
        tracking: Bool = true
    ) -> some View {
        self.id(id)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(FlightSectionSpy.coordinateSpace)).minY
            } action: { offset in
                guard tracking else { return }
                spy.report(id, offset: offset)
            }
            .onDisappear {
                guard tracking else { return }
                spy.report(id, offset: nil)
            }
    }
}

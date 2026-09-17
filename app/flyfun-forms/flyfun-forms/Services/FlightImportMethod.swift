import Foundation
import RZFlight
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A way of starting a new flight from something that already exists.
///
/// Methods are data rather than branches: the import control renders the list
/// from `allCases` and each case resolves to either an immediate draft or a
/// picker sheet, so adding a method is a case plus a sheet and touches neither
/// the form nor the control.
enum FlightImportMethod: String, CaseIterable, Identifiable, Hashable {
    case previousFlight
    case clipboardFPL
    case weather
    case autorouter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousFlight: return String(localized: "Previous Flight")
        case .clipboardFPL:   return String(localized: "Flight Plan")
        case .weather:        return String(localized: "FlyFun Weather")
        case .autorouter:     return String(localized: "Autorouter")
        }
    }

    var systemImage: String {
        switch self {
        case .previousFlight: return "clock.arrow.circlepath"
        case .clipboardFPL:   return "doc.on.clipboard"
        case .weather:        return "cloud.sun"
        case .autorouter:     return "arrow.down.doc"
        }
    }

    /// The one-line explanation shown under a method in the full list.
    var subtitle: String {
        switch self {
        case .previousFlight:
            return String(localized: "Repeat a flight with the same crew, rescheduled")
        case .clipboardFPL:
            return String(localized: "Paste an ICAO flight plan you copied")
        case .weather:
            return String(localized: "A flight you planned in FlyFun Weather")
        case .autorouter:
            return String(localized: "A route from your Autorouter history")
        }
    }
}

// MARK: - Availability

extension FlightImportMethod {

    enum Availability: Equatable {
        case available
        /// Offered but greyed, with the reason shown, so the method stays
        /// discoverable before the pilot has what it needs.
        case unavailable(reason: String)

        var isAvailable: Bool { self == .available }
    }

    func availability(in context: FlightImportContext) -> Availability {
        switch self {
        case .previousFlight:
            return context.hasPastFlights
                ? .available
                : .unavailable(reason: String(localized: "No earlier flights yet"))
        case .clipboardFPL:
            return context.clipboardHasText
                ? .available
                : .unavailable(reason: String(localized: "Nothing on the clipboard"))
        case .weather:
            return context.isSignedIn
                ? .available
                : .unavailable(reason: String(localized: "Sign in to import"))
        case .autorouter:
            guard context.isSignedIn else {
                return .unavailable(reason: String(localized: "Sign in to import"))
            }
            // Signing in is not enough: the pilot also has to have linked their
            // Autorouter account. Saying so here is the whole point of listing
            // an unavailable method — otherwise they tap, wait on a spinner,
            // and get the same answer as a 409.
            if context.autorouterLinked == false {
                return .unavailable(
                    reason: String(localized: "Link your Autorouter account in FlyFun Weather")
                )
            }
            return .available
        }
    }
}

// MARK: - Context

/// A snapshot of what the app can offer right now. Rebuilt when the import
/// control appears, which is also when the (cheap, non-prompting) clipboard
/// check happens.
struct FlightImportContext: Equatable {
    var hasPastFlights: Bool = false
    var clipboardHasText: Bool = false
    var isSignedIn: Bool = false

    /// Whether the account has a usable Autorouter token, or nil while the
    /// check is still in flight. Unknown counts as available: a pending fetch
    /// must never hide a method that works, and the picker's own 409 still
    /// explains it if the answer turns out to be no.
    var autorouterLinked: Bool?

    /// The route of the most recent flight, used to label the primary button
    /// when "Previous Flight" is the ranked method.
    var mostRecentRoute: String?

    /// Whether the pasteboard holds any string at all.
    ///
    /// `hasStrings` is deliberate: reading `UIPasteboard.general.string`
    /// raises the system "Allow Paste?" alert, so the *suggestion* is gated on
    /// this non-prompting check and the contents are read only once the pilot
    /// picks the method.
    @MainActor
    static var pasteboardHasText: Bool {
        #if os(iOS)
        return UIPasteboard.general.hasStrings
        #else
        return NSPasteboard.general.string(forType: .string)?.isEmpty == false
        #endif
    }
}

// MARK: - Ranking

extension FlightImportMethod {

    /// The method this context makes likeliest, which the list leads with.
    ///
    /// Ranked by context rather than by what was used last: a clipboard flight
    /// plan is only useful when there is one on the clipboard, and a repeat
    /// trip is overwhelmingly a previous flight. A sticky last-used order would
    /// also move the rows under the pilot and has nothing to go on for a fresh
    /// install.
    static func ranked(for context: FlightImportContext) -> FlightImportMethod {
        rankedOrder(for: context).first ?? .clipboardFPL
    }

    /// Every method, likeliest first, with the unusable ones last.
    ///
    /// The list shows all four whatever the context — an unavailable method
    /// says why rather than disappearing — so ranking only decides the order,
    /// where being wrong costs a glance rather than a wrong flight.
    static func rankedOrder(for context: FlightImportContext) -> [FlightImportMethod] {
        let order: [FlightImportMethod] = [.clipboardFPL, .previousFlight, .weather, .autorouter]
        let available = order.filter { $0.availability(in: context).isAvailable }
        return available + order.filter { !available.contains($0) }
    }
}

// MARK: - Clipboard

enum ClipboardFlightPlan {

    enum ImportError: LocalizedError {
        case empty
        case unparseable

        var errorDescription: String? {
            switch self {
            case .empty:
                return String(localized: "There is nothing on the clipboard to import.")
            case .unparseable:
                return String(localized: "The clipboard doesn't look like an ICAO flight plan. Copy the whole plan, starting with (FPL-.")
            }
        }
    }

    /// Read the pasteboard and parse it as an ICAO flight plan.
    ///
    /// Parsing is `RZFlight.ICAOFlightPlanParser`; forms carried a second copy
    /// of this for a while and it was the weaker one, so do not reimplement it
    /// locally. Failures are thrown rather than swallowed: the original silent
    /// `guard … else { return }` made a bad paste look like a dead button.
    @MainActor
    static func read() throws -> ICAOFlightPlan {
        #if os(iOS)
        let text = UIPasteboard.general.string
        #else
        let text = NSPasteboard.general.string(forType: .string)
        #endif
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.empty
        }
        guard let plan = ICAOFlightPlanText.parse(text) else {
            throw ImportError.unparseable
        }
        return plan
    }
}

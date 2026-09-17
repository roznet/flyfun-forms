import Foundation
import RZFlight

/// One way into `RZFlight.ICAOFlightPlanParser` for every FPL forms reads.
///
/// Autorouter — and some other tools — emit plans with a space before each
/// field separator (`…-EGTF0730 -N0164F100 …`). The parser splits on the
/// separator and then decides where field 13 starts from how many fields it
/// found, so the extra spaces shift every field by one slot: `EGTF` becomes
/// `N016`, the destination becomes `DOF/`, and the date and time come back nil.
/// The import looked like it worked and quietly filled the form with the wrong
/// route and the wrong departure time.
///
/// Collapsing `" -"` to `"-"` restores the canonical form. It is idempotent on
/// a plan that was already canonical, so both import paths can go through here
/// rather than each deciding whether its source needs it.
///
/// flyfun-weather does the same normalisation server-side in `/parse-fpl`; the
/// comment there records the same find.
enum ICAOFlightPlanText {

    /// Parse an ICAO FPL, tolerating spaces before the field separators.
    static func parse(_ text: String) -> ICAOFlightPlan? {
        ICAOFlightPlanParser.parse(normalisingSeparators(text))
    }

    /// `" -"` → `"-"`, leaving a canonical plan untouched.
    static func normalisingSeparators(_ text: String) -> String {
        text.replacingOccurrences(of: " +-", with: "-", options: .regularExpression)
    }
}

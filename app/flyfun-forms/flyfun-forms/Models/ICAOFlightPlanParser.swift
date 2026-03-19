import Foundation

/// Parses ICAO FPL format strings into structured flight plan data.
///
/// Expected format (fields separated by dashes within parentheses):
/// ```
/// (FPL-N122DR-VG
/// -S22T/L-SBDGORVY/LB2
/// -LFAT0930
/// -N0166VFR DCT ...
/// -EGTF0033
/// -PBN/... DOF/260318 EET/...)
/// ```
struct ICAOFlightPlanParser {
    struct Result {
        var aircraftRegistration: String?
        var aircraftType: String?
        var flightRules: String?   // V=VFR, I=IFR, Y/Z=mixed
        var flightType: String?    // G=general, S=scheduled, etc.
        var originICAO: String?
        var destinationICAO: String?
        var departureTimeUTC: String?  // HH:mm
        var eet: String?               // HH:mm (estimated elapsed time)
        var dateOfFlight: Date?
        var speed: String?
        var route: String?
    }

    static func parse(_ text: String) -> Result? {
        // Normalize: collapse whitespace/newlines, find the FPL block
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Extract content between outer parentheses starting with FPL
        guard let fplRange = normalized.range(of: #"\(FPL[^)]*\)"#, options: .regularExpression) else {
            return nil
        }
        var fplBody = String(normalized[fplRange])
        // Strip outer parens
        fplBody.removeFirst() // (
        fplBody.removeLast()  // )

        // Collapse newlines into spaces for easier splitting
        fplBody = fplBody.replacingOccurrences(of: "\n", with: " ")

        // Split on dash-delimited fields. ICAO FPL uses "-" as field separator,
        // but dashes also appear in the FPL prefix. The canonical fields after "FPL" are:
        //   FPL - field7 - field8 - field9 - field10 - field13 - field15 - field16 - field18
        // We split on " -" or starting "-" patterns, but the simplest approach is to
        // split on "-" and recombine intelligently.
        let fields = splitFields(fplBody)
        guard fields.count >= 6 else { return nil }

        var result = Result()

        // Field 7: Aircraft identification and flight rules/type
        // e.g. "N122DR" from first part, "VG" from second part
        parseField7(fields[0], into: &result)

        // Field 8: Flight rules and type of flight (e.g. "VG")
        parseField8(fields[1], into: &result)

        // Field 9: Aircraft type/wake and equipment
        // e.g. "S22T/L" and "SBDGORVY/LB2"
        parseField9(fields[2], equipmentField: fields.count > 3 ? fields[3] : nil, into: &result)

        // Field 13: Departure aerodrome and time
        // e.g. "LFAT0930"
        let field13Index = fields.count > 7 ? 4 : 3
        parseField13(fields[field13Index], into: &result)

        // Field 15: Route (speed, level, route)
        let field15Index = field13Index + 1
        if field15Index < fields.count {
            parseField15(fields[field15Index], into: &result)
        }

        // Field 16: Destination and EET
        let field16Index = field15Index + 1
        if field16Index < fields.count {
            parseField16(fields[field16Index], into: &result)
        }

        // Field 18: Other information (DOF, etc.)
        let field18Index = field16Index + 1
        if field18Index < fields.count {
            parseField18(fields[field18Index], into: &result)
        }

        return result
    }

    /// Split the FPL body into fields. Fields are separated by "\n-" in the original format.
    /// After newline normalization, we look for the pattern where a dash starts a new field.
    private static func splitFields(_ body: String) -> [String] {
        // The FPL body after removing "FPL-" prefix looks like:
        // "FPL-N122DR-VG -S22T/L-SBDGORVY/LB2 -LFAT0930 -N0166VFR... -EGTF0033 -PBN/..."
        // First remove the "FPL" prefix
        var text = body
        if text.hasPrefix("FPL") {
            text = String(text.dropFirst(3))
        }
        // Trim leading dash
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "- "))

        // Split on " -" which marks field boundaries after newline collapse
        // But also handle cases where fields are truly dash-separated without spaces
        // Strategy: split on patterns that look like field boundaries
        var fields: [String] = []

        // Regex approach: split on " -" that starts a new field
        let parts = text.components(separatedBy: " -")
        for (i, part) in parts.enumerated() {
            if i == 0 {
                // First part may contain "REG-RULES" with internal dashes
                let subparts = part.components(separatedBy: "-")
                fields.append(contentsOf: subparts)
            } else {
                fields.append(part.trimmingCharacters(in: .whitespaces))
            }
        }

        return fields
    }

    // MARK: - Field Parsers

    private static func parseField7(_ field: String, into result: inout Result) {
        // Aircraft registration, e.g. "N122DR"
        result.aircraftRegistration = field.trimmingCharacters(in: .whitespaces)
    }

    private static func parseField8(_ field: String, into result: inout Result) {
        // Flight rules (first char) and type (second char), e.g. "VG"
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 1 {
            result.flightRules = String(trimmed.prefix(1))
        }
        if trimmed.count >= 2 {
            result.flightType = String(trimmed.dropFirst(1))
        }
    }

    private static func parseField9(_ field: String, equipmentField: String?, into result: inout Result) {
        // e.g. "S22T/L" -> type is S22T
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if let slashIdx = trimmed.firstIndex(of: "/") {
            result.aircraftType = String(trimmed[trimmed.startIndex..<slashIdx])
        } else {
            result.aircraftType = trimmed
        }
    }

    private static func parseField13(_ field: String, into result: inout Result) {
        // e.g. "LFAT0930" -> ICAO=LFAT, time=09:30
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 8 else { return }
        result.originICAO = String(trimmed.prefix(4))
        let timeStr = String(trimmed.dropFirst(4).prefix(4))
        if let hour = Int(timeStr.prefix(2)), let min = Int(timeStr.suffix(2)),
           (0...23).contains(hour), (0...59).contains(min) {
            result.departureTimeUTC = String(format: "%02d:%02d", hour, min)
        }
    }

    private static func parseField15(_ field: String, into result: inout Result) {
        // e.g. "N0166VFR DCT LYD DCT..."
        // Speed is first token: N (knots) or K (km/h) followed by 4 digits
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        let speedPattern = #"^([NK]\d{4})"#
        if let match = trimmed.range(of: speedPattern, options: .regularExpression) {
            result.speed = String(trimmed[match])
            let rest = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Strip flight level/rules prefix (e.g. "VFR", "F350", "A050")
            let routePattern = #"^(?:VFR|IFR|[FAM]\d{3})\s*"#
            if let ruleMatch = rest.range(of: routePattern, options: .regularExpression) {
                result.route = String(rest[ruleMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                result.route = rest
            }
        }
    }

    private static func parseField16(_ field: String, into result: inout Result) {
        // e.g. "EGTF0033" -> ICAO=EGTF, EET=00:33
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        // May have alternate airports after the first 8 chars
        guard trimmed.count >= 8 else { return }
        result.destinationICAO = String(trimmed.prefix(4))
        let eetStr = String(trimmed.dropFirst(4).prefix(4))
        if let hour = Int(eetStr.prefix(2)), let min = Int(eetStr.suffix(2)),
           (0...23).contains(hour), (0...59).contains(min) {
            result.eet = String(format: "%02d:%02d", hour, min)
        }
    }

    private static func parseField18(_ field: String, into result: inout Result) {
        // Look for DOF/YYMMDD
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if let dofRange = trimmed.range(of: #"DOF/(\d{6})"#, options: .regularExpression) {
            let dofStr = String(trimmed[dofRange]).replacingOccurrences(of: "DOF/", with: "")
            // YYMMDD
            if dofStr.count == 6,
               let yy = Int(dofStr.prefix(2)),
               let mm = Int(dofStr.dropFirst(2).prefix(2)),
               let dd = Int(dofStr.suffix(2)) {
                var components = DateComponents()
                components.year = 2000 + yy
                components.month = mm
                components.day = dd
                components.timeZone = TimeZone(identifier: "UTC")
                result.dateOfFlight = Calendar.current.date(from: components)
            }
        }
    }
}

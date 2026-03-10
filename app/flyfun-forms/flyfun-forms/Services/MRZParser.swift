import Foundation
import RZUtilsSwift

struct MRZScanResult {
    let surname: String
    let givenNames: String
    let passportNumber: String
    let nationality: String
    let dateOfBirth: Date
    let expiryDate: Date
    let gender: String
    let issuingCountry: String
    let format: MRZFormat
}

enum MRZFormat { case td3, td1 }

enum MRZParser {

    // MARK: - Public API

    static func parse(lines: [String]) -> MRZScanResult? {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        if trimmed.count == 2, trimmed[0].count == 44, trimmed[1].count == 44 {
            return parseTD3(line1: trimmed[0], line2: trimmed[1])
        }
        if trimmed.count == 3, trimmed[0].count == 30, trimmed[1].count == 30, trimmed[2].count == 30 {
            return parseTD1(line1: trimmed[0], line2: trimmed[1], line3: trimmed[2])
        }
        return nil
    }

    // MARK: - ICAO 9303 Check Digit

    static func checkDigit(_ input: String) -> Int {
        let weights = [7, 3, 1]
        var sum = 0
        for (i, ch) in input.enumerated() {
            let value: Int
            if ch == "<" {
                value = 0
            } else if ch.isNumber {
                value = Int(String(ch))!
            } else if ch.isUppercase {
                value = Int(ch.asciiValue! - Character("A").asciiValue!) + 10
            } else {
                value = 0
            }
            sum += value * weights[i % 3]
        }
        return sum % 10
    }

    // MARK: - OCR Sanitization (digits only)

    static func sanitizeDigits(_ s: String) -> String {
        var result = ""
        for ch in s {
            switch ch {
            case "O": result.append("0")
            case "I": result.append("1")
            case "B": result.append("8")
            case "S": result.append("5")
            case "G": result.append("6")
            case "Q": result.append("0")
            default: result.append(ch)
            }
        }
        return result
    }

    // MARK: - OCR Correction for Alphanumeric Fields

    /// When checksum fails on a field that may contain letters (e.g. passport number),
    /// try common digit→letter substitutions to find the correct reading.
    /// MRZ font makes D↔0, I↔1, B↔8, S↔5, G↔6, Z↔2 ambiguous.
    static func correctField(_ field: String, expectedCheck: Int) -> String? {
        // digit → possible letters (reverse of sanitizeDigits + common MRZ confusions)
        let substitutions: [Character: [Character]] = [
            "0": ["O", "D", "Q"],
            "1": ["I", "L"],
            "8": ["B"],
            "5": ["S"],
            "6": ["G"],
            "2": ["Z"],
        ]

        // Try single-character corrections first (most common case)
        var chars = Array(field)
        for i in 0..<chars.count {
            let original = chars[i]
            if let alternatives = substitutions[original] {
                for alt in alternatives {
                    chars[i] = alt
                    let candidate = String(chars)
                    if checkDigit(candidate) == expectedCheck {
                        return candidate
                    }
                }
                chars[i] = original
            }
        }

        // Try two-character corrections (for cases like D+I both misread)
        for i in 0..<chars.count {
            let origI = chars[i]
            guard let altsI = substitutions[origI] else { continue }
            for altI in altsI {
                chars[i] = altI
                for j in (i+1)..<chars.count {
                    let origJ = chars[j]
                    guard let altsJ = substitutions[origJ] else { continue }
                    for altJ in altsJ {
                        chars[j] = altJ
                        let candidate = String(chars)
                        if checkDigit(candidate) == expectedCheck {
                            return candidate
                        }
                    }
                    chars[j] = origJ
                }
                chars[i] = origI
            }
        }

        return nil
    }

    // MARK: - Date Parsing

    static func parseMRZDate(_ s: String, isBirthDate: Bool) -> Date? {
        guard s.count == 6 else { return nil }
        guard let yy = Int(String(s.prefix(2))),
              let mm = Int(String(s.dropFirst(2).prefix(2))),
              let dd = Int(String(s.suffix(2))) else { return nil }
        guard mm >= 1, mm <= 12, dd >= 1, dd <= 31 else { return nil }

        let century: Int
        if isBirthDate {
            let currentYY = Calendar.current.component(.year, from: Date()) % 100
            century = yy > currentYY ? 1900 : 2000
        } else {
            century = 2000
        }

        var comps = DateComponents()
        comps.year = century + yy
        comps.month = mm
        comps.day = dd
        comps.calendar = Calendar(identifier: .gregorian)
        return comps.date
    }

    // MARK: - TD3 (Passport, 2×44)

    private static func parseTD3(line1: String, line2: String) -> MRZScanResult? {
        // Sanitize only digit-expected positions: check digits (9,19,27,43) and dates (13-18, 21-26)
        let l2 = sanitizePositions(line2, positions: [9, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 43])

        // Validate check digits
        var passNum = substr(l2, 0, 9)
        let passCheck = checkDigit(passNum)
        let passExpected = digit(l2, 9)
        if passCheck != passExpected {
            // Try OCR correction (digit→letter substitutions)
            if let corrected = correctField(passNum, expectedCheck: passExpected) {
                RZSLog.info("MRZ passport corrected: \(passNum) → \(corrected)")
                passNum = corrected
            } else {
                RZSLog.info("MRZ passport check FAIL: \(passNum) computed=\(passCheck) expected=\(passExpected)")
                return nil
            }
        }

        let dob = substr(l2, 13, 6)
        let dobCheck = checkDigit(dob)
        let dobExpected = digit(l2, 19)
        guard dobCheck == dobExpected else {
            RZSLog.info("MRZ DOB check FAIL: \(dob) computed=\(dobCheck) expected=\(dobExpected)")
            return nil
        }

        let expiry = substr(l2, 21, 6)
        let expiryCheck = checkDigit(expiry)
        let expiryExpected = digit(l2, 27)
        guard expiryCheck == expiryExpected else {
            RZSLog.info("MRZ expiry check FAIL: \(expiry) computed=\(expiryCheck) expected=\(expiryExpected)")
            return nil
        }

        // Composite check: positions 0-9 + 13-19 + 21-27 + 28-42
        // Use corrected passport number (passNum) + its check digit for positions 0-9
        let compositeInput = passNum + String(substr(l2, 9, 1)) + substr(l2, 13, 7) + substr(l2, 21, 7) + substr(l2, 28, 15)
        let compCheck = checkDigit(compositeInput)
        let compExpected = digit(l2, 43)
        guard compCheck == compExpected else {
            RZSLog.info("MRZ composite check FAIL: computed=\(compCheck) expected=\(compExpected)")
            return nil
        }

        // Parse names from line 1
        let (surname, givenNames) = parseNames(String(line1.dropFirst(5)))
        let issuingCountry = cleanCountry(substr(line1, 2, 3))
        let nationality = cleanCountry(substr(l2, 10, 3))
        let gender = parseGender(substr(l2, 20, 1))

        guard let birthDate = parseMRZDate(dob, isBirthDate: true),
              let expiryDate = parseMRZDate(expiry, isBirthDate: false) else { return nil }

        return MRZScanResult(
            surname: surname,
            givenNames: givenNames,
            passportNumber: cleanField(passNum),
            nationality: nationality,
            dateOfBirth: birthDate,
            expiryDate: expiryDate,
            gender: gender,
            issuingCountry: issuingCountry,
            format: .td3
        )
    }

    // MARK: - TD1 (ID Card, 3×30)

    private static func parseTD1(line1: String, line2: String, line3: String) -> MRZScanResult? {
        // Sanitize only digit-expected positions
        // Line 1: check digit at 14
        let l1 = sanitizePositions(line1, positions: [14])
        // Line 2: DOB 0-5, check 6, expiry 8-13, check 14, composite check 29
        let l2 = sanitizePositions(line2, positions: [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 29])

        let docNum = substr(l1, 5, 9)
        guard checkDigit(docNum) == digit(l1, 14) else { return nil }

        let dob = substr(l2, 0, 6)
        guard checkDigit(dob) == digit(l2, 6) else { return nil }

        let expiry = substr(l2, 8, 6)
        guard checkDigit(expiry) == digit(l2, 14) else { return nil }

        // Composite: line1[5..29] + line2[0..6] + line2[8..14] + line2[18..28]
        let compositeInput = substr(l1, 5, 25) + substr(l2, 0, 7) + substr(l2, 8, 7) + substr(l2, 18, 11)
        guard checkDigit(compositeInput) == digit(l2, 29) else { return nil }

        let issuingCountry = cleanCountry(substr(l1, 2, 3))
        let nationality = cleanCountry(substr(l2, 15, 3))
        let gender = parseGender(substr(l2, 7, 1))

        let (surname, givenNames) = parseNames(line3)

        guard let birthDate = parseMRZDate(dob, isBirthDate: true),
              let expiryDate = parseMRZDate(expiry, isBirthDate: false) else { return nil }

        return MRZScanResult(
            surname: surname,
            givenNames: givenNames,
            passportNumber: cleanField(docNum),
            nationality: nationality,
            dateOfBirth: birthDate,
            expiryDate: expiryDate,
            gender: gender,
            issuingCountry: issuingCountry,
            format: .td1
        )
    }

    // MARK: - Helpers

    private static func substr(_ s: String, _ start: Int, _ length: Int) -> String {
        let startIdx = s.index(s.startIndex, offsetBy: start)
        let endIdx = s.index(startIdx, offsetBy: length)
        return String(s[startIdx..<endIdx])
    }

    private static func digit(_ s: String, _ pos: Int) -> Int {
        let ch = s[s.index(s.startIndex, offsetBy: pos)]
        return Int(String(ch)) ?? -1
    }

    /// Apply OCR digit sanitization only to specific positions (dates, check digits).
    private static func sanitizePositions(_ line: String, positions: Set<Int>) -> String {
        var chars = Array(line)
        for i in positions where i < chars.count {
            let sanitized = sanitizeDigits(String(chars[i]))
            chars[i] = sanitized.first!
        }
        return String(chars)
    }

    private static func parseNames(_ nameField: String) -> (surname: String, givenNames: String) {
        let parts = nameField.components(separatedBy: "<<")
        let surname = titleCase(parts[0].replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces))
        let given: String
        if parts.count > 1 {
            given = titleCase(parts[1...].joined(separator: " ").replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces))
        } else {
            given = ""
        }
        return (surname, given)
    }

    private static func titleCase(_ s: String) -> String {
        s.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func cleanField(_ s: String) -> String {
        s.replacingOccurrences(of: "<", with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func cleanCountry(_ s: String) -> String {
        s.replacingOccurrences(of: "<", with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func parseGender(_ s: String) -> String {
        switch s {
        case "M": return "M"
        case "F": return "F"
        default: return "X"
        }
    }
}

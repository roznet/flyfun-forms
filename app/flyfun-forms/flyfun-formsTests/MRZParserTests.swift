import Testing
import Foundation
@testable import flyfun_forms

@Suite("MRZParser")
struct MRZParserTests {

    // MARK: - Check Digit

    @Test("ICAO check digit for known passport number")
    func checkDigitPassportNumber() {
        // L898902C3 → check digit 6 (ICAO specimen)
        #expect(MRZParser.checkDigit("L898902C3") == 6)
    }

    @Test("Check digit for all-filler string is 0")
    func checkDigitFiller() {
        #expect(MRZParser.checkDigit("<<<") == 0)
    }

    @Test("Check digit for digits only")
    func checkDigitDigitsOnly() {
        // 740812 → 7*7+4*3+0*1+8*7+1*3+2*1 = 49+12+0+56+3+2 = 122 → 122%10 = 2
        #expect(MRZParser.checkDigit("740812") == 2)
    }

    // MARK: - Sanitization

    @Test("Sanitize common OCR misreads")
    func sanitizeDigits() {
        #expect(MRZParser.sanitizeDigits("O1B5") == "0185")
        #expect(MRZParser.sanitizeDigits("SIQG") == "5106")
        #expect(MRZParser.sanitizeDigits("123") == "123")
    }

    // MARK: - Date Parsing

    @Test("Birth date with year > current → 19xx")
    func birthDate1900s() {
        let date = MRZParser.parseMRZDate("740812", isBirthDate: true)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        #expect(comps.year == 1974)
        #expect(comps.month == 8)
        #expect(comps.day == 12)
    }

    @Test("Birth date with year <= current → 20xx")
    func birthDate2000s() {
        let date = MRZParser.parseMRZDate("050315", isBirthDate: true)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        #expect(comps.year == 2005)
        #expect(comps.month == 3)
        #expect(comps.day == 15)
    }

    @Test("Expiry date always 20xx")
    func expiryDate() {
        let date = MRZParser.parseMRZDate("120415", isBirthDate: false)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        #expect(comps.year == 2012)
        #expect(comps.month == 4)
        #expect(comps.day == 15)
    }

    @Test("Invalid date returns nil")
    func invalidDate() {
        #expect(MRZParser.parseMRZDate("001301", isBirthDate: true) == nil)  // month 13
        #expect(MRZParser.parseMRZDate("AB0101", isBirthDate: true) == nil)  // non-digit
        #expect(MRZParser.parseMRZDate("12", isBirthDate: true) == nil)      // too short
    }

    // MARK: - TD3 Parsing (Passport)

    @Test("ICAO specimen passport parses correctly")
    func td3ICAOSpecimen() {
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        let line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let result = MRZParser.parse(lines: [line1, line2])

        #expect(result != nil)
        #expect(result?.surname == "Eriksson")
        #expect(result?.givenNames == "Anna Maria")
        #expect(result?.passportNumber == "L898902C3")
        #expect(result?.nationality == "UTO")
        #expect(result?.issuingCountry == "UTO")
        #expect(result?.gender == "F")
        #expect(result?.format == .td3)

        let dobComps = Calendar.current.dateComponents([.year, .month, .day], from: result!.dateOfBirth)
        #expect(dobComps.year == 1974)
        #expect(dobComps.month == 8)
        #expect(dobComps.day == 12)

        let expComps = Calendar.current.dateComponents([.year, .month, .day], from: result!.expiryDate)
        #expect(expComps.year == 2012)
        #expect(expComps.month == 4)
        #expect(expComps.day == 15)
    }

    @Test("TD3 with bad check digit returns nil")
    func td3BadCheckDigit() {
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        // Changed last digit from 0 to 9 (bad composite check)
        let line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<19"
        #expect(MRZParser.parse(lines: [line1, line2]) == nil)
    }

    @Test("TD3 male gender")
    func td3MaleGender() {
        // Modified specimen: M instead of F at position 20, with valid check digits recomputed
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        let line2 = "L898902C36UTO7408122M1204159ZE184226B<<<<<10"
        let result = MRZParser.parse(lines: [line1, line2])
        #expect(result?.gender == "M")
    }

    @Test("TD3 unspecified gender")
    func td3UnspecifiedGender() {
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        let line2 = "L898902C36UTO7408122<1204159ZE184226B<<<<<10"
        let result = MRZParser.parse(lines: [line1, line2])
        #expect(result?.gender == "X")
    }

    // MARK: - TD1 Parsing (ID Card)

    @Test("TD1 ID card parses correctly")
    func td1Parse() {
        let line1 = "I<UTOD231458907<<<<<<<<<<<<<<<" // doc type I, country UTO, doc num D23145890, check 7
        let line2 = "7408122F1204159UTO<<<<<<<<<<<6" // DOB 740812 check 2, F, expiry 120415 check 9, nat UTO, composite 6
        let line3 = "ERIKSSON<<ANNA<MARIA<<<<<<<<<<" // names
        let result = MRZParser.parse(lines: [line1, line2, line3])

        #expect(result != nil)
        #expect(result?.surname == "Eriksson")
        #expect(result?.givenNames == "Anna Maria")
        #expect(result?.passportNumber == "D23145890")
        #expect(result?.nationality == "UTO")
        #expect(result?.issuingCountry == "UTO")
        #expect(result?.gender == "F")
        #expect(result?.format == .td1)
    }

    // MARK: - Malformed Input

    @Test("Wrong number of lines returns nil")
    func wrongLineCount() {
        #expect(MRZParser.parse(lines: ["ONELINE"]) == nil)
        #expect(MRZParser.parse(lines: []) == nil)
    }

    @Test("Wrong line length returns nil")
    func wrongLineLength() {
        #expect(MRZParser.parse(lines: ["SHORT", "ALSO_SHORT"]) == nil)
    }

    @Test("Names with single component")
    func singleName() {
        // Test the name parsing helper indirectly through a valid MRZ
        let line1 = "P<UTOMADONNA<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
        let line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let result = MRZParser.parse(lines: [line1, line2])
        #expect(result?.surname == "Madonna")
    }
}

import Testing
import Foundation
@testable import flyfun_forms

@Suite("MRZResultProcessor")
struct MRZResultProcessorTests {

    // MARK: - Test Helpers

    private static func makeScanResult(
        surname: String = "Doe",
        givenNames: String = "John",
        passportNumber: String = "AB1234567",
        nationality: String = "GBR",
        dateOfBirth: Date = Date(timeIntervalSince1970: 0),
        expiryDate: Date = Date(timeIntervalSinceNow: 365 * 24 * 3600),
        gender: String = "M",
        issuingCountry: String = "GBR",
        format: MRZFormat = .td3
    ) -> MRZScanResult {
        MRZScanResult(
            surname: surname,
            givenNames: givenNames,
            passportNumber: passportNumber,
            nationality: nationality,
            dateOfBirth: dateOfBirth,
            expiryDate: expiryDate,
            gender: gender,
            issuingCountry: issuingCountry,
            format: format
        )
    }

    // MARK: - Name Matching

    @Test("Exact name match")
    func exactNameMatch() {
        let person = Person(firstName: "John", lastName: "Doe")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        #expect(MRZResultProcessor.namesMatch(person: person, result: result))
    }

    @Test("Case insensitive name match")
    func caseInsensitiveMatch() {
        let person = Person(firstName: "john", lastName: "doe")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        #expect(MRZResultProcessor.namesMatch(person: person, result: result))
    }

    @Test("Truncated first name match (MRZ truncation)")
    func truncatedFirstNameMatch() {
        let person = Person(firstName: "Jean-Pierre", lastName: "Dupont")
        let result = Self.makeScanResult(surname: "Dupont", givenNames: "Jean Pierre")
        // Surname matches, and first names share prefix "jean"
        // Note: the MRZ replaces hyphens with spaces, but prefix matching still works
        #expect(MRZResultProcessor.namesMatch(person: person, result: result))
    }

    @Test("Different surname does not match")
    func differentSurname() {
        let person = Person(firstName: "John", lastName: "Smith")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        #expect(!MRZResultProcessor.namesMatch(person: person, result: result))
    }

    @Test("Empty person name does not match")
    func emptyPersonName() {
        let person = Person(firstName: "", lastName: "")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        #expect(!MRZResultProcessor.namesMatch(person: person, result: result))
    }

    // MARK: - Name Similarity

    @Test("Perfect match gives score >= 0.9")
    func perfectSimilarity() {
        let person = Person(firstName: "John", lastName: "Doe")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        #expect(MRZResultProcessor.nameSimilarity(person: person, result: result) >= 0.9)
    }

    @Test("Surname-only match gives moderate score")
    func surnameOnlyScore() {
        let person = Person(firstName: "Jane", lastName: "Doe")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        let score = MRZResultProcessor.nameSimilarity(person: person, result: result)
        #expect(score >= 0.4)
        #expect(score < 0.9)
    }

    @Test("No match gives low score")
    func noMatchScore() {
        let person = Person(firstName: "Alice", lastName: "Smith")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        #expect(MRZResultProcessor.nameSimilarity(person: person, result: result) < 0.4)
    }

    // MARK: - Fill Person

    @Test("fillPerson sets empty fields")
    func fillPersonEmptyFields() {
        let person = Person()
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John", nationality: "GBR", gender: "F")
        MRZResultProcessor.fillPerson(person, from: result)

        #expect(person.firstName == "John")
        #expect(person.lastName == "Doe")
        #expect(person.nationality == "GBR")
        #expect(person.sex == "Female")
        #expect(person.dateOfBirth == result.dateOfBirth)
    }

    @Test("fillPerson does not overwrite existing fields by default")
    func fillPersonPreservesExisting() {
        let person = Person(firstName: "Jane", lastName: "Smith")
        person.nationality = "FRA"
        person.sex = "Female"
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John", nationality: "GBR", gender: "M")
        MRZResultProcessor.fillPerson(person, from: result)

        #expect(person.firstName == "Jane")
        #expect(person.lastName == "Smith")
        #expect(person.nationality == "FRA")
        #expect(person.sex == "Female")
    }

    @Test("fillPerson overwrites name when flag is set")
    func fillPersonOverwriteName() {
        let person = Person(firstName: "Jane", lastName: "Smith")
        let result = Self.makeScanResult(surname: "Doe", givenNames: "John")
        MRZResultProcessor.fillPerson(person, from: result, overwriteName: true)

        #expect(person.firstName == "John")
        #expect(person.lastName == "Doe")
    }

    // MARK: - Fill Document

    @Test("fillDocument sets all fields")
    func fillDocumentFields() {
        let doc = TravelDocument()
        let result = Self.makeScanResult(passportNumber: "XY9876543", issuingCountry: "FRA")
        MRZResultProcessor.fillDocument(doc, from: result)

        #expect(doc.docNumber == "XY9876543")
        #expect(doc.issuingCountry == "FRA")
        #expect(doc.expiryDate == result.expiryDate)
        #expect(doc.docType == "Passport")
    }

    @Test("fillDocument sets Identity card for TD1")
    func fillDocumentTD1() {
        let doc = TravelDocument()
        let result = Self.makeScanResult(format: .td1)
        MRZResultProcessor.fillDocument(doc, from: result)

        #expect(doc.docType == "Identity card")
    }
}

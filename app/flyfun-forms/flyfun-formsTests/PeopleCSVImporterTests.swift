import Testing
import Foundation
@testable import flyfun_forms

// MARK: - Helpers

private func csvData(_ text: String) -> Data {
    text.data(using: .utf8)!
}

// MARK: - Parse tests

@Suite("PeopleCSVImporter.parse")
struct CSVParseTests {

    @Test("Parses basic CSV with all columns")
    func basicParse() throws {
        let csv = """
        First Name,Last Name,Gender,DoB,Nationality,Doc Type,Doc Number,Doc Expiry,Doc Issuing State,Type
        Zara,Kowalski,F,1985-03-22,XYZ,Passport,PP-100001,2030-06-15,XYZ,Crew
        Tariq,Bergström,M,1990-11-07,ABC,Passport,PP-100002,2029-01-20,ABC,
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))

        #expect(result.count == 2)

        #expect(result[0].firstName == "Zara")
        #expect(result[0].lastName == "Kowalski")
        #expect(result[0].sex == "F")
        #expect(result[0].nationality == "XYZ")
        #expect(result[0].idNumber == "PP-100001")
        #expect(result[0].idType == "Passport")
        #expect(result[0].idIssuingCountry == "XYZ")
        #expect(result[0].isCrew == true)

        #expect(result[1].firstName == "Tariq")
        #expect(result[1].lastName == "Bergström")
        #expect(result[1].isCrew == false)
    }

    @Test("Parses date of birth correctly")
    func dateOfBirth() throws {
        let csv = """
        First Name,Last Name,DoB
        Lina,Petrova,1978-08-14
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result.count == 1)
        #expect(result[0].dateOfBirth != nil)

        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents([.year, .month, .day], from: result[0].dateOfBirth!)
        #expect(components.year == 1978)
        #expect(components.month == 8)
        #expect(components.day == 14)
    }

    @Test("Handles missing optional columns gracefully")
    func minimalColumns() throws {
        let csv = """
        First Name,Last Name
        Nico,Tanaka
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result.count == 1)
        #expect(result[0].firstName == "Nico")
        #expect(result[0].lastName == "Tanaka")
        #expect(result[0].sex == nil)
        #expect(result[0].dateOfBirth == nil)
        #expect(result[0].nationality == nil)
        #expect(result[0].idNumber == nil)
        #expect(result[0].isCrew == false)
    }

    @Test("Throws on empty data")
    func emptyData() throws {
        #expect(throws: PeopleCSVImporter.ImportError.self) {
            try PeopleCSVImporter.parse(data: csvData(""))
        }
    }

    @Test("Throws on missing required columns")
    func missingRequiredColumns() throws {
        let csv = """
        Name,Age
        Zara,30
        """
        #expect(throws: PeopleCSVImporter.ImportError.self) {
            try PeopleCSVImporter.parse(data: csvData(csv))
        }
    }

    @Test("Throws if only First Name is present (Last Name missing)")
    func missingLastName() throws {
        let csv = """
        First Name
        Zara
        """
        #expect(throws: PeopleCSVImporter.ImportError.self) {
            try PeopleCSVImporter.parse(data: csvData(csv))
        }
    }

    @Test("Skips rows with empty first and last name")
    func skipsEmptyNames() throws {
        let csv = """
        First Name,Last Name
        Zara,Kowalski
        ,
        ,Petrova
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        // First row is valid, second is empty (skipped), third has last name only (kept)
        #expect(result.count == 2)
        #expect(result[1].lastName == "Petrova")
    }

    @Test("Handles quoted fields with commas")
    func quotedFields() throws {
        let csv = """
        First Name,Last Name,Doc Number
        Zara,"Kowalski, Jr.",PP-100001
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result.count == 1)
        #expect(result[0].lastName == "Kowalski, Jr.")
    }

    @Test("Header is case-insensitive")
    func caseInsensitiveHeaders() throws {
        let csv = """
        FIRST NAME,LAST NAME,DOB
        Zara,Kowalski,1985-03-22
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result.count == 1)
        #expect(result[0].firstName == "Zara")
    }

    @Test("Empty optional fields become nil")
    func emptyOptionalFields() throws {
        let csv = """
        First Name,Last Name,Gender,Nationality,Doc Number
        Zara,Kowalski,,,
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result.count == 1)
        #expect(result[0].sex == nil)
        #expect(result[0].nationality == nil)
        #expect(result[0].idNumber == nil)
    }

    @Test("Crew type detection is case-insensitive")
    func crewTypeCaseInsensitive() throws {
        let csv = """
        First Name,Last Name,Type
        Zara,Kowalski,CREW
        Tariq,Bergström,crew
        Lina,Petrova,Passenger
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result[0].isCrew == true)
        #expect(result[1].isCrew == true)
        #expect(result[2].isCrew == false)
    }

    @Test("Expiry date parsed correctly")
    func expiryDate() throws {
        let csv = """
        First Name,Last Name,Doc Number,Doc Expiry
        Zara,Kowalski,PP-100001,2030-06-15
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result[0].idExpiry != nil)

        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents([.year, .month, .day], from: result[0].idExpiry!)
        #expect(components.year == 2030)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }

    @Test("Invalid date returns nil, doesn't crash")
    func invalidDate() throws {
        let csv = """
        First Name,Last Name,DoB,Doc Expiry
        Zara,Kowalski,not-a-date,also-bad
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result.count == 1)
        #expect(result[0].dateOfBirth == nil)
        #expect(result[0].idExpiry == nil)
    }

    @Test("Multiple rows parsed correctly")
    func multipleRows() throws {
        let csv = """
        First Name,Last Name,Nationality
        Zara,Kowalski,XYZ
        Tariq,Bergström,ABC
        Lina,Petrova,DEF
        Nico,Tanaka,GHI
        """
        let result = try PeopleCSVImporter.parse(data: csvData(csv))
        #expect(result.count == 4)
        #expect(result[3].firstName == "Nico")
        #expect(result[3].nationality == "GHI")
    }
}

// MARK: - API Types encoding tests

@Suite("APITypes Codable")
struct APITypesTests {

    @Test("GenerateRequest encodes snake_case keys")
    func generateRequestEncoding() throws {
        let request = GenerateRequest(
            airport: "ZZZZ",
            form: "test",
            flight: FlightPayload(
                origin: "ZZZZ", destination: "YYYY",
                departureDate: "2099-06-15", departureTimeUtc: "08:30",
                arrivalDate: "2099-06-15", arrivalTimeUtc: "10:45"
            ),
            aircraft: AircraftPayload(registration: "ZZ-TST", type: "FX99"),
            crew: [PersonPayload(firstName: "Zara", lastName: "Kowalski")],
            passengers: []
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Check snake_case keys
        #expect(json["connecting_flight"] == nil)
        #expect(json["extra_fields"] == nil)

        let flight = json["flight"] as! [String: Any]
        #expect(flight["departure_date"] as? String == "2099-06-15")
        #expect(flight["departure_time_utc"] as? String == "08:30")

        let crew = json["crew"] as! [[String: Any]]
        #expect(crew[0]["first_name"] as? String == "Zara")
    }

    @Test("ExtraFieldValue text round-trip")
    func extraFieldValueText() throws {
        let value = ExtraFieldValue.text("Pleasure")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(ExtraFieldValue.self, from: data)
        if case .text(let str) = decoded {
            #expect(str == "Pleasure")
        } else {
            Issue.record("Expected .text, got \(decoded)")
        }
    }

    @Test("ExtraFieldValue person dict round-trip")
    func extraFieldValuePerson() throws {
        let value = ExtraFieldValue.person(["name": "Zara K", "address": "7 Birch Lane"])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(ExtraFieldValue.self, from: data)
        if case .person(let dict) = decoded {
            #expect(dict["name"] == "Zara K")
            #expect(dict["address"] == "7 Birch Lane")
        } else {
            Issue.record("Expected .person, got \(decoded)")
        }
    }

    @Test("AirportDetailResponse decodes from server JSON")
    func airportDetailDecoding() throws {
        let json = """
        {
            "icao": "ZZZZ",
            "name": "Nowherton",
            "forms": [{
                "id": "test",
                "label": "Test Form",
                "version": "1.0",
                "required_fields": {
                    "flight": ["origin"],
                    "aircraft": ["registration"],
                    "crew": ["first_name"],
                    "passengers": ["first_name"]
                },
                "extra_fields": [{
                    "key": "reason",
                    "label": "Reason",
                    "type": "choice",
                    "options": ["Alpha", "Beta"]
                }],
                "max_crew": 4,
                "max_passengers": 8,
                "has_connecting_flight": false,
                "time_reference": "utc"
            }]
        }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(AirportDetailResponse.self, from: json)
        #expect(detail.icao == "ZZZZ")
        #expect(detail.forms.count == 1)
        #expect(detail.forms[0].maxCrew == 4)
        #expect(detail.forms[0].extraFields[0].options == ["Alpha", "Beta"])
        #expect(detail.forms[0].hasConnectingFlight == false)
    }

    @Test("PersonPayload encodes all snake_case fields")
    func personPayloadEncoding() throws {
        let person = PersonPayload(
            function: "Pilot",
            firstName: "Zara",
            lastName: "Kowalski",
            dob: "1985-03-22",
            nationality: "XYZ",
            idNumber: "PP-100001",
            idType: "Passport",
            idIssuingCountry: "XYZ",
            idExpiry: "2030-06-15",
            sex: "Female",
            placeOfBirth: "Northville",
            address: "7 Birch Lane"
        )
        let data = try JSONEncoder().encode(person)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["first_name"] as? String == "Zara")
        #expect(json["last_name"] as? String == "Kowalski")
        #expect(json["id_number"] as? String == "PP-100001")
        #expect(json["id_type"] as? String == "Passport")
        #expect(json["id_issuing_country"] as? String == "XYZ")
        #expect(json["id_expiry"] as? String == "2030-06-15")
        #expect(json["place_of_birth"] as? String == "Northville")
    }
}

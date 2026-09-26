import FlyFunCommon
import Foundation
import SwiftData
import Testing
@testable import flyfun_forms

@MainActor
struct ValidationFixTests {
    let container: ModelContainer
    let flight: Flight
    let pilot: Person
    let passenger: Person
    let aircraft: Aircraft

    init() throws {
        container = try ModelContainer(
            for: Person.self, TravelDocument.self, Aircraft.self, Flight.self, Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        pilot = Person(firstName: "Test", lastName: "Pilot")
        passenger = Person(firstName: "Test", lastName: "Passenger")
        aircraft = Aircraft(registration: "ZZ-TEST", type: "DR40")
        flight = Flight()
        flight.originICAO = "EGTF"
        flight.destinationICAO = "LFRM"
        [pilot, passenger].forEach(context.insert)
        context.insert(aircraft)
        context.insert(flight)

        let passport = TravelDocument(docType: "Passport", docNumber: "FXA000001", issuingCountry: "FRA")
        passport.person = pilot
        context.insert(passport)
    }

    private func context(formInfo: FormInfo? = nil) -> ValidationFixContext {
        ValidationFixContext(
            flight: flight, airport: "LFRM", formInfo: formInfo,
            crew: [pilot], passengers: [passenger]
        )
    }

    private func fix(_ field: String, formInfo: FormInfo? = nil) -> ValidationFix {
        context(formInfo: formInfo).fix(for: ServerValidationError(field: field, error: "required for this form"))
    }

    // MARK: - Path parsing

    @Test func parsesIndexedPath() {
        #expect(ValidationFieldPath("crew[2].id_number") == ValidationFieldPath(section: "crew", index: 2, key: "id_number"))
    }

    @Test func parsesExtraFieldPath() {
        #expect(ValidationFieldPath("extra_fields.email") == ValidationFieldPath(section: "extra_fields", index: nil, key: "email"))
    }

    @Test func parsesBareSection() {
        #expect(ValidationFieldPath("crew") == ValidationFieldPath(section: "crew", index: nil, key: ""))
    }

    // MARK: - Flight-level fields

    @Test func reasonForVisitUsesTheFormsOptions() throws {
        let form = try formInfo(extraFields: #"[{"key":"reason_for_visit","label":"Reason","type":"choice","options":["Based","Repair"]}]"#)
        guard case .reasonForVisit(let options) = fix("extra_fields.reason_for_visit", formInfo: form) else {
            Issue.record("expected reasonForVisit"); return
        }
        #expect(options == ["Based", "Repair"])
    }

    @Test func reasonForVisitFallsBackToTheGAROptions() {
        guard case .reasonForVisit(let options) = fix("extra_fields.reason_for_visit") else {
            Issue.record("expected reasonForVisit"); return
        }
        #expect(options == Flight.reasonForVisitOptions)
    }

    @Test func responsiblePersonAndContactPickAPerson() {
        guard case .responsiblePerson = fix("extra_fields.responsible_person") else {
            Issue.record("expected responsiblePerson"); return
        }
        guard case .responsiblePerson = fix("flight.contact") else {
            Issue.record("expected responsiblePerson"); return
        }
    }

    @Test func emailIsEditedOnTheResponsiblePerson() {
        flight.responsiblePerson = passenger
        guard case .personText(let person, .email) = fix("extra_fields.email") else {
            Issue.record("expected the responsible person's email"); return
        }
        #expect(person === passenger)
    }

    @Test func telephoneWithoutResponsiblePersonAsksForOne() {
        flight.responsiblePerson = nil
        guard case .responsiblePerson = fix("extra_fields.telephone") else {
            Issue.record("expected responsiblePerson"); return
        }
    }

    @Test func scheduleIsNotEditedInPlace() {
        guard case .none = fix("flight.departure_time_utc") else {
            Issue.record("expected none"); return
        }
    }

    // MARK: - People

    @Test func personFieldTargetsTheIndexedPerson() {
        guard case .personText(let person, .firstName) = fix("passengers[0].first_name") else {
            Issue.record("expected passenger first name"); return
        }
        #expect(person === passenger)
    }

    @Test func outOfRangeIndexIsNotEditable() {
        guard case .none = fix("crew[3].first_name") else {
            Issue.record("expected none"); return
        }
    }

    @Test func dateOfBirthAndSex() {
        guard case .personDateOfBirth(let p) = fix("crew[0].dob"), p === pilot else {
            Issue.record("expected pilot DOB"); return
        }
        guard case .personSex(let s) = fix("crew[0].sex"), s === pilot else {
            Issue.record("expected pilot sex"); return
        }
    }

    @Test func nationalityIsTheDocumentsIssuingCountry() {
        guard case .document(let person, .issuingCountry) = fix("crew[0].nationality") else {
            Issue.record("expected document issuing country"); return
        }
        #expect(person === pilot)
        #expect(context().document(for: pilot)?.docNumber == "FXA000001")
    }

    @Test func personWithoutDocumentResolvesToNone() {
        guard case .document(let person, .number) = fix("passengers[0].id_number") else {
            Issue.record("expected document number"); return
        }
        #expect(context().document(for: person) == nil, "the sheet offers Add Document when there is none")
    }

    // MARK: - Aircraft

    @Test func aircraftTypeIsEditedInPlace() {
        flight.aircraft = aircraft
        guard case .aircraftText(let ac, .type) = fix("aircraft.type") else {
            Issue.record("expected aircraft type"); return
        }
        #expect(ac === aircraft)
    }

    @Test func aircraftOwnerOpensTheAircraft() {
        flight.aircraft = aircraft
        guard case .openAircraft = fix("aircraft.owner") else {
            Issue.record("expected openAircraft"); return
        }
    }

    @Test func noAircraftAsksForOne() {
        flight.aircraft = nil
        guard case .chooseAircraft = fix("aircraft.registration") else {
            Issue.record("expected chooseAircraft"); return
        }
    }

    // MARK: - Other extra fields

    @Test func textAndChoiceExtraFields() throws {
        let form = try formInfo(extraFields: #"""
            [{"key":"handler","label":"Handler","type":"text"},
             {"key":"fuel","label":"Fuel","type":"choice","options":["AVGAS","JET A1"]},
             {"key":"owner_rep","label":"Owner","type":"person"}]
            """#)
        guard case .extraText(key: "handler") = fix("extra_fields.handler", formInfo: form) else {
            Issue.record("expected extraText"); return
        }
        guard case .extraChoice(key: "fuel", let options) = fix("extra_fields.fuel", formInfo: form) else {
            Issue.record("expected extraChoice"); return
        }
        #expect(options == ["AVGAS", "JET A1"])
        guard case .none = fix("extra_fields.owner_rep", formInfo: form) else {
            Issue.record("person extra fields are not edited in place yet"); return
        }
    }

    @Test func formKeyMatchesTheFlightEditorsKey() throws {
        let form = try formInfo(extraFields: "[]")
        #expect(context(formInfo: form).formKey == "LFRM_test")
    }

    private func formInfo(extraFields: String) throws -> FormInfo {
        let json = """
            {"id":"test","label":"Test","version":"1.0",
             "required_fields":{"flight":[],"aircraft":[],"crew":[],"passengers":[]},
             "extra_fields":\(extraFields),"max_crew":4,"max_passengers":4,
             "has_connecting_flight":false,"has_return_flight":false,"time_reference":"utc",
             "send_to":null,"email":null,"kind":"document","direction":null}
            """
        return try JSONDecoder().decode(FormInfo.self, from: Data(json.utf8))
    }
}

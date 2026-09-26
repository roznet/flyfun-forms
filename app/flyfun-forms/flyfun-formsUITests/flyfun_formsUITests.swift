//
//  flyfun_formsUITests.swift
//  flyfun-formsUITests
//
//  XCUITest journeys (#24). Launched with FLYFUN_UITEST + FLYFUN_MOCK, so the
//  app skips sign-in, runs on an in-memory store seeded by `UITestFixtures`, and
//  answers every request from `UITestURLProtocol`: deterministic, offline, and
//  never near the developer's iCloud data. Selectors key off
//  accessibilityIdentifiers rather than visible text where one exists, so they
//  survive copy and localisation changes.
//
//  The fixture records named here (Test Pilot, ZZ-TEST, EGTF → LFRM, …) are
//  defined in `UITestFixtures.seed`.
//

import XCTest

final class flyfun_formsUITests: XCTestCase {

    /// Where the app writes the body of each request it sends, and
    /// `unstubbed.log` for any it had no answer for. One per test.
    private var captureDirectory: URL!

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        captureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flyfun-forms-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        // Pinned, not inherited: simulator orientation persists between runs,
        // and CI runners have handed out iPhones already in landscape. A `Form`
        // is a lazy `List`, so in landscape rows below the fold are missing from
        // the accessibility tree altogether — the failure that cost flyfun-weather
        // four red nightlies before anyone read the element tree.
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // A request the stub had no answer for failed quietly inside the app;
        // this is where it becomes loud.
        let log = captureDirectory.appendingPathComponent("unstubbed.log")
        if let unstubbed = try? String(contentsOf: log, encoding: .utf8), !unstubbed.isEmpty {
            XCTFail("the app made requests UITestURLProtocol has no stub for:\n\(unstubbed)")
        }
        try? FileManager.default.removeItem(at: captureDirectory)
    }

    /// How long to wait for something that should appear. Generous because
    /// `waitForExistence` returns as soon as the element exists, so only a test
    /// that was going to fail pays for it, and CI runners are several times
    /// slower than a local Mac.
    private static let uiTimeout: TimeInterval = 20

    // MARK: - Launch

    @MainActor
    private func launchApp(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FLYFUN_UITEST"] = "1"
        app.launchEnvironment["FLYFUN_MOCK"] = "1"
        app.launchEnvironment["FLYFUN_UITEST_CAPTURE_DIR"] = captureDirectory.path
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    // MARK: - Journeys

    /// Journey 1: the seeded store is what the app shows, in every tab, and a
    /// document's expiry state is spoken rather than carried by colour alone.
    @MainActor
    func testLaunchShowsSeededData() throws {
        let app = launchApp()

        openTab(app, "People")
        for lastName in ["Pilot", "Passenger", "Traveller"] {
            XCTAssertTrue(element(app, "personRow-\(lastName)").waitForExistence(timeout: Self.uiTimeout),
                          "\(lastName) should be listed")
        }

        openTab(app, "Aircraft")
        XCTAssertTrue(element(app, "aircraftRow-ZZ-TEST").waitForExistence(timeout: Self.uiTimeout),
                      "ZZ-TEST should be listed")

        openTab(app, "Flights")
        XCTAssertTrue(element(app, "flightRow-EGTF-LFRM").waitForExistence(timeout: Self.uiTimeout),
                      "the outbound leg should be upcoming")
        XCTAssertTrue(element(app, "flightRow-LFRM-EGTF").exists, "the return leg should be upcoming")
        XCTAssertFalse(element(app, "flightRow-EGTF-LFAC").exists, "past flights start collapsed")
        element(app, "pastFlightsToggle").tap()
        XCTAssertTrue(element(app, "flightRow-EGTF-LFAC").waitForExistence(timeout: Self.uiTimeout),
                      "expanding Past Flights should show last month's flight")

        openTab(app, "People")
        element(app, "personRow-Traveller").tap()
        let passport = element(app, "documentRow-DEU")
        XCTAssertTrue(passport.waitForExistence(timeout: Self.uiTimeout), "the expired passport should be listed")
        let expiry = passport.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Expires'")).firstMatch
        XCTAssertTrue(expiry.exists, "the passport row should show its expiry date")
        XCTAssertEqual(expiry.value as? String, "Document expired",
                       "an expired passport should say so, not only turn red")
    }

    /// Journey 2: a new flight is route → people → create, and the people step
    /// offers last time's crew in one tap.
    @MainActor
    func testNewFlightWithSuggestedCrew() throws {
        let app = launchApp()
        openTab(app, "Flights")
        element(app, "addFlightButton").tap()

        let route = element(app, "newFlightRouteButton")
        XCTAssertTrue(route.waitForExistence(timeout: Self.uiTimeout), "the new-flight form should open")
        route.tap()
        pickAirport(app, "EGTF")
        pickAirport(app, "LFAC")
        element(app, "airportPickerDoneButton").tap()
        XCTAssertTrue(route.waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(route.label.contains("EGTF → LFAC"), "the route should read EGTF → LFAC, got: \(route.label)")

        element(app, "newFlightNextButton").tap()
        let suggestion = element(app, "peopleSuggestionButton")
        XCTAssertTrue(suggestion.waitForExistence(timeout: Self.uiTimeout),
                      "the people step should suggest a crew from earlier flights")
        suggestion.tap()
        XCTAssertTrue(app.staticTexts["Test Pilot"].waitForExistence(timeout: Self.uiTimeout),
                      "the suggestion should put Test Pilot on the crew")

        element(app, "createFlightButton").tap()
        XCTAssertTrue(app.navigationBars["EGTF > LFAC"].waitForExistence(timeout: Self.uiTimeout),
                      "creating the flight should open it")
        goBack(app)
        XCTAssertTrue(element(app, "flightRow-EGTF-LFAC").waitForExistence(timeout: Self.uiTimeout),
                      "the new flight should be listed as upcoming")
    }

    /// Journey 3: an ICAO flight plan on the clipboard fills the route, and a
    /// registration the app has never seen becomes a new aircraft — once the
    /// flight is created, and not if the import is cancelled.
    @MainActor
    func testPasteFlightPlanFillsRouteAndCreatesAircraft() throws {
        let plan = "(FPL-ZZNEW-ZG-S22T/L-SBDGORVY/LB2-LSGS0800-N0178A110 SAPRE1D SAPRE/N0189F180 IFR L615 DJL A6 SOMDA T11 VATRI B3 BILGO H20 XORBI H40 ABB N20 ELDAX M8 WAFFU Y8 GWC-EGTF0257-PBN/A1B2C2D2L1O2 DOF/260927)"
        let app = launchApp(environment: ["FLYFUN_UITEST_CLIPBOARD": plan])
        openTab(app, "Flights")
        element(app, "addFlightButton").tap()

        let importButton = element(app, "importButton")
        XCTAssertTrue(importButton.waitForExistence(timeout: Self.uiTimeout), "the new-flight form should open")
        importButton.tap()
        let method = element(app, "importMethod-clipboardFPL")
        XCTAssertTrue(method.waitForExistence(timeout: Self.uiTimeout), "the import list should offer the flight plan")
        XCTAssertTrue(method.isEnabled, "a plan on the clipboard should make the method available")
        method.tap()

        XCTAssertTrue(element(app, "importSummary").waitForExistence(timeout: Self.uiTimeout),
                      "the form should confirm what was imported")
        let route = element(app, "newFlightRouteButton")
        XCTAssertTrue(route.label.contains("LSGS → EGTF"), "the plan's route should be filled, got: \(route.label)")
        let aircraft = element(app, "newFlightAircraftPicker")
        scrollTo(app, aircraft)
        XCTAssertTrue(aircraft.label.contains("ZZNEW"),
                      "the unknown registration should be offered and selected, got: \(aircraft.label)")

        // Cancelled, the import leaves nothing behind: the aircraft is only
        // staged until the flight is created.
        element(app, "newFlightCancelButton").tap()
        openTab(app, "Aircraft")
        XCTAssertTrue(element(app, "aircraftRow-ZZ-TEST").waitForExistence(timeout: Self.uiTimeout))
        XCTAssertFalse(element(app, "aircraftRow-ZZNEW").exists,
                       "a cancelled import should not leave its aircraft on file")

        // Created, it is kept.
        openTab(app, "Flights")
        element(app, "addFlightButton").tap()
        XCTAssertTrue(importButton.waitForExistence(timeout: Self.uiTimeout))
        importButton.tap()
        XCTAssertTrue(method.waitForExistence(timeout: Self.uiTimeout))
        method.tap()
        XCTAssertTrue(element(app, "importSummary").waitForExistence(timeout: Self.uiTimeout))
        element(app, "newFlightNextButton").tap()
        element(app, "createFlightButton").tap()
        XCTAssertTrue(app.navigationBars["LSGS > EGTF"].waitForExistence(timeout: Self.uiTimeout),
                      "creating the flight should open it")
        openTab(app, "Aircraft")
        XCTAssertTrue(element(app, "aircraftRow-ZZNEW").waitForExistence(timeout: Self.uiTimeout),
                      "creating the flight should add the imported aircraft")
    }

    /// Journey 4: the schedule is written through the instant *and* the legacy
    /// day + UTC time pair the list (and older app builds) read. Setting a
    /// Paris departure to 00:xx local lands on the previous UTC day under
    /// either DST offset, so the list must show both a new day and a new time.
    @MainActor
    func testScheduleEditCrossingUtcMidnightMovesTheDay() throws {
        let app = launchApp()
        openTab(app, "Flights")

        let row = element(app, "flightRow-LFRM-EGTF")
        XCTAssertTrue(row.waitForExistence(timeout: Self.uiTimeout), "the return leg should be listed")
        let before = row.label
        XCTAssertTrue(before.contains("12:00z"), "the fixture departs at 12:00z, got: \(before)")
        row.tap()

        focusSection(app, "schedule")
        selectFromMenuPicker(app, identifier: "DepartureHourPicker", value: "00")
        goBack(app)

        XCTAssertTrue(row.waitForExistence(timeout: Self.uiTimeout))
        let after = row.label
        let newTime = ["22:00z", "23:00z"].first { after.contains($0) }
        XCTAssertNotNil(newTime, "00:00 in Paris is 22:00z or 23:00z, got: \(after)")
        XCTAssertNotEqual(after.replacingOccurrences(of: newTime ?? "", with: ""),
                          before.replacingOccurrences(of: "12:00z", with: ""),
                          "crossing UTC midnight should move the day as well as the time")
    }

    /// Journey 5: sharing a form sends the flight, aircraft and people it
    /// should — including the passport picked for the airport's region — and
    /// hands the file to the share sheet.
    @MainActor
    func testGenerateFormSendsTheFlight() throws {
        let app = launchApp()
        openLeg(app, "flightRow-EGTF-LFRM")
        focusSection(app, "form-arrival")
        let share = element(app, "shareForm-LFRM-lfrm")
        XCTAssertTrue(share.waitForExistence(timeout: Self.uiTimeout), "LFRM's arrival form should be offered")
        share.tap()

        XCTAssertTrue(waitForShareSheet(app), "the generated form should be handed to the share sheet")

        let request = try capturedRequest(named: "POST-generate")
        XCTAssertEqual(request["airport"] as? String, "LFRM")
        XCTAssertEqual(request["form"] as? String, "lfrm")

        let flight = try XCTUnwrap(request["flight"] as? [String: Any])
        XCTAssertEqual(flight["origin"] as? String, "EGTF")
        XCTAssertEqual(flight["destination"] as? String, "LFRM")
        XCTAssertEqual(flight["departure_time_utc"] as? String, "09:00")
        XCTAssertEqual(flight["contact"] as? String, "Test Pilot", "the responsible person is the contact")

        let aircraft = try XCTUnwrap(request["aircraft"] as? [String: Any])
        XCTAssertEqual(aircraft["registration"] as? String, "ZZ-TEST")

        let crew = try XCTUnwrap(request["crew"] as? [[String: Any]])
        XCTAssertEqual(crew.count, 1)
        XCTAssertEqual(crew.first?["last_name"] as? String, "Pilot")
        XCTAssertEqual(crew.first?["function"] as? String, "Pilot")
        // Test Pilot holds French and British passports; LFRM is Schengen.
        XCTAssertEqual(crew.first?["id_number"] as? String, "FXA000001", "a Schengen airport should get the French passport")
        XCTAssertEqual(crew.first?["nationality"] as? String, "FRA")

        let passengers = try XCTUnwrap(request["passengers"] as? [[String: Any]])
        XCTAssertEqual(passengers.first?["last_name"] as? String, "Passenger")
        XCTAssertEqual(passengers.first?["id_type"] as? String, "Identity card")
    }

    /// Journey 6: a 422 from the server reads as a list of fields a pilot can
    /// fix, not an API path.
    @MainActor
    func testValidationErrorsAreReadable() throws {
        let app = launchApp(environment: ["FLYFUN_MOCK_GENERATE": "422"])
        openLeg(app, "flightRow-EGTF-LFRM")
        focusSection(app, "form-arrival")
        let share = element(app, "shareForm-LFRM-lfrm")
        XCTAssertTrue(share.waitForExistence(timeout: Self.uiTimeout), "LFRM's arrival form should be offered")
        share.tap()

        let error = element(app, "validationError-crew[0].id_number")
        XCTAssertTrue(error.waitForExistence(timeout: Self.uiTimeout), "the validation errors sheet should open")
        XCTAssertTrue(app.staticTexts["Crew 1 — ID Number"].exists,
                      "crew[0].id_number should read as Crew 1 — ID Number")
        XCTAssertTrue(app.staticTexts["Field required"].exists, "the server's reason should be shown")
        XCTAssertTrue(element(app, "validationFix-documentNumber").exists,
                      "a missing ID number should be editable on the passport the form uses")
    }

    /// Journey 6b: a missing value is filled in on the errors sheet and the
    /// form goes out from there, without going back to the flight.
    @MainActor
    func testFixValidationErrorInPlace() throws {
        let app = launchApp(environment: ["FLYFUN_MOCK_REQUIRE_REASON": "1"])
        openLeg(app, "flightRow-EGTF-LFRM")
        focusSection(app, "form-arrival")
        let share = element(app, "shareForm-LFRM-lfrm")
        XCTAssertTrue(share.waitForExistence(timeout: Self.uiTimeout), "LFRM's arrival form should be offered")
        share.tap()

        XCTAssertTrue(element(app, "validationError-extra_fields.reason_for_visit").waitForExistence(timeout: Self.uiTimeout),
                      "the missing reason for visit should be listed")
        selectFromMenuPicker(app, identifier: "validationFix-reasonForVisit", value: "Maintenance")
        element(app, "validationRetryButton").tap()

        XCTAssertTrue(waitForShareSheet(app), "the form should be shared once the reason is filled in")
        let request = try capturedRequest(named: "POST-generate")
        let extras = try XCTUnwrap(request["extra_fields"] as? [String: Any])
        XCTAssertEqual(extras["reason_for_visit"] as? String, "Maintenance",
                       "the reason picked on the errors sheet should be sent")
    }

    /// Journey 7: a person is added with a passport, and the passport's expiry
    /// state shows on its row.
    @MainActor
    func testAddPersonWithPassport() throws {
        let app = launchApp()
        openTab(app, "People")
        element(app, "addPersonMenu").tap()
        let add = element(app, "addPersonButton")
        XCTAssertTrue(add.waitForExistence(timeout: Self.uiTimeout), "the Add menu should offer Add Person")
        add.tap()

        let firstName = app.textFields["personFirstNameField"]
        XCTAssertTrue(firstName.waitForExistence(timeout: Self.uiTimeout), "the person editor should open")
        firstName.tap()
        firstName.typeText("New")
        let lastName = app.textFields["personLastNameField"]
        lastName.tap()
        lastName.typeText("Person")

        let addDocument = element(app, "addDocumentButton")
        scrollTo(app, addDocument)
        addDocument.tap()
        let newDocument = element(app, "documentRow-new")
        XCTAssertTrue(newDocument.waitForExistence(timeout: Self.uiTimeout), "a blank document should be added")
        newDocument.tap()

        let number = app.textFields["documentNumberField"]
        XCTAssertTrue(number.waitForExistence(timeout: Self.uiTimeout), "the document editor should open")
        number.tap()
        number.typeText("DEA123456")
        let country = app.textFields["documentCountryField"]
        country.tap()
        country.typeText("deu")
        // "Set" dates the expiry today, which is already past by the time the row draws.
        app.buttons["Set"].firstMatch.tap()
        goBack(app)

        let passport = element(app, "documentRow-DEU")
        XCTAssertTrue(passport.waitForExistence(timeout: Self.uiTimeout),
                      "the passport should be listed under its issuing country, upper-cased")
        let expiry = passport.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Expires'")).firstMatch
        XCTAssertEqual(expiry.value as? String, "Document expired", "a passport expiring today is expired")

        goBack(app)
        XCTAssertTrue(element(app, "personRow-Person").waitForExistence(timeout: Self.uiTimeout),
                      "New Person should be listed")
    }

    /// Journey 8: return flight, next leg and duplicate each open the new leg
    /// with the route it should have, and each lands in the list.
    @MainActor
    func testReturnNextLegAndDuplicate() throws {
        let app = launchApp()
        openLeg(app, "flightRow-EGTF-LFRM")
        focusSection(app, "actions")

        tapAction(app, "createReturnFlightButton")
        XCTAssertTrue(app.navigationBars["LFRM > EGTF"].waitForExistence(timeout: Self.uiTimeout),
                      "the return flight should swap origin and destination")

        tapAction(app, "createNextLegButton")
        XCTAssertTrue(app.navigationBars["EGTF > ????"].waitForExistence(timeout: Self.uiTimeout),
                      "the next leg should start where the return landed, destination open")

        tapAction(app, "duplicateFlightButton")
        XCTAssertTrue(app.navigationBars["EGTF > ????"].waitForExistence(timeout: Self.uiTimeout),
                      "the duplicate should keep the route")

        goBack(app)
        XCTAssertTrue(element(app, "flightRow-EGTF-LFRM").waitForExistence(timeout: Self.uiTimeout))
        XCTAssertEqual(rowCount(app, "flightRow-LFRM-EGTF"), 2, "the seeded return leg plus the new one")
        XCTAssertEqual(rowCount(app, "flightRow-EGTF-"), 2, "the next leg plus its duplicate")
    }

    // MARK: - Helpers

    /// The first element carrying `identifier`. `.firstMatch` because SwiftUI
    /// copies an identifier onto a view's children, so one id can name several
    /// elements — fine to wait on, but `.tap()` needs exactly one.
    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// List rows carrying `identifier` — counted on buttons, which a
    /// `NavigationLink` row is exactly one of, unlike its copied-down children.
    @MainActor
    private func rowCount(_ app: XCUIApplication, _ identifier: String) -> Int {
        app.buttons.matching(identifier: identifier).count
    }

    @MainActor
    private func openTab(_ app: XCUIApplication, _ title: String) {
        let tab = app.tabBars.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: Self.uiTimeout), "the \(title) tab should be present")
        tab.tap()
    }

    /// Flights tab, then the leg whose row carries `identifier`.
    @MainActor
    private func openLeg(_ app: XCUIApplication, _ identifier: String) {
        openTab(app, "Flights")
        let row = element(app, identifier)
        XCTAssertTrue(row.waitForExistence(timeout: Self.uiTimeout), "\(identifier) should be listed")
        row.tap()
        XCTAssertTrue(element(app, "flightSectionNavBar").waitForExistence(timeout: Self.uiTimeout),
                      "the flight editor should open")
    }

    /// Show one section of the flight editor through its pill, so its rows are
    /// on screen rather than somewhere below the fold of a lazy `Form`. Form
    /// pills only appear once the airport's forms have loaded.
    @MainActor
    private func focusSection(_ app: XCUIApplication, _ id: String) {
        let pill = element(app, "flightSectionPill_\(id)")
        XCTAssertTrue(pill.waitForExistence(timeout: Self.uiTimeout), "the \(id) pill should be offered")
        // The pills scroll sideways; the later ones exist but sit past the
        // screen edge, where a tap has no hit point (nor does `isHittable`
        // answer). Drag the bar by coordinates until the pill is on screen.
        let width = app.windows.firstMatch.frame.maxX
        let origin = app.coordinate(withNormalizedOffset: .zero)
        var drags = 0
        while pill.frame.maxX > width - 8 && drags < 5 {
            let y = pill.frame.midY
            origin.withOffset(CGVector(dx: width - 40, dy: y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 80, dy: y)))
            drags += 1
        }
        pill.tap()
    }

    @MainActor
    private func tapAction(_ app: XCUIApplication, _ identifier: String) {
        let button = element(app, identifier)
        XCTAssertTrue(button.waitForExistence(timeout: Self.uiTimeout), "\(identifier) should be offered")
        button.tap()
    }

    /// With the airport picker open, search for `icao` and take the result. The
    /// picker moves on to the destination by itself once the origin is set.
    @MainActor
    private func pickAirport(_ app: XCUIApplication, _ icao: String) {
        let search = app.textFields["airportSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.uiTimeout), "the airport picker should open")
        search.tap()
        search.typeText(icao)
        let result = element(app, "airportResult-\(icao)")
        XCTAssertTrue(result.waitForExistence(timeout: Self.uiTimeout), "\(icao) should be found")
        result.tap()
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: Self.uiTimeout), "there should be a way back")
        back.tap()
    }

    /// Swipe until a row below the fold of a lazy `Form` exists at all.
    @MainActor
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    /// Pick from a `.menu` `Picker` by its identifier: the rendered label folds
    /// in the current value, so it is no stable selector.
    @MainActor
    private func selectFromMenuPicker(_ app: XCUIApplication, identifier: String, value: String) {
        let picker = app.buttons[identifier].firstMatch
        scrollTo(app, picker)
        XCTAssertTrue(picker.waitForExistence(timeout: Self.uiTimeout), "the \(identifier) picker should be present")
        picker.tap()
        let option = app.buttons[value].firstMatch
        // A long menu opens scrolled to the current value, and its rows off
        // screen are absent from the accessibility tree: whether `value` is
        // reachable depended on how much room the menu got. Scroll it back
        // toward the top until the option exists. The menu is the collection
        // view presented last.
        var swipes = 0
        while !option.waitForExistence(timeout: 2) && swipes < 4 {
            app.collectionViews.allElementsBoundByIndex.last?.swipeDown()
            swipes += 1
        }
        XCTAssertTrue(option.waitForExistence(timeout: Self.uiTimeout), "\(value) should be offered by \(identifier)")
        option.tap()
    }

    /// The system share sheet has no identifier of ours; its activity list is
    /// the stable part of it across iOS releases.
    @MainActor
    private func waitForShareSheet(_ app: XCUIApplication) -> Bool {
        let sheet = app.otherElements["ActivityListView"].firstMatch
        let copy = app.buttons["Copy"].firstMatch
        let deadline = Date().addingTimeInterval(Self.uiTimeout)
        while Date() < deadline {
            if sheet.exists || copy.exists { return true }
            _ = sheet.waitForExistence(timeout: 1)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "share-sheet-missing"
        shot.lifetime = .keepAlways
        add(shot)
        return false
    }

    /// The JSON body of the latest captured request whose file name contains
    /// `name` (`<n>-<METHOD>-<path>.json`, see `UITestURLProtocol.capture`).
    private func capturedRequest(named name: String) throws -> [String: Any] {
        let files = try FileManager.default.contentsOfDirectory(atPath: captureDirectory.path)
            .filter { $0.contains(name) }
            .sorted()
        let latest = try XCTUnwrap(files.last, "no \(name) request was captured; captured: \(files)")
        let data = try Data(contentsOf: captureDirectory.appendingPathComponent(latest))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

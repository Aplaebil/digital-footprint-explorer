// [01] The connection stays in place until the person makes a clear choice in the confirmation

import XCTest

@MainActor
final class ConnectionConfirmationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    // [02] Cancelling must leave both the saved days and the existing connection in place.
    func testDisconnectAlertKeepsSavedDaysAndConnectionWhenCancelled() throws {
        try checkConfirmation(largeText: false, dark: false)
    }

    // [03] A dark screen and larger text should still leave both confirmation choices readable and
    // reachable.
    func testLargestTextDarkDisconnectAlertKeepsBothChoicesReadable() throws {
        try checkConfirmation(largeText: true, dark: true)
    }

    private func checkConfirmation(largeText: Bool, dark: Bool) throws {
        let app = openFixture(largeText: largeText, dark: dark)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        let savedTotal = app.staticTexts["footprint.total"].label
        assertSavedConnection(in: app, savedTotal: savedTotal)

        let first = openConfirmation(in: app)
        assertChoices(in: first.alert)
        let geometry = XCTAttachment(string: "Message: \(first.alert.staticTexts[confirmationMessage].frame). Cancel: \(action("Cancel", in: first.alert).frame). Disconnect: \(action("Disconnect", in: first.alert).frame). Alert: \(first.alert.frame). Window: \(app.windows.firstMatch.frame).")
        geometry.name = largeText ? "Native alert AX5 geometry" : "Native alert normal geometry"
        geometry.lifetime = .keepAlways
        XCTContext.runActivity(named: "Record native alert layout") { $0.add(geometry) }
        AutomaticUITestSupport.capture(largeText ? "AX5 dark native disconnect alert" : "Light native disconnect alert")
        AutomaticUITestSupport.captureElement(first.alert,
            name: largeText ? "native Disconnect alert, large SwiftUI text" : "native Disconnect alert, normal text")
        try auditConfirmation(in: app)

        // [04] While confirmation is open, a tap behind it must not change tabs or escape the
        // decision.
        first.backgroundHistory.tap()
        XCTAssertTrue(first.alert.exists)
        assertChoices(in: first.alert)
        action("Cancel", in: first.alert).tap()
        assertDismissed(first.alert)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected,
                      "The alert must block interaction with the tab bar behind it")
        assertSavedConnection(in: app, savedTotal: savedTotal)

        let confirmed = openConfirmation(in: app)
        action("Disconnect", in: confirmed.alert).tap()
        assertDismissed(confirmed.alert)
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertEqual(status.label, "Not connected",
                       "Only the explicit destructive action changes the isolated preview state")
        XCTAssertFalse(AutomaticUITestSupport.element("screen-time-disconnect", in: app).exists)
        XCTAssertTrue(AutomaticUITestSupport.reachSettings("settings.automaticSetup", in: app).exists)
        assertSavedTotal(in: app, savedTotal: savedTotal)
        AutomaticUITestSupport.assertNoManualEntry(in: app)

        app.terminate()
        let reopened = openFixture(reset: false, largeText: largeText, dark: dark)
        XCTAssertTrue(reopened.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        XCTAssertEqual(reopened.staticTexts["footprint.total"].label, savedTotal,
                       "Disconnect must keep the saved archive without reseeding it")
        // [05] The test connection exists only in memory, so this confirmation cannot revoke the
        // owner's real access.
        assertSavedConnection(in: reopened, savedTotal: savedTotal)
    }

    private let confirmationMessage = "Automatic estimates will pause. Your saved days will stay on this iPhone."
    private typealias Confirmation = (alert: XCUIElement, backgroundHistory: XCUICoordinate)

    @discardableResult
    private func showSettings(in app: XCUIApplication) -> XCUIElement {
        let tab = app.tabBars.buttons["Settings"]
        let bar = app.navigationBars["Settings"]
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        if !(tab.isSelected && bar.exists && settings.exists && settings.isHittable) {
            tab.tap()
        }
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        XCTAssertTrue(tab.isSelected)
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        return settings
    }

    private func openConfirmation(in app: XCUIApplication) -> Confirmation {
        let settings = showSettings(in: app)
        let entry = AutomaticUITestSupport.element("screen-time-disconnect", in: settings)
        if !entry.exists {
            AutomaticUITestSupport.reachSettings("screen-time.management", in: app).tap()
        }
        AutomaticUITestSupport.reach(entry, in: app, inside: settings,
                                     below: app.navigationBars["Settings"], verticalMargin: 16)
        XCTAssertTrue(entry.isHittable)
        let history = app.tabBars.buttons["History"].frame
        let window = app.windows.firstMatch
        let backgroundHistory = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: history.midX - window.frame.minX, dy: history.midY - window.frame.minY))
        entry.tap()
        let alert = app.alerts["Disconnect Screen Time?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts[confirmationMessage].exists)
        XCTAssertEqual(app.alerts.count, 1)
        XCTAssertEqual(app.sheets.count, 0, "This decision is a centered native alert, not a sheet")
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        return (alert, backgroundHistory)
    }

    private func assertChoices(in alert: XCUIElement) {
        let buttons = alert.buttons.allElementsBoundByIndex
        let inventory = buttons.enumerated().map { index, button in
            "\(index): label=\(button.label); identifier=\(button.identifier); frame=\(button.frame); hittable=\(button.isHittable)"
        }.joined(separator: "\n")
        let diagnostic = XCTAttachment(string: "\(inventory)\n\n\(alert.debugDescription)")
        diagnostic.name = "Native disconnect alert action inventory before strict assertion"
        diagnostic.lifetime = .keepAlways
        self.add(diagnostic)
        AutomaticUITestSupport.capture("Native disconnect alert before strict action inventory")
        let titles = ["Cancel", "Disconnect"]
        XCTAssertEqual(Set(buttons.map(\.label)), Set(titles))
        // [06] iOS exposes more than one test entry for the same visible action; they must share
        // the same position.
        let physicalActions = Set(buttons.map { "\($0.label)|\($0.frame)" })
        XCTAssertEqual(physicalActions.count, 2, "Only two physical action targets should be present")
        for title in titles {
            let button = action(title, in: alert)
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }

    private func action(_ title: String, in alert: XCUIElement) -> XCUIElement {
        alert.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func assertDismissed(_ alert: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !alert.exists }, object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
    }

    private func assertSavedConnection(in app: XCUIApplication, savedTotal: String) {
        showSettings(in: app)
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertEqual(status.label, "Connected")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        assertSavedTotal(in: app, savedTotal: savedTotal)
    }

    private func assertSavedTotal(in app: XCUIApplication, savedTotal: String) {
        let tab = app.tabBars.buttons["Today"]
        let bar = app.navigationBars["Today"]
        let total = app.staticTexts["footprint.total"]
        if !(tab.isSelected && bar.exists && total.exists && total.isHittable) {
            tab.tap()
        }
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        XCTAssertTrue(tab.isSelected)
        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertEqual(total.label, savedTotal)
    }

    private func auditConfirmation(in app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion]) { issue in
            let detail = XCTAttachment(string: "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No affected element supplied")\n\(app.debugDescription)")
            detail.name = "Native disconnect alert accessibility issue and viewport"
            detail.lifetime = .keepAlways
            XCTContext.runActivity(named: "Native disconnect alert accessibility diagnosis") { $0.add(detail) }
            return false
        }
    }

    private func openFixture(reset: Bool = true, largeText: Bool, dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        // [07] These launch choices use disposable history and leave Apple's real permission
        // untouched.
        app.launchArguments = ["-ui-testing", "-ui-automatic-preview", "-ui-disconnect-preview"]
            + (reset ? ["-reset-ui-state", "-ui-reset-appearance", "-ui-example-history"] : [])
            + (largeText ? ["-ui-extra-large-text"] : [])
            + (dark ? ["-ui-dark-mode"] : [])
        app.launch()
        return app
    }
}

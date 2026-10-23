// [01] Shared navigation helpers use a separate archive so screen checks never edit the owner's
// real history

import XCTest

@MainActor
enum AutomaticUITestSupport {
    static func open(reset: Bool = true, fixture: Bool = false, legacyToday: Bool = false,
                     largeText: Bool = false, dark: Bool = false, preview: Bool = true,
                     refreshTesting: Bool = false, revokedPreview: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // [02] Every example uses separate history, so these navigation tests never read the
        // person's Screen Time.
        app.launchArguments = ["-ui-testing"] + (reset ? ["-reset-ui-state", "-ui-reset-appearance"] : [])
            + (fixture ? ["-ui-example-history"] : [])
            + (legacyToday ? ["-ui-legacy-today"] : [])
            + (largeText ? ["-ui-extra-large-text"] : [])
            + (dark ? ["-ui-dark-mode"] : [])
            + (preview ? ["-ui-automatic-preview"] : [])
            + (refreshTesting ? ["-ui-refresh-test"] : [])
            + (revokedPreview ? ["-ui-revoked-preview"] : [])
        app.launch()
        return app
    }

    static func element(_ id: String, in container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    static func reachSettings(_ id: String, in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        let form = element("settings.form", in: app)
        // [03] Look only in the visible Settings page, or a hidden tab could answer for the wrong
        // screen.
        let target = element(id, in: form)
        reach(target, in: app, inside: form, below: app.navigationBars["Settings"], verticalMargin: 16)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        return target
    }

    static func reach(_ element: XCUIElement, in app: XCUIApplication,
                      inside scopedContainer: XCUIElement? = nil,
                      below scopedNavigationBar: XCUIElement? = nil,
                      verticalMargin: CGFloat = 4) {
        var recordedViewport = false
        var searchDirection = 1.0
        var searchSteps = 0
        var searchLimit = 4
        for _ in 0..<60 {
            let window = app.windows.firstMatch
            let bars: [XCUIElement]
            let container: XCUIElement
            if let scopedContainer {
                // [04] Scroll the open sheet itself. Dragging the page behind it could dismiss the
                // sheet and hide a navigation problem.
                guard scopedContainer.exists, let scopedNavigationBar,
                      scopedNavigationBar.exists else {
                    XCTFail("The requested sheet must stay open while reading its content")
                    return
                }
                container = scopedContainer
                bars = [scopedNavigationBar] + app.tabBars.allElementsBoundByIndex
            } else {
                bars = app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
                let candidates = Array(app.collectionViews.allElementsBoundByIndex.reversed())
                    + Array(app.tables.allElementsBoundByIndex.reversed())
                    + Array(app.scrollViews.allElementsBoundByIndex.reversed())
                container = candidates.first { $0.exists && $0.isHittable && $0.frame.intersects(window.frame) } ?? window
            }
            let frame = container.frame
            var visible = frame.intersection(window.frame)
            for bar in bars where bar.exists && bar.isHittable && bar.frame.intersects(visible) {
                if bar.frame.midY < visible.midY {
                    let top = max(visible.minY, bar.frame.maxY)
                    visible = CGRect(x: visible.minX, y: top, width: visible.width, height: visible.maxY - top)
                } else {
                    visible.size.height = min(visible.maxY, bar.frame.minY) - visible.minY
                }
            }
            visible = visible.insetBy(dx: 4, dy: verticalMargin)
            // [05] Read one stable view of the row, since iOS may remove an offscreen row before
            // the next check.
            let targetFrame = element.exists ? (try? element.snapshot())?.frame : nil
            if let targetFrame, element.isHittable {
                let inBar = bars.contains { $0.exists && $0.isHittable && $0.frame.insetBy(dx: -1, dy: -1).contains(targetFrame) }
                if inBar || visible.insetBy(dx: -1, dy: -1).contains(targetFrame) { return }
                // [06] A large-text row may be taller than the screen, but it still needs a usable
                // touch area. Ordinary buttons should fit fully.
                let shown = targetFrame.intersection(visible)
                if targetFrame.height > visible.height,
                   shown.height >= 44, shown.width >= min(44, targetFrame.width),
                   targetFrame.minX >= visible.minX - 1,
                   targetFrame.maxX <= visible.maxX + 1 { return }
            }
            XCTAssertGreaterThan(visible.height, 44)
            if !recordedViewport {
                recordedViewport = true
                let diagnostics = XCTAttachment(string: app.debugDescription)
                diagnostics.name = "Viewport before scrolling to requested content"
                diagnostics.lifetime = .keepAlways
                XCTContext.runActivity(named: "Scroll viewport diagnostics") { $0.add(diagnostics) }
            }
            let offset: Double
            if let targetFrame, !targetFrame.isEmpty {
                offset = targetFrame.midY - visible.midY
                searchDirection = offset < 0 ? -1 : 1
                searchSteps = 0
                searchLimit = 4
            } else {
                // [07] An offscreen row may have no reported position. Search both ways so the
                // test does not get stuck at one end.
                if searchSteps >= searchLimit {
                    searchDirection *= -1
                    searchSteps = 0
                    searchLimit = min(16, searchLimit * 2)
                }
                searchSteps += 1
                offset = visible.height * 0.5 * searchDirection
            }
            let movement = max(-visible.height * 0.55, min(visible.height * 0.55, offset))
            let minimumTravel = min(64, visible.height * 0.75)
            let distance = max(minimumTravel, abs(movement)) * (movement < 0 ? -1.0 : 1.0)
            // [08] Use a normal scroll and let it settle, so a small button is not carried past
            // the visible area.
            let x = visible.midX
            // [09] Start the gesture from the stable window so a hidden tab cannot change the page
            // while the test prepares a drag.
            let windowFrame = window.frame
            let start = window.coordinate(withNormalizedOffset: CGVector(
                dx: (x - windowFrame.minX) / windowFrame.width,
                dy: (visible.midY + distance / 2 - windowFrame.minY) / windowFrame.height))
            let end = window.coordinate(withNormalizedOffset: CGVector(
                dx: (x - windowFrame.minX) / windowFrame.width,
                dy: (visible.midY - distance / 2 - windowFrame.minY) / windowFrame.height))
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        // [10] Keep the failed screen area and control for review; do not make the check easier
        // just to pass.
        let diagnostics = XCTAttachment(string: "Requested element: \(element.debugDescription)\n\(app.debugDescription)")
        diagnostics.name = "Unreachable UI element and viewport"
        diagnostics.lifetime = .keepAlways
        XCTContext.runActivity(named: "Unreachable UI element diagnostics") { $0.add(diagnostics) }
        XCTAssertTrue(element.exists, "The requested content must exist")
        XCTAssertTrue(element.isHittable, "The requested content must remain reachable")
        XCTFail("The requested content did not become fully visible")
    }

    static func assertNoManualEntry(in app: XCUIApplication) {
        for id in ["onboarding.setup", "today.edit", "history.edit", "settings.editRoutine", "automatic.review", "automatic.manual"] {
            XCTAssertFalse(app.buttons[id].exists, "Manual input route remains: \(id)")
        }
        for label in ["Add today's entry", "Edit today's use", "Edit my routine", "Set up my routine"] {
            XCTAssertFalse(app.buttons[label].exists, "Manual input action remains visible")
        }
        XCTAssertFalse(app.scrollViews["input.editor"].exists)
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "input.preset.")).count, 0)
    }

    static func openSetup(in app: XCUIApplication, id: String = "onboarding.automatic") {
        let action: XCUIElement
        if id.hasPrefix("settings.") {
            let management = element("screen-time.management", in: element("settings.form", in: app))
            if id == "settings.automaticSetup", management.exists,
               !element(id, in: element("settings.form", in: app)).exists {
                reachSettings("screen-time.management", in: app).tap()
            }
            action = reachSettings(id, in: app)
        }
        else {
            action = app.buttons[id]
            reach(action, in: app)
        }
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        action.tap()
        XCTAssertTrue(app.navigationBars["Automatic setup"].waitForExistence(timeout: 8))
    }

    static func openHistoryDay(in app: XCUIApplication) {
        app.tabBars.buttons["History"].tap()
        let bar = app.navigationBars["History"]
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        let content = element("history.content", in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        let row = content.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.day.")).firstMatch
        // [11] Find the day on the visible page before scrolling, so a hidden retained row cannot
        // open the wrong view.
        reach(row, in: app, inside: content, below: bar, verticalMargin: 16)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        row.tap()
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
    }

    static func captureElement(_ element: XCUIElement, name: String) {
        guard element.exists && element.isHittable else {
            XCTFail("The DFE component must be visible before its review image is captured")
            return
        }
        // [12] Capture only the component, leaving the phone's status bar and unrelated
        // notifications out of the report.
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = "DFE-only " + name + " (isolated synthetic UI data)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Review DFE component: " + name) { $0.add(attachment) }
    }

    static func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name + " (isolated synthetic UI data)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}

@MainActor
final class AutomaticReadOnlyFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [13] Once setup is saved, Today should focus on the garden while connection controls remain
    // in Settings.
    func testSavedAutomaticSetupStaysAvailableOnlyInSettings() {
        let app = AutomaticUITestSupport.open(fixture: true)
        let latest = AutomaticUITestSupport.element("today.latestResult", in: app)
        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        app.tabBars.buttons["Settings"].tap()
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertEqual(status.label, "Connected")
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        XCTAssertFalse(AutomaticUITestSupport.element("settings.automaticSetup", in: settings).exists)
        XCTAssertTrue(AutomaticUITestSupport.reachSettings("screen-time.management", in: app).exists)
        XCTAssertTrue(AutomaticUITestSupport.reachSettings("settings.modelDetails", in: app).exists)
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }

    // [14] Older results must stay readable without bringing manual entry back into the automatic
    // experience.
    func testLegacyResultsRemainReadableWithoutRestoringManualEditing() {
        let app = AutomaticUITestSupport.open(fixture: true, legacyToday: true)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        for title in ["Today", "History", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists)
            XCTAssertTrue(app.tabBars.buttons[title].isHittable)
        }
        AutomaticUITestSupport.openHistoryDay(in: app)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture("Read-only legacy result")
    }

    // [15] Settings should explain connection and privacy without repeating widget setup already
    // offered on Today.
    func testSettingsShowsConnectionAndPrivacyWithoutRepeatedWidgetSetup() {
        let app = AutomaticUITestSupport.open(fixture: true)
        app.tabBars.buttons["Settings"].tap()
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertFalse(status.label.isEmpty)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        XCTAssertFalse(AutomaticUITestSupport.element("settings.widgetHelp", in: app).exists)
        let privacy = AutomaticUITestSupport.reachSettings("settings.privacy", in: app)
        XCTAssertGreaterThanOrEqual(privacy.frame.height, 44)
    }
}

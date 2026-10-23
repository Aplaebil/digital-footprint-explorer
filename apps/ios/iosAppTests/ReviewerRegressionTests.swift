// [01] Saved clock times cannot always show which deliberate edit happened last. Keep the person's
// actual order

import XCTest
@testable import DFE

final class ReviewerRegressionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
    private func inputs(_ minutes: Double) -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes,
                                               gigabytesPerHour: 1, wifiShare: 0.8)],
                        brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    }
    @MainActor private func makeStore() -> FootprintStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FootprintStore(fileURL: directory.appendingPathComponent("history.json"),
                              calculator: SharedFootprintCalculator(), calendar: calendar)
    }

    // [02] Turning the phone's clock back should not undo the routine change the person made most
    // recently.
    @MainActor func testSameDayClockRollbackKeepsLatestExplicitRoutineEdit() async throws {
        let store = makeStore()
        try store.saveProfile(inputs(60), now: date("2026-10-07T10:00:00Z"))
        // [03] The edit happens later in the app, even though the system clock moved back.
        try store.saveProfile(inputs(120), now: date("2026-10-07T09:00:00Z"))
        XCTAssertEqual(store.archive?.revisions.last?.inputs.totalMinutes, 120)
        try store.catchUp(now: date("2026-10-09T10:00:00Z"))
        let followingDay = try XCTUnwrap(store.records.first { $0.day == "2026-10-08" })
        XCTAssertEqual(followingDay.inputs.totalMinutes, 120)
        XCTAssertEqual(followingDay.source, .routineEstimate)
        // [04] The original explicit daily entry is preserved when a routine changes.
        XCTAssertEqual(store.records.first?.inputs.totalMinutes, 60)
        let reopened = FootprintStore(fileURL: store.fileURL, calculator: SharedFootprintCalculator(), calendar: calendar)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.archive?.revisions.last?.inputs.totalMinutes, 120)
        XCTAssertEqual(reopened.records, store.records)
    }

    // [05] Two edits with the same saved time should keep their actual order after the file is
    // reopened.
    @MainActor func testSameTimestampRoutineEditsKeepInsertionOrderAfterReload() async throws {
        let store = makeStore()
        let now = date("2026-10-07T10:00:00Z")
        try store.saveProfile(inputs(60), now: now)
        try store.saveProfile(inputs(90), now: now)
        try store.saveProfile(inputs(120), now: now)
        let reopened = FootprintStore(fileURL: store.fileURL, calculator: SharedFootprintCalculator(), calendar: calendar)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.archive?.revisions.map { $0.inputs.totalMinutes }, [60, 90, 120])
        try reopened.catchUp(now: date("2026-10-09T10:00:00Z"))
        XCTAssertEqual(reopened.records.first { $0.day == "2026-10-08" }?.inputs.totalMinutes, 120)
    }
}

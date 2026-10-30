/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

// [01] A morning notice needs a relevant result, private wording and a reliable one-per-day limit

import XCTest
import UserNotifications
@testable import DFE

private final class MemoryGardenNotificationLedger: GardenNotificationLedgerStore, @unchecked Sendable {
    enum Failure: Error { case damaged }
    private let lock = NSLock()
    private var value = DailyGardenNotificationLedger()
    var refusesReads = false
    func load() throws -> DailyGardenNotificationLedger {
        lock.lock(); defer { lock.unlock() }
        if refusesReads { throw Failure.damaged }
        return value
    }
    func save(_ ledger: DailyGardenNotificationLedger) throws {
        lock.lock(); defer { lock.unlock() }
        value = ledger
    }
}

private actor MemoryGardenNotificationClient: GardenNotificationClient {
    enum Failure: Error { case uncertainAdd }
    var authorized = true
    var refuseAdd = false
    var identifiers: [String] = []
    var pendingPlans: [DailyGardenNotificationPlan] = []
    var scheduled: [DailyGardenNotificationPlan] = []
    var removed: [String] = []
        func isAuthorized() async -> Bool { await Task.yield(); return authorized }
    func requestState() async -> GardenNotificationRequestState {
        GardenNotificationRequestState(pendingIdentifiers: pendingPlans.map(\.identifier), deliveredIdentifiers: identifiers)
    }
    func add(_ plan: DailyGardenNotificationPlan) async throws {
        await Task.yield()
        if refuseAdd { throw Failure.uncertainAdd }
        scheduled.append(plan)
        pendingPlans.removeAll { $0.identifier == plan.identifier }
        if plan.deliverAt > Date.distantPast { pendingPlans.append(plan) }
    }
    func remove(identifiers values: [String]) async {
        removed += values
        pendingPlans.removeAll { values.contains($0.identifier) }
    }
    func configure(authorized: Bool = true, refuseAdd: Bool = false, identifiers: [String] = []) {
        self.authorized = authorized
        self.refuseAdd = refuseAdd
        self.identifiers = identifiers
    }
    func setPending(_ plans: [DailyGardenNotificationPlan]) { pendingPlans = plans }
    func snapshot() -> (scheduled: [DailyGardenNotificationPlan], removed: [String], identifiers: [String]) {
        (scheduled, removed, identifiers)
    }
}

final class DailyGardenNotificationTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func calendar(_ zone: String = "Europe/Zurich") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func record(day: String = "2026-10-20", garden: FootprintGarden = .growing,
                        minutes: Double = 20, total: Double = 0.08, baseline: Double? = 0.1) -> FootprintRecord {
        FootprintRecord(day: day,
            inputs: FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes)],
                brightness: 0.5, gpsHours: 0, bluetoothHours: 0),
            result: FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0, backgroundKg: 0, categories: []),
            source: .screenTimeWithEstimates, calculatedAt: date("2026-10-21T06:00:00Z"),
            isCompleted: true, garden: garden, baselineKg: baseline, automaticCategories: [.video])
    }
    private func plan(now: Date? = nil) throws -> DailyGardenNotificationPlan {
        try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: now ?? date("2026-10-21T07:00:00Z"), recordCalendar: calendar(), deliveryCalendar: calendar()))
    }

    // [02] Morning follows the person's local clock, even on the days when the clocks move forward
    // or back.
    func testMorningUsesLocalEightAcrossBothDaylightSavingChanges() throws {
        for (day, beforeEight, atEight) in [
            ("2026-03-28", "2026-03-29T05:59:00Z", "2026-03-29T06:00:00Z"),
            ("2026-10-24", "2026-10-25T06:59:00Z", "2026-10-25T07:00:00Z")
        ] {
            XCTAssertNil(DailyGardenNotificationPlan.make(records: [record(day: day)],
                automaticAccessReady: true, now: date(beforeEight), recordCalendar: calendar(), deliveryCalendar: calendar()))
            let result = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record(day: day)],
                automaticAccessReady: true, now: date(atEight), recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertEqual(result.deliverAt, date(atEight))
            XCTAssertEqual(result.recordDay, day)
        }
    }

    // [03] A notice needs a complete, usable automatic day. Missing or invalid activity is not a
    // reason to announce a result.
    func testOnlyACompleteValidYesterdayWithActualAutomaticUseCanProduceNotice() {
        let now = date("2026-10-21T07:00:00Z")
        var incomplete = record(); incomplete.isCompleted = false
        var manual = record(); manual.source = .manual
        var noProvenCategories = record(); noProvenCategories.automaticCategories = nil
        let candidates: [[FootprintRecord]] = [[], [incomplete], [manual], [noProvenCategories],
            [record(day: "2026-10-19")], [record(day: "2026-10-21")],
            [record(minutes: 0)], [record(total: 0)], [record(total: .nan)], [record(minutes: -1)]]
        for records in candidates {
            XCTAssertNil(DailyGardenNotificationPlan.make(records: records,
                automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
        }
        XCTAssertNil(DailyGardenNotificationPlan.make(records: [record()],
            automaticAccessReady: false, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
    }

    // [04] A late import should not interrupt someone at night just to catch up on a morning
    // message.
    func testLateImportStaysQuietInsteadOfSendingAtNight() throws {
        XCTAssertNil(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: date("2026-10-21T18:00:00Z"), recordCalendar: calendar(), deliveryCalendar: calendar()))
        let lateMorning = try plan(now: date("2026-10-21T09:00:00Z"))
        XCTAssertEqual(lateMorning.deliverAt, date("2026-10-21T09:00:00Z"))
    }

    // [25] A day saved before breakfast still needs a fresh morning check. If Apple is briefly
    // unavailable at eight, keep one later chance instead of waiting until tomorrow.
    func testSavedBeforeEightRetriesPendingMorningImportThenNotifiesOnce() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let days = calendar()
        let beforeEight = date("2026-10-21T05:00:00Z")
        let atEight = date("2026-10-21T06:00:00Z")
        let atNine = date("2026-10-21T07:00:00Z")
        let saved = record()
        let savedDates = [try XCTUnwrap(FootprintCalendar(calendar: days).date(saved.day))]

        let earlyPlan = DailyGardenNotificationPlan.make(records: [saved], automaticAccessReady: true,
            now: beforeEight, recordCalendar: days, deliveryCalendar: days)
        XCTAssertNil(earlyPlan)
        let earlyResult = try await coordinator.submit(earlyPlan)
        XCTAssertEqual(earlyResult, .noEligibleDay)
        XCTAssertEqual(BackgroundSchedule.nextAttempt(after: beforeEight, importEligible: true,
            completedDates: savedDates, calendar: days, deliveryCalendar: days), atEight)

        let pending = ScreenTimeRefreshResult(attemptedDays: 1, pendingDays: 1)
        XCTAssertFalse(pending.canNotifyLatestCompletedDay)
        let morningCandidate = DailyGardenNotificationPlan.make(records: [saved], automaticAccessReady: true,
            now: atEight, recordCalendar: days, deliveryCalendar: days)
        let retryNeeded = try await coordinator.needsRetry(for: morningCandidate)
        XCTAssertTrue(retryNeeded)
        XCTAssertEqual(BackgroundSchedule.nextAttempt(after: atEight, importEligible: true,
            completedDates: savedDates, notificationRetryNeeded: retryNeeded,
            calendar: days, deliveryCalendar: days), atNine,
            "A temporarily unavailable fresh check must keep a chance for this morning's notice")
        var state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty, "The old saved day must not be announced after a failed check")

        let fresh = ScreenTimeRefreshResult(attemptedDays: 1, importedDays: 1,
            latestCompletedDayRefreshed: true)
        XCTAssertTrue(fresh.canNotifyLatestCompletedDay)
        let refreshedPlan = DailyGardenNotificationPlan.make(records: [saved], automaticAccessReady: true,
            now: atNine, recordCalendar: days, deliveryCalendar: days)
        let first = try await coordinator.submit(refreshedPlan)
        let duplicate = try await coordinator.submit(refreshedPlan)
        XCTAssertEqual(first, .scheduled)
        XCTAssertEqual(duplicate, .alreadyReserved)
        state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
        let retryAfterSending = try await coordinator.needsRetry(for: refreshedPlan)
        XCTAssertFalse(retryAfterSending)
        XCTAssertEqual(BackgroundSchedule.nextAttempt(after: atNine, importEligible: true,
            completedDates: savedDates, notificationRetryNeeded: retryAfterSending,
            calendar: days, deliveryCalendar: days), date("2026-10-22T06:00:00Z"))
    }

    // [26] Another data check is useful only while the person wants notices and iOS permits them.
    // A reserved morning must not start a fresh round of retries.
    func testMorningRetryStopsWhenDisabledDeniedOrAlreadyReserved() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let candidate = try plan()
        let disabled = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(disabled)
        try await coordinator.setEnabled(true)
        await client.configure(authorized: false)
        let denied = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(denied)
        await client.configure()
        let eligible = try await coordinator.needsRetry(for: candidate)
        XCTAssertTrue(eligible)
        let sent = try await coordinator.submit(candidate)
        XCTAssertEqual(sent, .scheduled)
        let reserved = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(reserved)
        for retryNeeded in [disabled, denied, reserved] {
            XCTAssertEqual(BackgroundSchedule.nextAttempt(after: candidate.deliverAt, importEligible: true,
                completedDates: [date("2026-10-20T12:00:00Z")], notificationRetryNeeded: retryNeeded,
                calendar: calendar(), deliveryCalendar: calendar()), date("2026-10-22T06:00:00Z"))
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
    }

    // [27] A notice already held by iOS needs no retry, even if this local record has no date stamp.
    func testKnownSystemNoticeAndIneligibleDayDoNotRequestMorningRetry() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let noDay = try await coordinator.needsRetry(for: nil)
        XCTAssertFalse(noDay)
        let candidate = try plan()
        await client.configure(identifiers: [candidate.identifier])
        let alreadyKnown = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(alreadyKnown)
        XCTAssertTrue(try ledger.load().reservations.isEmpty, "This read must not reserve or send a notice")
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [05] The message should describe the saved garden, without inventing new flowers or a
    // streak.
    func testCopyUsesTheSavedGardenWithoutInventingGrowthOrStreaks() throws {
        let now = date("2026-10-21T07:00:00Z")
        for state in [FootprintGarden.flourishing, .growing, .stable, .wilting, .withered] {
            let result = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record(garden: state)],
                automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertTrue(result.body.lowercased().contains("yesterday"))
            XCTAssertFalse(result.body.contains("streak"))
            XCTAssertFalse(result.body.contains("CO"))
            XCTAssertLessThanOrEqual(result.body.count, 80)
        }
        let first = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record(baseline: nil)],
            automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
        XCTAssertTrue(first.body.contains("daily estimate"))
        XCTAssertFalse(first.body.contains("first"))
        XCTAssertEqual(DailyGardenNotificationPlan.gardenURL, "digitalfootprint://today")
        let transition = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [
            record(), record(day: "2026-10-18", garden: .withered), record(day: "2026-10-19", garden: .stable)
        ], automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
        XCTAssertEqual(transition.title, "Your Garden Has a New Look")
        XCTAssertEqual(transition.body,
                       "Yesterday's estimate was lower than usual. Come see your growing garden.")
    }

    // [06] A gap in history means we cannot honestly call a different-looking garden a change from
    // yesterday.
    func testGapsInHistoryDoNotInventAYesterdayGardenChange() throws {
        let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [
            record(day: "2026-10-18", garden: .stable), record()
        ], automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
            recordCalendar: calendar(), deliveryCalendar: calendar()))
        XCTAssertEqual(candidate.title, "A Little Green Moment")
        XCTAssertFalse(candidate.body.contains("moved"))
    }

    // [07] An earlier manual or incomplete day cannot support a claim about consecutive automatic
    // results.
    func testUnprovenPreviousDaysDoNotInventAnAutomaticGardenChange() throws {
        var manual = record(day: "2026-10-19", garden: .stable); manual.source = .manual
        var incomplete = record(day: "2026-10-19", garden: .stable); incomplete.isCompleted = false
        var unproven = record(day: "2026-10-19", garden: .stable); unproven.automaticCategories = nil
        var invalid = record(day: "2026-10-19", garden: .stable); invalid.inputs.brightness = .nan
        for previous in [manual, incomplete, unproven, invalid] {
            let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [previous, record()],
                automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
                recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertEqual(candidate.title, "A Little Green Moment")
        }
    }

    // [08] A Lock Screen can be seen by other people, so the message avoids app names and private
    // usage details.
    func testNotificationCopyKeepsUsageDetailsOffTheLockScreen() throws {
        let cases: [(state: String, garden: FootprintGarden, total: Double, baseline: Double?, title: String, body: String)] = [
            ("baseline-absent", .stable, 0.08, nil, "A Moment for Your Garden",
             "Yesterday's daily estimate is ready. Come see how your garden looks."),
            ("flourishing", .flourishing, 0.05, 0.1, "Look What's in Bloom",
             "Yesterday's estimate was much lower than usual. Your garden is in bloom."),
            ("growing", .growing, 0.08, 0.1, "A Little Green Moment",
             "Yesterday's estimate was lower than usual. Come see your growing garden."),
            ("stable", .stable, 0.1, 0.1, "Your Garden, Just a Tap Away",
             "Yesterday's estimate stayed close to usual. Take a moment to look around."),
            ("wilting", .wilting, 0.12, 0.1, "A Little Care for Your Garden",
             "Yesterday's estimate was higher than usual. Find one small idea for today."),
            ("withered", .withered, 0.15, 0.1, "A Fresh Day for Your Garden",
             "Yesterday's estimate was much higher than usual. Explore one small change."),
            ("adjacent-transition", .growing, 0.08, 0.1, "Your Garden Has a New Look",
             "Yesterday's estimate was lower than usual. Come see your growing garden.")
        ]
        var previews: [[String: String]] = []
        for item in cases {
            let current = record(garden: item.garden, total: item.total, baseline: item.baseline)
            let records = item.state == "adjacent-transition"
                ? [record(day: "2026-10-19", garden: .stable, total: 0.1), current] : [current]
            let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: records,
                automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
                recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertEqual(candidate.title, item.title)
            XCTAssertEqual(candidate.body, item.body)
            let text = candidate.title + " " + candidate.body
            XCTAssertTrue(text.rangeOfCharacter(from: .decimalDigits) == nil)
            XCTAssertFalse(text.contains(FootprintCategory.video.title))
            XCTAssertFalse(text.contains("kg"))
            XCTAssertLessThanOrEqual(candidate.title.count, 32)
            XCTAssertLessThanOrEqual(candidate.body.count, 80)
            previews.append(["state": item.state, "title": candidate.title, "body": candidate.body,
                             "recordDay": candidate.recordDay, "deliveryDay": candidate.deliveryDay])
        }
        // [09] Preview content comes from the real planner and isolated synthetic records.
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: previews, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "dfe-daily-notification-preview-content"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // [10] When the app is open, the same daily update can appear as a banner and remain in
    // Notification Center.
    func testDailyForegroundNoticeRequestsBannerAndNotificationCenter() {
        let options = GardenNotificationDelegate.foregroundPresentationOptions(
            identifier: DailyGardenNotificationPlan.prefix + "2026-10-21",
            gardenURL: DailyGardenNotificationPlan.gardenURL)
        XCTAssertEqual(options, [.banner, .list])
        XCTAssertFalse(options.contains(.sound))
    }

    // [11] The garden's presentation choice should not make an unrelated notification interrupt
    // the person.
    func testOtherForegroundNotificationsStaySilent() {
        for (identifier, route) in [
            ("another-feature.2026-10-21", DailyGardenNotificationPlan.gardenURL as String?),
            (DailyGardenNotificationPlan.prefix + "2026-10-21", "digitalfootprint://history"),
            (DailyGardenNotificationPlan.prefix + "2026-10-21", nil)
        ] {
            XCTAssertTrue(GardenNotificationDelegate.foregroundPresentationOptions(
                identifier: identifier, gardenURL: route).isEmpty)
        }
    }

    // [12] Opening the app during a background refresh must not cause two notices for the same
    // morning.
    func testConcurrentForegroundAndBackgroundRefreshesScheduleOnlyOneNotice() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { _ = try? await coordinator.submit(candidate) }
            }
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
        XCTAssertEqual(try ledger.load().reservations.count, 1)
    }

    // [13] Reopening or retrying later should remember that today's notification opportunity was
    // already reserved.
    func testRelaunchAndSameDayRetryKeepTheDurableReservation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notice-ledger.json")
        let client = MemoryGardenNotificationClient()
        let firstLedger = FileGardenNotificationLedgerStore(url: file)
        let first = DailyGardenNotificationCoordinator(client: client, ledgerStore: firstLedger)
        try await first.setEnabled(true)
        let candidate = try plan()
        let firstResult = try await first.submit(candidate)
        XCTAssertEqual(firstResult, .scheduled)
        let reopened = DailyGardenNotificationCoordinator(client: client,
            ledgerStore: FileGardenNotificationLedgerStore(url: file))
        let nextResult = try await reopened.submit(candidate)
        XCTAssertEqual(nextResult, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
        XCTAssertTrue(try firstLedger.load().contains(candidate))
    }

    // [14] If scheduling has an uncertain outcome, staying quiet is safer than risking a duplicate
    // notice.
    func testUncertainSchedulingErrorConsumesItsDayRatherThanRiskingDuplicate() async throws {
        let client = MemoryGardenNotificationClient()
        await client.configure(refuseAdd: true)
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        let first = try await coordinator.submit(candidate)
        XCTAssertEqual(first, .schedulingFailed)
        await client.configure()
        let retry = try await coordinator.submit(candidate)
        XCTAssertEqual(retry, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [15] Turning notices off should remove this feature's requests without disturbing unrelated
    // notifications.
    func testPermissionDeniedAndOptOutRemoveOnlyDailyGardenRequests() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let own = DailyGardenNotificationPlan.prefix + "2026-10-21"
        let unrelated = "unrelated-local-feature"
        await client.configure(authorized: false, identifiers: [unrelated])
        await client.setPending([try plan()])
        try await coordinator.setEnabled(true)
        let result = try await coordinator.submit(try plan())
        XCTAssertEqual(result, .denied)
        var state = await client.snapshot()
        XCTAssertEqual(state.removed, [own])
        XCTAssertEqual(state.identifiers, [unrelated])
        await client.configure(identifiers: [unrelated])
        await client.setPending([try plan()])
        try await coordinator.setEnabled(false)
        state = await client.snapshot()
        XCTAssertEqual(state.identifiers, [unrelated])
        let enabled = try await coordinator.isEnabled()
        XCTAssertFalse(enabled)
    }

    // [16] A damaged or disabled notice record is a reason to stop, rather than send without
    // reliable daily limits.
    func testDisabledOrDamagedLedgerNeverPublishesNotification() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let result = try await coordinator.submit(try plan())
        XCTAssertEqual(result, .disabled)
        ledger.refusesReads = true
        do {
            _ = try await coordinator.needsRetry(for: try plan())
            XCTFail("A damaged ledger must stop morning retries too.")
        } catch { }
        do {
            _ = try await coordinator.submit(try plan())
            XCTFail("A damaged ledger must stop scheduling.")
        } catch { }
        await client.setPending([try plan()])
        do { try await coordinator.setEnabled(false) } catch { }
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
        XCTAssertEqual(state.removed, [try plan().identifier])
    }

    // [17] Travel or a clock change must not turn one result into two daily notifications.
    func testTimeZoneOrClockChangeCannotReuseAReservedDayOrRecord() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let original = try plan()
        _ = try await coordinator.submit(original)
        let sameDayInAnotherZone = DailyGardenNotificationPlan(deliveryDay: original.deliveryDay,
            recordDay: "2026-10-19", title: original.title, body: original.body,
            deliverAt: original.deliverAt, timeZoneIdentifier: "America/New_York")
        let shiftedDaySameRecord = DailyGardenNotificationPlan(deliveryDay: "2026-10-22",
            recordDay: original.recordDay, title: original.title, body: original.body,
            deliverAt: original.deliverAt, timeZoneIdentifier: "Pacific/Auckland")
        for candidate in [sameDayInAnotherZone, shiftedDaySameRecord] {
            let outcome = try await coordinator.submit(candidate)
            XCTAssertEqual(outcome, .alreadyReserved)
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
    }

    // [18] A request already known to iOS should be recognized, rather than sent a second time.
    func testExistingPendingOrDeliveredRequestIsAdoptedWithoutRepublishing() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        await client.configure(identifiers: [candidate.identifier])
        let result = try await coordinator.submit(candidate)
        XCTAssertEqual(result, .alreadyReserved)
        XCTAssertTrue(try ledger.load().contains(candidate))
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [19] A saved history date should not force the morning notice to use a time zone the person
    // has left.
    func testDeliveryClockIsLocalEvenWhenTheArchiveUsesAnotherTimeZone() throws {
        let beforeEight = date("2026-10-21T10:59:00Z") // [20] 07:59 in Sao Paulo, 12:59 in Zurich.
        XCTAssertNil(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: beforeEight, recordCalendar: calendar(), deliveryCalendar: calendar("America/Sao_Paulo")))
        let localEight = date("2026-10-21T11:00:00Z")
        let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()],
            automaticAccessReady: true, now: localEight, recordCalendar: calendar(),
            deliveryCalendar: calendar("America/Sao_Paulo")))
        XCTAssertEqual(candidate.deliverAt, localEight)
        XCTAssertEqual(candidate.timeZoneIdentifier, "America/Sao_Paulo")
        XCTAssertNil(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: date("2026-10-21T06:00:00Z"), recordCalendar: calendar(),
            deliveryCalendar: calendar("Pacific/Honolulu")))
    }

    // [21] A valid fresh result for yesterday remains useful even if a separate older-day catch-up
    // fails.
    @MainActor
    func testFreshYesterdayCanNotifyEvenWhenAnOlderBackfillFails() async throws {
        let now = date("2026-10-21T07:00:00Z")
        let days = calendar()
        let today = days.startOfDay(for: now)
        let latest = try XCTUnwrap(days.date(byAdding: .day, value: -1, to: today))
        let importPlan = ScreenTimeImportPlan.make(start: date("2026-10-19T00:00:00Z"),
            today: today, calendar: days, cursor: nil,
            shouldRefreshLatest: { _ in true }, shouldBackfill: { _ in true })
        var saved: [FootprintRecord] = []
        let refresh = try await ScreenTimeCompletedDayImporter.run(dates: importPlan.dates,
            today: today, calendar: days, shouldImport: { _ in true }, importDay: { day in
                if !days.isDate(day, inSameDayAs: latest) { throw CocoaError(.fileReadCorruptFile) }
                saved.append(self.record())
                return ScreenTimeDayImportReceipt(day: day, created: true)
            }, onError: { _ in .error })
        XCTAssertEqual(refresh.attemptedDays, 2)
        XCTAssertEqual(refresh.importedDays, 1)
        XCTAssertFalse(refresh.completedWithoutFatalError)
        XCTAssertTrue(refresh.canNotifyLatestCompletedDay)

        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        if refresh.canNotifyLatestCompletedDay {
            let candidate = DailyGardenNotificationPlan.make(records: saved,
                automaticAccessReady: true, now: now, recordCalendar: days, deliveryCalendar: days)
            let result = try await coordinator.submit(candidate)
            XCTAssertEqual(result, .scheduled)
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1,
                       "A separate older error must not silence yesterday's committed garden")
        XCTAssertEqual(state.scheduled.first?.recordDay, "2026-10-20")
    }

    // [22] Without current access and a fresh import result, an old saved day must not trigger a
    // new notice.
    @MainActor
    func testLostAccessOrUnrefreshedYesterdayCannotNotifyAnOldSavedResult() async throws {
        let days = calendar()
        let today = days.startOfDay(for: date("2026-10-21T07:00:00Z"))
        let latest = try XCTUnwrap(days.date(byAdding: .day, value: -1, to: today))
        let importPlan = ScreenTimeImportPlan.make(start: date("2026-10-19T00:00:00Z"),
            today: today, calendar: days, cursor: nil,
            shouldRefreshLatest: { _ in true }, shouldBackfill: { _ in true })
        let accessLost = try await ScreenTimeCompletedDayImporter.run(dates: importPlan.dates,
            today: today, calendar: days, shouldImport: { _ in true }, importDay: { day in
                if !days.isDate(day, inSameDayAs: latest) { throw ScreenTimeImportError.permissionRequired }
                return ScreenTimeDayImportReceipt(day: day, created: true)
            }, onError: { _ in .noAccess })
        XCTAssertTrue(accessLost.latestCompletedDayRefreshed)
        XCTAssertTrue(accessLost.stoppedForAccess)
        XCTAssertFalse(accessLost.canNotifyLatestCompletedDay)
        let olderOnly = ScreenTimeRefreshResult(attemptedDays: 2, importedDays: 1,
            pendingDays: 1, newRecords: 1)
        XCTAssertFalse(olderOnly.canNotifyLatestCompletedDay)
        XCTAssertFalse(ScreenTimeRefreshResult().canNotifyLatestCompletedDay)
    }

    // [23] Troubleshooting only needs our own valid delivery dates, not other notifications or
    // their contents.
    func testTechnicalNotificationProjectionKeepsOnlyValidOwnDeliveryDates() {
        let prefix = DailyGardenNotificationPlan.prefix
        let projected = GardenNotificationTechnicalSnapshot.deliveryDays(from: [
            prefix + "2026-10-23", "unrelated-2026-10-22", prefix + "2026-02-30",
            prefix + "2026-10-22.private-content", prefix + "2026-10-22"
        ])
        XCTAssertEqual(projected, ["2026-10-22", "2026-10-23"])
        XCTAssertEqual(GardenNotificationTechnicalSnapshot.relativePath,
                       "DFENotificationDiagnostics/state-v1.json")
    }

    // [24] Deleting history resets future notice choices without pretending to erase notifications
    // already delivered.
    func testDeletingHistoryResetsOptInAndReservationsButKeepsDeliveredHistory() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        _ = try await coordinator.submit(candidate)
        await client.configure(identifiers: ["delivered-garden-receipt"])
        try await coordinator.reset()
        let saved = try ledger.load()
        let state = await client.snapshot()
        XCTAssertFalse(saved.enabled)
        XCTAssertTrue(saved.reservations.isEmpty)
        XCTAssertEqual(state.removed, [candidate.identifier])
        XCTAssertEqual(state.identifiers, ["delivered-garden-receipt"])
    }
}

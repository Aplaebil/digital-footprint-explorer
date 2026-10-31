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

import Foundation

extension ScreenTimeRefreshResult {
    /// [01] Yesterday's saved result can have a notice even if an older missing day failed.
    /// Lost data access still blocks both the notice and further importing.
    var canNotifyLatestCompletedDay: Bool {
        latestCompletedDayRefreshed && !stoppedForAccess
    }
}

/// [02] A notice describes one saved day. Missing activity is never a zero-use day.
struct DailyGardenNotificationPlan: Codable, Equatable, Sendable {
    static let prefix = "dfe.garden.daily."
    static let gardenURL = "digitalfootprint://today"
    enum Kind: String, Codable, Sendable { case estimate, reminder }
    var kind: Kind = .estimate
    var scheduledForMorning = false
    let deliveryDay: String
    let recordDay: String
    let title: String
    let body: String
    let deliverAt: Date
    let timeZoneIdentifier: String
    var identifier: String { Self.prefix + deliveryDay }

    // [03] A daily notice needs a complete, valid automatic result for yesterday.
    // No usable activity means no notice; it does not mean the person used nothing.
    static func make(records: [FootprintRecord], automaticAccessReady: Bool, now: Date,
                     recordCalendar: Calendar = FootprintCalendar.localCalendar,
                     deliveryCalendar: Calendar = FootprintCalendar.localCalendar) -> Self? {
        guard automaticAccessReady,
              let yesterday = recordCalendar.date(byAdding: .day, value: -1, to: recordCalendar.startOfDay(for: now)),
              let localYesterday = deliveryCalendar.date(byAdding: .day, value: -1, to: deliveryCalendar.startOfDay(for: now)) else { return nil }
        let recordDays = FootprintCalendar(calendar: recordCalendar)
        let localDays = FootprintCalendar(calendar: deliveryCalendar)
        let yesterdayKey = recordDays.key(yesterday)
        // [04] During travel, wait if the saved day and the person's local yesterday disagree.
        // A day that is still running must not be announced as complete.
        guard yesterdayKey == localDays.key(localYesterday),
              let recordEnd = recordCalendar.date(byAdding: .day, value: 1, to: yesterday),
              recordEnd <= now else { return nil }
        guard let record = records.last(where: { $0.day == yesterdayKey }),
              record.isCompleted, record.source == .screenTimeWithEstimates,
              record.automaticCategories?.isEmpty == false,
              record.inputs.totalMinutes > 0, record.result.totalKg > 0,
              (try? record.inputs.validate()) != nil,
              (try? record.result.validate()) != nil else { return nil }
        // [05] A late import should not wake someone at night or describe an older day as yesterday.
        guard deliveryCalendar.component(.hour, from: now) < 20,
              let morning = deliveryCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) else { return nil }
        // [06] Only yesterday's immediate neighbour can show a day-to-day change.
        // Older gaps or manual entries do not establish an automatic transition.
        let previousKey = recordCalendar.date(byAdding: .day, value: -1, to: yesterday).map(recordDays.key)
        let previous = records.last { candidate in
            candidate.day == previousKey && candidate.isCompleted
                && candidate.source == .screenTimeWithEstimates
                && candidate.automaticCategories?.isEmpty == false
                && (try? candidate.inputs.validate()) != nil
                && (try? candidate.result.validate()) != nil
        }
        let content = message(for: record, previous: previous)
        return Self(scheduledForMorning: now < morning, deliveryDay: localDays.key(now),
            recordDay: record.day, title: content.title, body: content.body,
            deliverAt: max(now, morning), timeZoneIdentifier: deliveryCalendar.timeZone.identifier)
    }

    // [17] Book a few mornings ahead, like leaving dated notes with iOS.
    // The invitation never claims that an estimate has already been calculated.
    static func morningReminders(after now: Date, calendar: Calendar = FootprintCalendar.localCalendar,
                                 count: Int = 30) -> [Self] {
        guard count > 0,
              let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) else { return [] }
        let first = morning > now ? 0 : 1
        let days = FootprintCalendar(calendar: calendar)
        return (first..<(first + min(count, 30))).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: morning) else { return nil }
            return Self(kind: .reminder, scheduledForMorning: true, deliveryDay: days.key(date), recordDay: "",
                title: "A Moment for Your Garden",
                body: "What will your digital day look like? Open your garden to explore your latest estimate.",
                deliverAt: date, timeZoneIdentifier: calendar.timeZone.identifier)
        }
    }

    // [07] Make the invitation match the saved garden. Keep usage details off the lock screen,
    // and describe a change only when the neighbouring automatic day supports it.
    private static func message(for record: FootprintRecord, previous: FootprintRecord?) -> (title: String, body: String) {
        guard let baseline = record.baselineKg, baseline.isFinite, baseline > 0 else {
            return ("A Moment for Your Garden", "Yesterday's daily estimate is ready. Come see how your garden looks.")
        }
        let title: String
        let body: String
        switch record.garden {
        case .flourishing:
            title = "Look What's in Bloom"
            body = "Yesterday's estimate was much lower than usual. Your garden is in bloom."
        case .growing:
            title = "A Little Green Moment"
            body = "Yesterday's estimate was lower than usual. Come see your growing garden."
        case .stable:
            title = "Your Garden, Just a Tap Away"
            body = "Yesterday's estimate stayed close to usual. Take a moment to look around."
        case .wilting:
            title = "A Little Care for Your Garden"
            body = "Yesterday's estimate was higher than usual. Find one small idea for today."
        case .withered:
            title = "A Fresh Day for Your Garden"
            body = "Yesterday's estimate was much higher than usual. Explore one small change."
        }
        if let previous, previous.garden != record.garden {
            return ("Your Garden Has a New Look", body)
        }
        return (title, body)
    }

}

// [08] This small record is like a date stamp: once a day is reserved, another refresh
// cannot send a second notice for the same delivery day or the same result.
struct DailyGardenNotificationLedger: Codable, Equatable, Sendable {
    var enabled = false
    var reservations: [Reservation] = []
    var reminders: [MorningReminder] = []
    struct MorningReminder: Codable, Equatable, Sendable {
        let deliveryDay: String
        let deliverAt: Date
        let timeZoneIdentifier: String

        // [18] A traveller may reach eight o'clock earlier in a new time zone.
        // Count either deadline as used, so a dismissed reminder cannot be followed by a second alert.
        func mayHaveDelivered(at now: Date, calendar: Calendar) -> Bool {
            guard let day = FootprintCalendar(calendar: calendar).date(deliveryDay),
                  let localMorning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) else { return true }
            return deliverAt <= now || localMorning <= now
        }
    }
    struct Reservation: Codable, Equatable, Sendable {
        let deliveryDay: String
        let recordDay: String
        let reservedAt: Date
        let timeZoneIdentifier: String
    }
    func contains(_ plan: DailyGardenNotificationPlan) -> Bool {
        reservations.contains { $0.deliveryDay == plan.deliveryDay || (!plan.recordDay.isEmpty && $0.recordDay == plan.recordDay) }
    }
}

// [19] People keep their existing notice choice when this small record gains reminder dates.
extension DailyGardenNotificationLedger {
    private enum CodingKeys: String, CodingKey { case enabled, reservations, reminders }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        reservations = try values.decode([Reservation].self, forKey: .reservations)
        reminders = try values.decodeIfPresent([MorningReminder].self, forKey: .reminders) ?? []
    }
}

protocol GardenNotificationLedgerStore: Sendable {
    func load() throws -> DailyGardenNotificationLedger
    func save(_ ledger: DailyGardenNotificationLedger) throws
}

struct FileGardenNotificationLedgerStore: GardenNotificationLedgerStore {
    let url: URL
    func load() throws -> DailyGardenNotificationLedger {
        guard FileManager.default.fileExists(atPath: url.path) else { return DailyGardenNotificationLedger() }
        // [09] If the notice record cannot be read, stop here. Guessing could send a second alert.
        return try JSONDecoder().decode(DailyGardenNotificationLedger.self, from: Data(contentsOf: url))
    }
    // [10] Replace the whole saved record at once, so an interrupted write does not leave half a date stamp.
    func save(_ ledger: DailyGardenNotificationLedger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(ledger)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

struct GardenNotificationRequestState: Sendable {
    var pendingIdentifiers: [String] = []
    var deliveredIdentifiers: [String] = []
    var identifiers: [String] { pendingIdentifiers + deliveredIdentifiers }
}

protocol GardenNotificationClient: Sendable {
    func isAuthorized() async -> Bool
    func requestState() async -> GardenNotificationRequestState
    func add(_ plan: DailyGardenNotificationPlan) async throws
    func remove(identifiers: [String]) async
}

enum GardenNotificationSubmission: Equatable {
    case disabled, denied, noEligibleDay, alreadyReserved, scheduled, schedulingFailed
}

/// [11] Use one queue for notices from the open app and background work, so their date checks cannot race.
actor DailyGardenNotificationCoordinator {
    private let client: any GardenNotificationClient
    private let ledgerStore: any GardenNotificationLedgerStore
    private var tail: Task<Void, Never>?

    init(client: any GardenNotificationClient, ledgerStore: any GardenNotificationLedgerStore) {
        self.client = client
        self.ledgerStore = ledgerStore
    }

    func isEnabled() throws -> Bool { try ledgerStore.load().enabled }

    // [16] A saved day may still need a fresh morning check. Read the same daily limits
    // used for sending, without reserving a date or publishing the older result.
    func needsRetry(for plan: DailyGardenNotificationPlan?, now: Date = Date(),
                    calendar: Calendar = FootprintCalendar.localCalendar) async throws -> Bool {
        let previous = tail
        let work = Task {
            await previous?.value
            try Task.checkCancellation()
            let ledger = try ledgerStore.load()
            guard ledger.enabled, let plan, !ledger.contains(plan),
                  !ledger.reminders.contains(where: { $0.deliveryDay == plan.deliveryDay && $0.mayHaveDelivered(at: now, calendar: calendar) }),
                  await client.isAuthorized() else { return false }
            let existing = await client.requestState()
            return !existing.identifiers.contains(plan.identifier)
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    func setEnabled(_ enabled: Bool, now: Date = Date(),
                    calendar: Calendar = FootprintCalendar.localCalendar) async throws {
        let previous = tail
        let work = Task {
            await previous?.value
            // [12] Turning notices off must still cancel pending cards if the ledger is damaged.
            if !enabled {
                let state = await client.requestState()
                await client.remove(identifiers: state.pendingIdentifiers.filter { $0.hasPrefix(DailyGardenNotificationPlan.prefix) })
            }
            var ledger = try ledgerStore.load()
            ledger.enabled = enabled
            // [23] Cancellation can finish just after eight. Keep the date stamps even
            // when turning reminders off, in case iOS already displayed that morning's card.
            try ledgerStore.save(ledger)
        }
        tail = Task { _ = try? await work.value }
        try await work.value
    }

    /// [13] Call only after deleting local history and resetting Screen Time setup.
    func reset() async throws {
        let previous = tail
        let work = Task {
            await previous?.value
            let state = await client.requestState()
            await client.remove(identifiers: state.pendingIdentifiers.filter { $0.hasPrefix(DailyGardenNotificationPlan.prefix) })
            try ledgerStore.save(DailyGardenNotificationLedger())
        }
        tail = Task { _ = try? await work.value }
        try await work.value
    }

    // [20] Prepare one dated invitation per morning. iOS can display it even after
    // the person closes DFE; it does not need a new Screen Time query to do so.
    func prepareMorningReminders(now: Date, calendar: Calendar = FootprintCalendar.localCalendar,
                                 days: Int = 30) async throws -> GardenNotificationSubmission {
        let previous = tail
        let work = Task {
            await previous?.value
            try Task.checkCancellation()
            var ledger = try ledgerStore.load()
            guard ledger.enabled else { return GardenNotificationSubmission.disabled }
            var existing = await client.requestState()
            guard await client.isAuthorized() else {
                await client.remove(identifiers: existing.pendingIdentifiers.filter { $0.hasPrefix(DailyGardenNotificationPlan.prefix) })
                return .denied
            }
            let plans = DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar, count: days)
            let wanted = Set(plans.map(\.identifier))
            let obsolete = ledger.reminders.filter { reminder in
                !reminder.mayHaveDelivered(at: now, calendar: calendar)
                    && !wanted.contains(DailyGardenNotificationPlan.prefix + reminder.deliveryDay)
                    && !ledger.reservations.contains(where: { $0.deliveryDay == reminder.deliveryDay })
            }
            // [21] Only remove this feature's future placeholders; a delivered date stays stamped.
            let obsoleteIDs = obsolete.map { DailyGardenNotificationPlan.prefix + $0.deliveryDay }
            if !obsoleteIDs.isEmpty {
                await client.remove(identifiers: obsoleteIDs)
                // [24] Replanning cancels pending requests, not their safety record.
                // A future date can still be repaired with the same identifier before it is due.
                existing.pendingIdentifiers.removeAll { obsoleteIDs.contains($0) }
            }
            var changed = false
            var failed = false
            for plan in plans {
                try Task.checkCancellation()
                guard !ledger.contains(plan), !existing.deliveredIdentifiers.contains(plan.identifier) else { continue }
                let slot = ledger.reminders.first { $0.deliveryDay == plan.deliveryDay }
                guard slot?.mayHaveDelivered(at: now, calendar: calendar) != true else { continue }
                let needsNewZone = slot.map { $0.timeZoneIdentifier != plan.timeZoneIdentifier } ?? false
                if existing.pendingIdentifiers.contains(plan.identifier) && !needsNewZone { continue }
                // [22] Save first. If iOS accepts a request just as the app stops, the next launch
                // must still know that this morning may already have had its one invitation.
                ledger.reminders.removeAll { $0.deliveryDay == plan.deliveryDay }
                ledger.reminders.append(.init(deliveryDay: plan.deliveryDay, deliverAt: plan.deliverAt,
                    timeZoneIdentifier: plan.timeZoneIdentifier))
                try ledgerStore.save(ledger)
                do {
                    try Task.checkCancellation()
                    try await client.add(plan)
                    existing.pendingIdentifiers.append(plan.identifier)
                    changed = true
                } catch is CancellationError { throw CancellationError() }
                catch { failed = true }
            }
            return failed ? .schedulingFailed : (changed ? .scheduled : .alreadyReserved)
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    // [14] A fresh result may replace a future invitation with the same identifier.
    // After its deadline, keep the daily limit even if its banner has been dismissed.
    func submit(_ plan: DailyGardenNotificationPlan?, now: Date = Date(),
                calendar: Calendar = FootprintCalendar.localCalendar) async throws -> GardenNotificationSubmission {
        let previous = tail
        let work = Task {
            await previous?.value
            try Task.checkCancellation()
            var ledger = try ledgerStore.load()
            guard ledger.enabled else { return GardenNotificationSubmission.disabled }
            guard await client.isAuthorized() else {
                let state = await client.requestState()
                await client.remove(identifiers: state.pendingIdentifiers.filter { $0.hasPrefix(DailyGardenNotificationPlan.prefix) })
                return .denied
            }
            guard let plan else { return .noEligibleDay }
            let existing = await client.requestState()
            guard !ledger.contains(plan) else { return .alreadyReserved }
            let reminder = ledger.reminders.first { $0.deliveryDay == plan.deliveryDay }
            guard reminder?.mayHaveDelivered(at: now, calendar: calendar) != true else { return .alreadyReserved }
            let canReplace = reminder != nil && plan.scheduledForMorning && plan.deliverAt > now
                && existing.pendingIdentifiers.contains(plan.identifier)
                && !existing.deliveredIdentifiers.contains(plan.identifier)
            guard canReplace || !existing.identifiers.contains(plan.identifier) else {
                ledger.reservations.append(.init(deliveryDay: plan.deliveryDay, recordDay: plan.recordDay,
                    reservedAt: plan.deliverAt, timeZoneIdentifier: plan.timeZoneIdentifier))
                try ledgerStore.save(ledger)
                return .alreadyReserved
            }
            // [15] Save the date stamp before sending. An unclear failure may skip one notice,
            // but trying again must not turn that uncertainty into a second alert.
            try Task.checkCancellation()
            ledger.reservations.append(.init(deliveryDay: plan.deliveryDay, recordDay: plan.recordDay,
                reservedAt: plan.deliverAt, timeZoneIdentifier: plan.timeZoneIdentifier))
            try ledgerStore.save(ledger)
            do {
                try Task.checkCancellation()
                try await client.add(plan)
                return .scheduled
            } catch is CancellationError { throw CancellationError() }
            catch { return .schedulingFailed }
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}

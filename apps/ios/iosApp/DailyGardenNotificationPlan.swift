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
        guard (8..<20).contains(deliveryCalendar.component(.hour, from: now)) else { return nil }
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
        return Self(deliveryDay: localDays.key(now), recordDay: record.day, title: content.title,
            body: content.body, deliverAt: now, timeZoneIdentifier: deliveryCalendar.timeZone.identifier)
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
    struct Reservation: Codable, Equatable, Sendable {
        let deliveryDay: String
        let recordDay: String
        let reservedAt: Date
        let timeZoneIdentifier: String
    }
    func contains(_ plan: DailyGardenNotificationPlan) -> Bool {
        reservations.contains { $0.deliveryDay == plan.deliveryDay || $0.recordDay == plan.recordDay }
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

    func setEnabled(_ enabled: Bool) async throws {
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

    // [14] Check the saved choice, Apple permission and existing notices in one queue.
    // Two refreshes arriving together must not both send the same daily update.
    func submit(_ plan: DailyGardenNotificationPlan?) async throws -> GardenNotificationSubmission {
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
            guard !existing.identifiers.contains(plan.identifier) else {
                ledger.reservations.append(.init(deliveryDay: plan.deliveryDay, recordDay: plan.recordDay,
                    reservedAt: plan.deliverAt, timeZoneIdentifier: plan.timeZoneIdentifier))
                try ledgerStore.save(ledger)
                return .alreadyReserved
            }
            // [15] Save the date stamp before sending. A crash or unclear failure may skip one notice,
            // but trying again must not turn that uncertainty into a second alert.
            try Task.checkCancellation()
            ledger.reservations.append(.init(deliveryDay: plan.deliveryDay, recordDay: plan.recordDay,
                reservedAt: plan.deliverAt, timeZoneIdentifier: plan.timeZoneIdentifier))
            try ledgerStore.save(ledger)
            do {
                try Task.checkCancellation()
                try await client.add(plan)
                return .scheduled
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .schedulingFailed
            }
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }
}

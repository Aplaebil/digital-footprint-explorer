import Foundation
import WidgetKit

protocol WidgetSnapshotPublishing {
    func publish(_ snapshot: GardenWidgetSnapshot?) throws
}

/// [01] The app creates a small summary from saved history.
/// A widget problem must not undo a successfully saved day.
final class FootprintWidgetPublisher: WidgetSnapshotPublishing {
    private let storage: WidgetSnapshotStorage
    private let reload: () -> Void
    static var appGroupIdentifier: String? { WidgetSnapshotStorage.appGroupIdentifier() }
    static var isAvailable: Bool { WidgetSnapshotStorage.configured().directory != nil }
    // [02] A build without the shared group can still keep history; it simply cannot publish a widget summary.
    static func availablePublisher() -> FootprintWidgetPublisher? {
        let storage = WidgetSnapshotStorage.configured()
        guard storage.directory != nil else { return nil }
        return FootprintWidgetPublisher(storage: storage)
    }

    init(storage: WidgetSnapshotStorage, reload: @escaping () -> Void = {
        WidgetCenter.shared.reloadTimelines(ofKind: GardenWidgetSnapshot.widgetKind)
    }) {
        self.storage = storage
        self.reload = reload
    }
    // [03] Ask WidgetKit to reload only after the shared summary changes, saving limited refresh opportunities.
    func publish(_ snapshot: GardenWidgetSnapshot?) throws {
        if try storage.write(snapshot) { reload() }
    }
}

extension GardenWidgetSnapshot {
    // [04] Copy only the last saved result needed by the widget. App identities and detailed inputs stay out.
    init(record: FootprintRecord) {
        day = record.day
        totalKg = record.result.totalKg
        garden = WidgetGardenState(rawValue: record.garden.rawValue)!
        source = WidgetEstimateSource(rawValue: record.source.rawValue)!
        calculatedAt = record.calculatedAt
        isCompleted = record.isCompleted
    }
}

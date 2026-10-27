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

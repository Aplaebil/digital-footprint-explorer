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

// [01] A warm welcome can reflect the saved garden without claiming to know more about the person
// than we do

import XCTest
@testable import DFE

final class GardenFeedbackTests: XCTestCase {
    // [02] Each garden needs a relevant message that still makes clear that its footprint is an
    // estimate.
    func testEachSavedGardenStateHasAContextualEstimateMessage() {
        let cases: [(FootprintGarden, Double, String)] = [
            (.flourishing, 0.6, "well below"), (.growing, 0.8, "is below"),
            (.stable, 1.0, "is close"), (.wilting, 1.2, "is above"),
            (.withered, 1.6, "well above")
        ]
        let messages = cases.map { state, total, comparison in
            let message = GardenFeedback.message(state: state, totalKg: total, baselineKg: 1)
            XCTAssertTrue(message.contains(comparison))
            XCTAssertTrue(message.contains("Your estimate"))
            return message
        }
        XCTAssertEqual(Set(messages).count, cases.count)
    }

    // [03] A first day or zero baseline cannot support a believable claim about the person's usual
    // level.
    func testFirstAndZeroBaselineDaysDoNotInventAnAverageComparison() {
        let first = GardenFeedback.message(state: .stable, totalKg: 0.02, baselineKg: nil)
        XCTAssertTrue(first.contains("starting point"))
        XCTAssertFalse(first.contains("average"))
        XCTAssertTrue(GardenFeedback.message(state: .stable, totalKg: 0, baselineKg: 0).contains("zero estimate"))
        XCTAssertTrue(GardenFeedback.message(state: .withered, totalKg: 0.02, baselineKg: 0).contains("earlier zero"))
        XCTAssertEqual(GardenFeedback.message(state: .stable, totalKg: 0.02, baselineKg: .nan), first)
    }

    // [04] Removing the old naming choices should leave the person's appearance choice and history
    // untouched.
    func testRetiredGardenPreferencesAreRemovedWithoutChangingAppearanceOrHistory() throws {
        let suite = "DFE.GardenFeedbackTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Quiet corner", forKey: "dfe.garden.name")
        defaults.set("balance", forKey: "dfe.garden.focus")
        defaults.set("dark", forKey: AppAppearance.storageKey)
        defaults.set("retained", forKey: "history-test-marker")
        AppAppearance.removeRetiredGardenPreferences(in: defaults)
        XCTAssertNil(defaults.object(forKey: "dfe.garden.name"))
        XCTAssertNil(defaults.object(forKey: "dfe.garden.focus"))
        XCTAssertEqual(defaults.string(forKey: AppAppearance.storageKey), "dark")
        XCTAssertEqual(defaults.string(forKey: "history-test-marker"), "retained")
        AppAppearance.resetLocalPreferences(in: defaults)
        XCTAssertNil(defaults.object(forKey: AppAppearance.storageKey))
        XCTAssertEqual(defaults.string(forKey: "history-test-marker"), "retained")
    }
}

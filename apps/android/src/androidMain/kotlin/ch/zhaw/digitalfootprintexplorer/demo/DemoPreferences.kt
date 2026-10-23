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

package ch.zhaw.digitalfootprintexplorer.demo

// [01] The demo uses its own saved choices and meter readings, keeping them separate from real daily
// history.
internal object DemoPreferences {

    const val PREFS_STATE_FILE      = "demo_prefs"

    const val PREFS_CALCULATOR_FILE = "demo_calculator_prefs"

    const val KEY_ACTIVE            = "demo_active"
    const val KEY_GARDEN_STATE      = "demo_garden_state"
    const val KEY_SUMMARY           = "demo_summary"

    // [02] These readings mark where the short experiment started, so reopening the app does not restart
    // its clock.
    const val KEY_BASELINE_TS       = "baseline_ts"
    const val KEY_BASELINE_TOTAL    = "baseline_total"
    const val KEY_BASELINE_DFE      = "baseline_dfe"
}

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

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.model.GardenState
import ch.zhaw.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidget
import kotlinx.coroutines.CancellationException

// [01] This keeps the Android demo screen and widget on the same saved demo result.
class DemoRepository(private val appContext: Context) {

    private val prefs: SharedPreferences =
        appContext.getSharedPreferences(DemoPreferences.PREFS_STATE_FILE, Context.MODE_PRIVATE)

    val wasActiveOnStart: Boolean = prefs.getBoolean(DemoPreferences.KEY_ACTIVE, false)

    fun loadSummary(): String? = prefs.getString(DemoPreferences.KEY_SUMMARY, null)

    // [02] A deliberate new demo starts clean; an old demo result should not appear to belong to the new
    // experiment.
    fun activate() {
        DemoCalculator.resetBaseline(appContext)
        prefs.edit {
            putBoolean(DemoPreferences.KEY_ACTIVE, true)
            remove(DemoPreferences.KEY_GARDEN_STATE)
            remove(DemoPreferences.KEY_SUMMARY)
        }
    }

    // [03] When the demo ends, bring back the real saved garden instead of leaving the demonstration on the
    // widget.
    suspend fun deactivate() {
        DemoCalculator.clearBaseline(appContext)
        prefs.edit {
            putBoolean(DemoPreferences.KEY_ACTIVE, false)
            remove(DemoPreferences.KEY_GARDEN_STATE)
            remove(DemoPreferences.KEY_SUMMARY)
        }
        val app = appContext.applicationContext as DFEApplication
        val realState = app.gardenStateCalculator.getLatestGardenState()
        if (realState != null) GardenWidget.updateState(appContext, realState)
    }

    // [04] Save the result after updating the widget, so opening the app again can show the same demo
    // summary.
    suspend fun refresh(): Pair<EmissionResult, GardenState> {
        val (result, gardenState) = DemoCalculator.calculate(appContext)
        GardenWidget.updateState(appContext, gardenState)
        prefs.edit {
            putString(DemoPreferences.KEY_GARDEN_STATE, gardenState.name)
            putString(DemoPreferences.KEY_SUMMARY, buildSummary(result, gardenState.name))
        }
        return result to gardenState
    }

    // [05] The demo summary uses grams for small changes. It leaves out display energy because this demo
    // does not calculate it.
    fun buildSummary(result: EmissionResult, stateName: String): String {
        fun f(v: Double) = "%.6f".format(v)
        return """
app  : ${f(result.ghgAppUsage   * 1000)} gCO₂e
bg   : ${f(result.ghgBackground * 1000)} gCO₂e
total: ${f(result.ghgTotal      * 1000)} gCO₂e
state: $stateName
        """.trimIndent()
    }
}

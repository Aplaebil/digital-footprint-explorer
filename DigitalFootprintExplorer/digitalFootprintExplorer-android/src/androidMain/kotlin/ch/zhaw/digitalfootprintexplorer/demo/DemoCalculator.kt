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
import android.net.TrafficStats
import androidx.core.content.edit
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.digitalfootprintexplorer.model.EmissionsCalculator
import ch.zhaw.digitalfootprintexplorer.model.GardenState
import ch.zhaw.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.BackgroundProcessTracker

// [01] This Android demonstration shows changes over a short period; it is separate from the daily history
// calculation.
object DemoCalculator {

    // [02] A new demo starts from the current traffic counter, like taking a meter reading before a short
    // experiment.
    fun resetBaseline(context: Context) {
        val ts    = System.currentTimeMillis()
        val total = totalDeviceBytes()
        val dfe   = ownAppBytes(context)
        context.getSharedPreferences(DemoPreferences.PREFS_CALCULATOR_FILE, Context.MODE_PRIVATE)
            .edit {
                putLong(DemoPreferences.KEY_BASELINE_TS, ts)
                putLong(DemoPreferences.KEY_BASELINE_TOTAL, total)
                putLong(DemoPreferences.KEY_BASELINE_DFE, dfe)
            }
    }

    // [03] Leaving the demo clears its starting readings so the next experiment cannot reuse an old period.
    fun clearBaseline(context: Context) {
        context.getSharedPreferences(DemoPreferences.PREFS_CALCULATOR_FILE, Context.MODE_PRIVATE)
            .edit {
                remove(DemoPreferences.KEY_BASELINE_TS)
                remove(DemoPreferences.KEY_BASELINE_TOTAL)
                remove(DemoPreferences.KEY_BASELINE_DFE)
            }
    }

    // [04] The demo uses total phone traffic rather than claiming an app-by-app breakdown. Display energy
    // is left out here.
    suspend fun calculate(context: Context): Pair<EmissionResult, GardenState> {
        val dfeApp            = context.applicationContext as DFEApplication
        val backgroundTracker: BackgroundProcessTracker = dfeApp.backgroundProcessTracker

        val prefs = context.getSharedPreferences(DemoPreferences.PREFS_CALCULATOR_FILE, Context.MODE_PRIVATE)
        val baselineTs    = prefs.getLong(DemoPreferences.KEY_BASELINE_TS,    0L)
        val baselineTotal = prefs.getLong(DemoPreferences.KEY_BASELINE_TOTAL, 0L)
        val baselineDfe   = prefs.getLong(DemoPreferences.KEY_BASELINE_DFE,   0L)

        val toMs   = System.currentTimeMillis()
        val fromMs = if (baselineTs > 0L) baselineTs else toMs - 30_000L

        val currentTotal = totalDeviceBytes()
        val currentDfe   = ownAppBytes(context)
        // [05] Counters can restart or become unavailable. Negative changes should not turn into negative
        // traffic.
        val totalDelta   = maxOf(0L, currentTotal - baselineTotal)
        val dfeDelta     = maxOf(0L, currentDfe   - baselineDfe)
        // [06] Subtract DFE traffic from the phone total so the demonstration does not mainly reflect its
        // own activity.
        val deltaBytes   = maxOf(0L, totalDelta   - dfeDelta)
        val networkMetrics: List<AppUsageInput> = if (deltaBytes > 0L) listOf(
            AppUsageInput(
                appName       = "Device total",
                appCategory   = AppCategory.MISCELLANEOUS,
                wifiBytes     = DataPoint.Measured(deltaBytes.toDouble()),
                cellularBytes = DataPoint.Unavailable("not tracked in demo mode")
            )
        ) else emptyList()

        // [07] Save the new meter reading after this result; the next refresh then covers a fresh period.
        prefs.edit {
            putLong(DemoPreferences.KEY_BASELINE_TS, toMs)
            putLong(DemoPreferences.KEY_BASELINE_TOTAL, currentTotal)
            putLong(DemoPreferences.KEY_BASELINE_DFE, currentDfe)
        }
        val backgroundInput = backgroundTracker.peek(fromMs, toMs)

        val result = EmissionsCalculator().calculate(
            appUsage   = networkMetrics,
            display    = DisplayInput(intervals = emptyList()),
            background = backgroundInput
        )
        val gardenState = calculateDemoGardenState(result.ghgTotal)

        return result to gardenState
    }

    // [08] Unsupported traffic readings are not useful measurements. This demo uses zero for those missing
    // counters.
    private fun totalDeviceBytes(): Long {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        val validRx = if (rx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, rx)
        val validTx = if (tx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, tx)
        return validRx + validTx
    }

    private fun ownAppBytes(context: Context): Long {
        val uid = context.applicationInfo.uid
        val rx  = TrafficStats.getUidRxBytes(uid)
        val tx  = TrafficStats.getUidTxBytes(uid)
        val validRx = if (rx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, rx)
        val validTx = if (tx == TrafficStats.UNSUPPORTED.toLong()) 0L else maxOf(0L, tx)
        return validRx + validTx
    }

    // [09] A short demonstration needs its own fixed ranges. These are not the normal seven-day history
    // comparison.
    private fun calculateDemoGardenState(kgCO2e: Double): GardenState = when {
        kgCO2e < 5e-6   -> GardenState.FLOURISHING
        kgCO2e < 2e-5   -> GardenState.GROWING
        kgCO2e < 3.5e-5 -> GardenState.STABLE
        kgCO2e < 5.5e-5 -> GardenState.WILTING
        else            -> GardenState.WITHERED
    }
}

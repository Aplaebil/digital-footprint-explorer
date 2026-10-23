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

package ch.zhaw.digitalfootprintexplorer.model

import ch.zhaw.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.digitalfootprintexplorer.model.input.BackgroundInput
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.digitalfootprintexplorer.model.output.CategoryEmission
import ch.zhaw.digitalfootprintexplorer.model.output.EmissionResult

// [01] The estimate combines device use, network traffic, servers, the screen and background services.
// These are model results, not measured emissions.
class EmissionsCalculator(
    private val userEmissionFactor: Double = ModelConstants.EF_SWISS
) {

    // [02] Keep the three main contributions separate so the result can explain the total instead of
    // showing only one unexplained number.
    fun calculate(
        appUsage: List<AppUsageInput>,
        display: DisplayInput,
        background: BackgroundInput
    ): EmissionResult {
        val categoryBreakdown = calculateAppUsage(appUsage)
        return EmissionResult(
            ghgAppUsage = categoryBreakdown.fold(0.0) { acc, c -> acc + c.ghgTotal },
            ghgDisplay = calculateDisplay(display),
            ghgBackground = calculateBackground(background),
            categoryBreakdown = categoryBreakdown
        )
    }

    // [03] Group apps by activity before applying category power values. Several apps in one category
    // should still contribute to one category total.
    private fun calculateAppUsage(metrics: List<AppUsageInput>): List<CategoryEmission> {

        return metrics
            .groupBy { it.appCategory }
            .map { (category, entries) ->
                // [04] Power needs hours and traffic rates need decimal GB, so convert the recorded seconds
                // and bytes before using those rates.
                val totalTimeH = entries.sumOf { it.totalForegroundTime } / 3600.0
                val totalWifiGB = entries.fold(0.0) { acc, m -> acc + m.wifiBytes.valueOrDefault() } / 1_000_000_000.0
                val totalCellularGB = entries.fold(0.0) { acc, m -> acc + m.cellularBytes.valueOrDefault() } / 1_000_000_000.0

                CategoryEmission(
                    category = category,
                    ghgDevice = calculateDevice(category, totalTimeH),
                    ghgNetwork = calculateNetwork(totalWifiGB, totalCellularGB),
                    ghgBackend = calculateBackend(category, totalWifiGB + totalCellularGB)
                )
            }
    }

    // [05] Device electricity includes the model's charging losses, then uses the chosen electricity mix to
    // estimate its emissions.
    private fun calculateDevice(category: AppCategory, timeH: Double): Double {
        val pWatt = ModelConstants.P_DEVICE_BY_CATEGORY[category]
            ?: ModelConstants.P_DEVICE_BY_CATEGORY[AppCategory.MISCELLANEOUS]!!
        val energyKwh = pWatt * timeH / 1000.0
        return energyKwh / ModelConstants.CHARGING_EFFICIENCY * userEmissionFactor
    }

    // [06] Wi-Fi and mobile traffic have different energy rates. Keeping them separate lets the estimate
    // reflect that difference.
    private fun calculateNetwork(wifiGB: Double, cellularGB: Double): Double {
        val energyKwh =
            wifiGB * ModelConstants.NETWORK_INTENSITY_WIFI +
            cellularGB * ModelConstants.NETWORK_INTENSITY_CELLULAR
        return energyKwh * ModelConstants.EF_GLOBAL
    }

    // [07] Server energy follows traffic volume, with a category multiplier where the model defines one.
    private fun calculateBackend(category: AppCategory, totalDataGB: Double): Double {
        val factor = ModelConstants.BACKEND_INTENSITY_FACTOR_BY_CATEGORY[category] ?: 1.0
        return totalDataGB * ModelConstants.BACKEND_INTENSITY_GB * factor * ModelConstants.EF_GLOBAL
    }

    // [08] A bright screen uses more of the model's display power; dark periods contribute no display
    // energy.
    private fun calculateDisplay(display: DisplayInput): Double {
        val energyWh = ModelConstants.P_DISPLAY_MAX_WATT *
            display.intervals.fold(0.0) { acc, i -> acc + i.normalizedBrightness * i.durationH }
        val energyKwh = energyWh / 1000.0
        return energyKwh / ModelConstants.CHARGING_EFFICIENCY * userEmissionFactor
    }

    // [09] Each tracked service adds its own power over its active time, so these costs do not get lost
    // inside app traffic.
    private fun calculateBackground(background: BackgroundInput): Double {
        return background.activeProcesses.fold(0.0) { acc, proc ->
            val pWatt = ModelConstants.P_BACKGROUND_BY_PROCESS[proc.process] ?: 0.0
            val energyKwh = pWatt * proc.durationH / 1000.0
            acc + energyKwh / ModelConstants.CHARGING_EFFICIENCY * userEmissionFactor
        }
    }
}

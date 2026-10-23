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
import ch.zhaw.digitalfootprintexplorer.model.input.BrightnessInterval
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import ch.zhaw.digitalfootprintexplorer.model.output.EmissionResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private fun Long.dp() = DataPoint.Measured(this.toDouble())

// [01] Use made-up inputs with known units to check the shared emissions model, rather than treating phone
// activity as test data.
class EmissionsCalculatorTest {

    private val calculator = EmissionsCalculator()
    private val emptyDisplay = DisplayInput(emptyList())
    private val emptyBackground = BackgroundInput(emptyList())

    @Test
    // [02] An empty input must stay zero; the model should not invent energy use when no contribution is
    // supplied.
    fun `zero input yields zero emissions`() {
        val result = calculator.calculate(emptyList(), emptyDisplay, emptyBackground)
        assertEquals(0.0, result.ghgTotal)
        assertEquals(0.0, result.ghgAppUsage)
        assertEquals(0.0, result.ghgDisplay)
        assertEquals(0.0, result.ghgBackground)
    }

    @Test
    // [03] A known hour and traffic volume make it possible to check the device, network and server
    // contributions by hand.
    fun `1h video streaming over wifi yields positive value`() {
        val metric = AppUsageInput(
            appName = "Netflix",
            appCategory = AppCategory.VIDEO_STREAMING,
            totalForegroundTime = 3600,
            wifiBytes = 2_700_000_000L.dp(),
            cellularBytes = 0L.dp()
        )
        val result = calculator.calculate(listOf(metric), emptyDisplay, emptyBackground)
        assertTrue(result.ghgAppUsage > 0.0)
        val wifiGB = 2_700_000_000.0 / 1_000_000_000.0
        val timeH = 3600.0 / 3600.0
        val expectedDevice = ModelConstants.P_DEVICE_BY_CATEGORY[AppCategory.VIDEO_STREAMING]!! *
            timeH / 1000.0 / ModelConstants.CHARGING_EFFICIENCY * ModelConstants.EF_SWISS
        val expectedNetwork = wifiGB * ModelConstants.NETWORK_INTENSITY_WIFI * ModelConstants.EF_GLOBAL
        val expectedBackend = wifiGB * ModelConstants.BACKEND_INTENSITY_GB * ModelConstants.EF_GLOBAL
        assertEquals(expectedDevice + expectedNetwork + expectedBackend, result.ghgAppUsage, absoluteTolerance = 1e-9)
    }

    @Test
    // [04] The same traffic over mobile data should cost more in this model than over Wi-Fi.
    fun `cellular is more energy intensive than wifi`() {
        val wifiMetric = AppUsageInput("App", AppCategory.VIDEO_STREAMING, 3600,
            wifiBytes = 1_000_000_000L.dp(), cellularBytes = 0L.dp())
        val cellMetric = AppUsageInput("App", AppCategory.VIDEO_STREAMING, 3600,
            wifiBytes = 0L.dp(), cellularBytes = 1_000_000_000L.dp())

        val wifiResult = calculator.calculate(listOf(wifiMetric), emptyDisplay, emptyBackground)
        val cellResult = calculator.calculate(listOf(cellMetric), emptyDisplay, emptyBackground)

        assertTrue(cellResult.ghgNetwork(cellMetric) > wifiResult.ghgNetwork(wifiMetric))
    }

    @Test
    // [05] Screen energy must be able to stand on its own, without creating app or background emissions.
    fun `only display input yields ghg only for display`() {
        val display = DisplayInput(listOf(BrightnessInterval(0.5, 1.0)))
        val result = calculator.calculate(emptyList(), display, emptyBackground)
        assertEquals(0.0, result.ghgAppUsage)

        assertEquals(0.000013401709401709402, result.ghgDisplay, absoluteTolerance = 1e-12)
    }

    @Test
    // [06] Splitting one category across two apps must not change that category's combined estimate.
    fun `multiple apps of same category are aggregated correctly`() {
        val metrics = listOf(
            AppUsageInput("Netflix", AppCategory.VIDEO_STREAMING, 1800, 500_000_000L.dp(), 0L.dp()),
            AppUsageInput("YouTube", AppCategory.VIDEO_STREAMING, 1800, 500_000_000L.dp(), 0L.dp())
        )
        val resultAggregated = calculator.calculate(metrics, emptyDisplay, emptyBackground)

        val singleMetric = AppUsageInput("Combined", AppCategory.VIDEO_STREAMING, 3600, 1_000_000_000L.dp(), 0L.dp())
        val resultSingle = calculator.calculate(listOf(singleMetric), emptyDisplay, emptyBackground)

        assertEquals(resultSingle.ghgTotal, resultAggregated.ghgTotal, absoluteTolerance = 1e-10)
    }

    @Test
    // [07] The displayed total must still be the sum of its three explained contributions.
    fun `ghg total is sum of the three components`() {
        val metric = AppUsageInput("App", AppCategory.SOCIAL_MEDIA, 3600, 100_000_000L.dp(), 0L.dp())
        val display = DisplayInput(listOf(BrightnessInterval(0.7, 0.5)))
        val background = BackgroundInput(listOf(ProcessUsage(BackgroundProcess.GPS, 1.0f)))

        val result = calculator.calculate(listOf(metric), display, background)
        val expectedTotal = result.ghgAppUsage + result.ghgDisplay + result.ghgBackground
        assertEquals(expectedTotal, result.ghgTotal, absoluteTolerance = 1e-10)
    }

    @Test
    // [08] Missing network readings do not remove the energy of known foreground activity.
    fun `app with foreground time but no network data yields positive device emissions`() {
        val metric = AppUsageInput(
            appName             = "Calculator",
            appCategory         = AppCategory.MISCELLANEOUS,
            totalForegroundTime = 1800,
            wifiBytes           = 0L.dp(),
            cellularBytes       = 0L.dp()
        )
        val result = calculator.calculate(listOf(metric), emptyDisplay, emptyBackground)

        val category = result.categoryBreakdown.first { it.category == AppCategory.MISCELLANEOUS }
        assertTrue(result.ghgAppUsage > 0.0)
        assertTrue(category.ghgDevice > 0.0)
        assertEquals(0.0, category.ghgNetwork)
        assertEquals(0.0, category.ghgBackend)
    }

    @Test
    // [09] With neither usage time nor traffic, the app must not gain an unexplained contribution.
    fun `app with no foreground time and no network data yields zero app emissions`() {
        val metric = AppUsageInput(
            appName             = "SilentApp",
            appCategory         = AppCategory.MISCELLANEOUS,
            totalForegroundTime = 0,
            wifiBytes           = 0L.dp(),
            cellularBytes       = 0L.dp()
        )
        val result = calculator.calculate(listOf(metric), emptyDisplay, emptyBackground)

        assertEquals(0.0, result.ghgAppUsage)
    }

    private fun EmissionResult.ghgNetwork(metric: AppUsageInput): Double =
        categoryBreakdown.firstOrNull { it.category == metric.appCategory }?.ghgNetwork ?: 0.0
}

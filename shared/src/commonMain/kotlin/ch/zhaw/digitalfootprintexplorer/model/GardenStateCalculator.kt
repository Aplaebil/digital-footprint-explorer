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

import ch.zhaw.digitalfootprintexplorer.database.DFEDatabase
import ch.zhaw.digitalfootprintexplorer.model.output.CategoryEmission
import kotlinx.datetime.LocalDate

// [01] The Android garden compares a day with earlier saved days, so its appearance reflects change from
// recent use.
class GardenStateCalculator(private val database: DFEDatabase) {

    // [02] Save the total and its categories together under the same date, keeping the details traceable to
    // their daily result.
    fun recordDailyFootprint(
        date: LocalDate,
        kgCO2e: Double,
        ghgAppUsage: Double,
        ghgDisplay: Double,
        ghgBackground: Double,
        measuredAt: String,
        gardenState: GardenState,
        baselineKgCO2e: Double,
        categoryBreakdown: List<CategoryEmission>
    ) {
        val dateStr = date.toString()
        database.dailyFootprintQueries.insert(
            dateStr, kgCO2e, ghgAppUsage, ghgDisplay, ghgBackground, measuredAt,
            gardenState.name, baselineKgCO2e
        )
        categoryBreakdown.forEach { c ->
            database.dailyFootprintQueries.insertCategory(dateStr, c.category.name, c.ghgTotal)
        }
    }

    // [03] Call this before saving the new day. A day must not be included in the average it is compared
    // with.
    fun calculateGardenState(todayFootprint: Double): Pair<GardenState, Double> {
        val count = database.dailyFootprintQueries.count().executeAsOne()
        // [04] Without earlier days there is no personal comparison yet, so the first garden starts in the
        // stable state.
        if (count == 0L) return GardenState.STABLE to 0.0
        // [05] Use all earlier days at first, then only the latest seven for the comparison. Older history
        // remains saved.
        val entries = if (count >= 7L) {
            database.dailyFootprintQueries.selectLatest7().executeAsList()
        } else {
            database.dailyFootprintQueries.selectAll().executeAsList()
        }
        val baseline = entries.map { it.total_kg }.average()
        return fromDeviation(todayFootprint, baseline) to baseline
    }

    // [06] Returning from a demo should restore the real latest garden; an unreadable saved state is
    // treated as absent.
    fun getLatestGardenState(): GardenState? {
        val latest = database.dailyFootprintQueries.selectLatest().executeAsOneOrNull()
        return latest?.garden_state?.let { runCatching { GardenState.valueOf(it) }.getOrNull() }
    }

    fun getLatestEntry(): DailyFootprintEntry? {
        val latest = database.dailyFootprintQueries.selectLatest().executeAsOneOrNull() ?: return null
        return DailyFootprintEntry(
            date = LocalDate.parse(latest.date),
            kgCO2e = latest.total_kg,
            ghgAppUsage = latest.app_usage_kg,
            ghgDisplay = latest.display_kg,
            ghgBackground = latest.background_kg,
            measuredAt = latest.calculated_at
        )
    }

    // [07] The daily worker checks the most recent saved date so it can skip an already completed day.
    fun isDailyFootprintCalculated(date: LocalDate): Boolean {
        return database.dailyFootprintQueries.selectLatest().executeAsOneOrNull()?.date == date.toString()
    }

    // [08] Lower estimates lead to a healthier garden relative to the saved average. These ranges are model
    // feedback, not proof of ecological change.
    private fun fromDeviation(today: Double, baseline: Double): GardenState {
        val percentage = (today - baseline) / baseline
        return when {
            percentage <= -0.30 -> GardenState.FLOURISHING
            percentage <= -0.10 -> GardenState.GROWING
            percentage <   0.10 -> GardenState.STABLE
            percentage <=  0.40 -> GardenState.WILTING
            else                -> GardenState.WITHERED
        }
    }

}

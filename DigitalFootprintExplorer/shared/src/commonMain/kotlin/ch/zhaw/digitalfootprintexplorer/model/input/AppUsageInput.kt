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

package ch.zhaw.digitalfootprintexplorer.model.input

import ch.zhaw.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.digitalfootprintexplorer.model.DataPoint

// [01] One app or category brings its activity group, usage time and traffic quality into the shared
// calculation.
data class AppUsageInput(
    val appName: String,
    val appCategory: AppCategory,

    // [02] Both platforms supply seconds here, preventing minutes or milliseconds from changing the
    // estimate by the wrong scale.
    val totalForegroundTime: Int = 0,
    val wifiBytes: DataPoint,
    val cellularBytes: DataPoint,
)

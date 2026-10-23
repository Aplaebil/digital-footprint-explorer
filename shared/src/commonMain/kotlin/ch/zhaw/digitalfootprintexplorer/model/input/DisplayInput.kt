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

// [01] Pair brightness from zero to one with its duration in hours; the screen estimate needs both.
data class BrightnessInterval(
    val normalizedBrightness: Double,
    val durationH: Double
)

// [02] Several brightness periods let the model account for a screen that changes during the day.
data class DisplayInput(
    val intervals: List<BrightnessInterval>
)

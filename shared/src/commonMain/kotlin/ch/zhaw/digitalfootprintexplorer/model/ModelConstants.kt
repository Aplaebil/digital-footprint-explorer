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

// [01] Keep the model's fixed values in one place so Android and iOS use the same calculation rules.
object ModelConstants {

    // [02] Electricity factors turn energy into kilograms of CO2e. The device uses the chosen mix; network
    // and servers use the global factor.
    const val EF_SWISS = 0.0392
    const val EF_GLOBAL = 0.458

    // [03] Some charging energy is lost before reaching the device, so using the phone needs more
    // electricity than its useful energy alone.
    const val CHARGING_EFFICIENCY = 0.585

    // [04] The network model assigns a different amount of energy to each decimal GB over Wi-Fi or mobile
    // data.
    const val NETWORK_INTENSITY_WIFI = 0.006
    const val NETWORK_INTENSITY_CELLULAR = 0.055

    // [05] Category power values describe typical model activity; they are not a live power reading from
    // the user's phone.
    val P_DEVICE_BY_CATEGORY: Map<AppCategory, Double> = mapOf(
        AppCategory.VIDEO_STREAMING      to 1.0,
        AppCategory.AUDIO_STREAMING      to 0.5,
        AppCategory.SOCIAL_MEDIA         to 1.7,
        AppCategory.MESSAGING            to 0.6,
        AppCategory.ARTIFICIAL_INTELLIGENCE to 0.5,
        AppCategory.E_MAIL               to 0.5,
        AppCategory.VIDEO_CALL           to 4.0,
        AppCategory.GAMING               to 1.3,
        AppCategory.NAVIGATION           to 0.9,
        AppCategory.MISCELLANEOUS        to 0.5
    )

    // [06] The display model scales this maximum by brightness and time to estimate screen energy.
    const val P_DISPLAY_MAX_WATT = 0.4

    // [07] GPS and Bluetooth use their own power assumptions when active time is included.
    val P_BACKGROUND_BY_PROCESS: Map<BackgroundProcess, Double> = mapOf(
        BackgroundProcess.GPS       to 0.3,
        BackgroundProcess.BLUETOOTH to 0.04
    )

    // [08] Server energy starts with one traffic-based rate. A separate multiplier gives AI activity its
    // model-specific adjustment.
    const val BACKEND_INTENSITY_GB = 0.055

    val BACKEND_INTENSITY_FACTOR_BY_CATEGORY: Map<AppCategory, Double> = mapOf(
        AppCategory.ARTIFICIAL_INTELLIGENCE to 10.0
    )
}

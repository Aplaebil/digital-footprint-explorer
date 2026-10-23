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

package ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import java.util.Locale
import ch.zhaw.digitalfootprintexplorer.model.input.BrightnessInterval
import ch.zhaw.digitalfootprintexplorer.model.input.DisplayInput
import androidx.core.content.edit

// [01] The Android screen estimate needs brightness over time, rather than just the brightness when the
// daily job runs.
class DisplayBrightnessObserver(private val context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private var currentBrightness: Double = 0.0
    private var intervalStartMs: Long = System.currentTimeMillis()
    private var screenOn: Boolean = true

    private val contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            // [02] A brightness setting can change while the screen is off. That must not add energy for a
            // screen that is dark.
            if (!screenOn) return
            val now = System.currentTimeMillis()
            flushInterval(now)
            currentBrightness = readCurrentBrightness()
            intervalStartMs = now
        }
    }

    fun register() {
        screenOn = isScreenOn()
        currentBrightness = if (screenOn) readCurrentBrightness() else 0.0
        intervalStartMs = System.currentTimeMillis()
        context.contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS),
            false,
            contentObserver
        )
    }

    fun unregister() {
        context.contentResolver.unregisterContentObserver(contentObserver)
    }

    // [03] Close the lit period before recording darkness, so screen-off time does not use the previous
    // brightness.
    fun onScreenOff() {
        val now = System.currentTimeMillis()
        flushInterval(now)
        currentBrightness = 0.0
        intervalStartMs = now
        screenOn = false
    }

    // [04] End the dark period before using the current brightness again.
    fun onScreenOn() {
        val now = System.currentTimeMillis()
        flushInterval(now)
        currentBrightness = readCurrentBrightness()
        intervalStartMs = now
        screenOn = true
    }

    // [05] Only yesterday's part is used now. Later activity stays saved for the next daily calculation.
    fun collectAndReset(fromMs: Long, toMs: Long): DisplayInput {
        val now = System.currentTimeMillis()
        val originalStartMs = intervalStartMs

        val flushEnd = minOf(now, toMs)
        if (flushEnd > originalStartMs) {
            appendInterval(currentBrightness, originalStartMs, flushEnd)
        }

        val raw = prefs.getString(KEY_INTERVALS, "") ?: ""
        val intervals = parseAndClip(raw, fromMs, toMs)
        val remainingRaw = keepIntervalsAfter(raw, toMs)

        prefs.edit {
            if (remainingRaw.isBlank()) {
                remove(KEY_INTERVALS)
            } else {
                putString(KEY_INTERVALS, remainingRaw)
            }
        }

        // [06] If a brightness period crosses the day boundary, continue it from that boundary without
        // losing today's activity.
        intervalStartMs = when {
            now <= toMs -> now
            originalStartMs < toMs -> toMs
            else -> originalStartMs
        }

        return DisplayInput(
            // [07] With no recorded periods, this Android path assumes a full day at half brightness. That
            // is a fallback, not a reading.
            intervals = intervals.ifEmpty {
                listOf(BrightnessInterval(normalizedBrightness = DEFAULT_BRIGHTNESS, durationH = 24.0))
            }
        )
    }

    private fun keepIntervalsAfter(raw: String, boundaryMs: Long): String {
        if (raw.isBlank()) return ""

        return raw.split(",").mapNotNull { entry ->
            val parts = entry.split(":")
            if (parts.size != 3) return@mapNotNull null

            val b = parts[0].toDoubleOrNull() ?: return@mapNotNull null
            val s = parts[1].toLongOrNull() ?: return@mapNotNull null
            val e = parts[2].toLongOrNull() ?: return@mapNotNull null

            if (e <= boundaryMs) return@mapNotNull null

            val clippedStart = maxOf(s, boundaryMs)
            String.format(Locale.ROOT, "%.10f:%d:%d", b, clippedStart, e)
        }.joinToString(",")
    }

    private fun flushInterval(endMs: Long) {
        if (endMs > intervalStartMs) {
            appendInterval(currentBrightness, intervalStartMs, endMs)
        }
    }

    // [08] Use a decimal point in saved brightness values, so a phone language that uses commas cannot
    // split a record by mistake.
    private fun appendInterval(brightness: Double, startMs: Long, endMs: Long) {
        val existing = prefs.getString(KEY_INTERVALS, "") ?: ""
        val entry    = String.format(Locale.ROOT, "%.10f:%d:%d", brightness, startMs, endMs)
        val updated  = if (existing.isEmpty()) entry else "$existing,$entry"
        prefs.edit { putString(KEY_INTERVALS, updated) }
    }

    // [09] Ignore unreadable records and trim valid ones to the requested day before they enter the
    // calculation.
    private fun parseAndClip(raw: String, fromMs: Long, toMs: Long): List<BrightnessInterval> {
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { entry ->
            val parts = entry.split(":")
            if (parts.size == 3) {
                val b = parts[0].toDoubleOrNull() ?: return@mapNotNull null
                val s = parts[1].toLongOrNull()   ?: return@mapNotNull null
                val e = parts[2].toLongOrNull()   ?: return@mapNotNull null
                val clippedStart = maxOf(s, fromMs)
                val clippedEnd   = minOf(e, toMs)
                if (clippedEnd <= clippedStart) return@mapNotNull null
                val durationH = (clippedEnd - clippedStart) / MILLIS_PER_HOUR
                BrightnessInterval(normalizedBrightness = b, durationH = durationH)
            } else null
        }
    }

    private fun readCurrentBrightness(): Double {
        val raw = Settings.System.getInt(
            context.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            DEFAULT_RAW_BRIGHTNESS
        )
        return raw / MAX_BRIGHTNESS
    }

    private fun isScreenOn(): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    companion object {
        private const val PREFS_NAME          = "display_brightness_observer"
        private const val KEY_INTERVALS       = "intervals"
        private const val MAX_BRIGHTNESS      = 255.0
        private const val DEFAULT_RAW_BRIGHTNESS = 128
        private const val DEFAULT_BRIGHTNESS  = 0.5
        private const val MILLIS_PER_HOUR     = 3_600_000.0
    }
}

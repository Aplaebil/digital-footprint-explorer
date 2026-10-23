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

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.os.Build
import ch.zhaw.digitalfootprintexplorer.model.BackgroundProcess
import ch.zhaw.digitalfootprintexplorer.model.ProcessUsage
import ch.zhaw.digitalfootprintexplorer.model.input.BackgroundInput
import androidx.core.content.edit

// [01] GPS and Bluetooth on/off periods support an energy estimate. They do not reveal a person's location
// or messages.
class BackgroundProcessTracker(private val context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                LocationManager.PROVIDERS_CHANGED_ACTION ->
                    updateState(BackgroundProcess.GPS, isGpsEnabled())
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                    updateState(BackgroundProcess.BLUETOOTH, state == BluetoothAdapter.STATE_ON)
                }
            }
        }
    }

    // [02] Read the current switches before listening for changes, so a service that is already on is not
    // missed.
    fun register() {
        initState(BackgroundProcess.GPS, isGpsEnabled())
        initState(BackgroundProcess.BLUETOOTH, isBluetoothEnabled())

        val filter = IntentFilter().apply {
            addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    fun unregister() {
        runCatching { context.unregisterReceiver(receiver) }
    }

    // [03] A demo can read a time window without consuming periods that the real daily calculation still
    // needs.
    fun peek(fromMs: Long, toMs: Long): BackgroundInput {
        val now = System.currentTimeMillis()
        val processes = BackgroundProcess.entries.mapNotNull { process ->
            val isActive = prefs.getBoolean(activeKey(process), false)
            val startMs  = prefs.getLong(startKey(process), now)

            val raw = prefs.getString(intervalsKey(process), "") ?: ""
            val completedMs = parseAndClip(raw, fromMs, toMs).sum()

            // [04] An active period may not have ended yet. Include only the part inside the requested
            // window.
            val openMs = if (isActive) {
                val clippedStart = maxOf(startMs, fromMs)
                val clippedEnd   = minOf(now, toMs)
                if (clippedEnd > clippedStart) clippedEnd - clippedStart else 0L
            } else 0L

            val totalH = ((completedMs + openMs) / MILLIS_PER_HOUR).toFloat()
            if (totalH > 0f) ProcessUsage(process = process, durationH = totalH) else null
        }
        return BackgroundInput(activeProcesses = processes)
    }

    // [05] Finish yesterday's periods while keeping activity after the boundary for the following day.
    fun collectAndReset(fromMs: Long, toMs: Long): BackgroundInput {
        val now = System.currentTimeMillis()
        val processes = BackgroundProcess.entries.mapNotNull { process ->
            val isActive = prefs.getBoolean(activeKey(process), false)
            val startMs  = prefs.getLong(startKey(process), now)

            if (isActive) {
                val flushEnd = minOf(now, toMs)
                if (flushEnd > startMs) appendInterval(process, startMs, flushEnd)
            }

            val raw = prefs.getString(intervalsKey(process), "") ?: ""
            val totalMs = parseAndClip(raw, fromMs, toMs).sum()
            val totalH = (totalMs / MILLIS_PER_HOUR).toFloat()

            val remainingRaw = keepIntervalsAfter(raw, toMs)

            // [06] A service can stay on across midnight. Its next period must start at the boundary,
            // without counting yesterday twice.
            val newStartMs = when {
                isActive && now > toMs && startMs < toMs -> toMs
                isActive -> startMs
                else -> now
            }

            prefs.edit {
                if (remainingRaw.isBlank()) {
                    remove(intervalsKey(process))
                } else {
                    putString(intervalsKey(process), remainingRaw)
                }

                putLong(startKey(process), newStartMs)
            }

            if (totalH > 0f) ProcessUsage(process = process, durationH = totalH) else null
        }
        return BackgroundInput(activeProcesses = processes)
    }

    // [07] Keep the part of a saved period that belongs to a later day instead of throwing away newly
    // collected activity.
    private fun keepIntervalsAfter(raw: String, boundaryMs: Long): String {
        if (raw.isBlank()) return ""

        return raw.split(",").mapNotNull { entry ->
            val parts = entry.split(":")
            if (parts.size != 2) return@mapNotNull null

            val s = parts[0].toLongOrNull() ?: return@mapNotNull null
            val e = parts[1].toLongOrNull() ?: return@mapNotNull null

            if (e <= boundaryMs) return@mapNotNull null

            val clippedStart = maxOf(s, boundaryMs)
            "$clippedStart:$e"
        }.joinToString(",")
    }

    // [08] The first reading starts the clock once. Registering again must not erase an existing start
    // time.
    private fun initState(process: BackgroundProcess, isActive: Boolean) {
        if (!prefs.contains(activeKey(process))) {
            prefs.edit {
                putBoolean(activeKey(process), isActive)
                putLong(startKey(process), System.currentTimeMillis())
            }
        }
    }

    private fun updateState(process: BackgroundProcess, isNowActive: Boolean) {
        val now = System.currentTimeMillis()
        val wasActive = prefs.getBoolean(activeKey(process), false)

        // [09] Repeated system messages do not mean a new activity period, so leave the current one alone.
        if (wasActive == isNowActive) return

        if (wasActive) {
            val start = prefs.getLong(startKey(process), now)
            appendInterval(process, start, now)
        }

        prefs.edit {
            putBoolean(activeKey(process), isNowActive)

            if (!wasActive) {
                putLong(startKey(process), now)
            }
        }
    }

    private fun appendInterval(process: BackgroundProcess, startMs: Long, endMs: Long) {
        val existing = prefs.getString(intervalsKey(process), "") ?: ""
        val entry    = "$startMs:$endMs"
        val updated  = if (existing.isEmpty()) entry else "$existing,$entry"
        prefs.edit { putString(intervalsKey(process), updated) }
    }

    // [10] Damaged saved entries are skipped, and valid periods count only within the day being calculated.
    private fun parseAndClip(raw: String, fromMs: Long, toMs: Long): List<Long> {
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { entry ->
            val parts = entry.split(":")
            if (parts.size == 2) {
                val s = parts[0].toLongOrNull() ?: return@mapNotNull null
                val e = parts[1].toLongOrNull() ?: return@mapNotNull null
                val clippedStart = maxOf(s, fromMs)
                val clippedEnd   = minOf(e, toMs)
                if (clippedEnd > clippedStart) clippedEnd - clippedStart else null
            } else null
        }
    }

    private fun isGpsEnabled(): Boolean {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    private fun isBluetoothEnabled(): Boolean {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter?.isEnabled == true
    }

    private fun activeKey(p: BackgroundProcess)    = "active_${p.name}"
    private fun startKey(p: BackgroundProcess)     = "start_${p.name}"
    private fun intervalsKey(p: BackgroundProcess) = "intervals_${p.name}"

    companion object {
        private const val PREFS_NAME      = "background_process_tracker"
        private const val MILLIS_PER_HOUR = 3_600_000.0
    }
}

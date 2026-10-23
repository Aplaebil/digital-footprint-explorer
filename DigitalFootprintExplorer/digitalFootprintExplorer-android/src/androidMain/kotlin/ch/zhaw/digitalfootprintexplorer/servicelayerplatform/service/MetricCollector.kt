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

import android.app.usage.UsageStatsManager
import android.content.Context
import ch.zhaw.digitalfootprintexplorer.model.input.AppUsageInput
import ch.zhaw.digitalfootprintexplorer.model.DataPoint
import ch.zhaw.digitalfootprintexplorer.model.NetworkType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

// [01] Bring app time and network totals into the shared model without asking the Android user to enter
// each value.
class MetricCollector(
    private val installedAppProvider: InstalledAppProvider,
    private val networkUsageDataSource: NetworkUsageDataSource,
    private val usageStatsManager: UsageStatsManager
) {

    suspend fun collectNetworkMetrics(
        context: Context,
        startTime: Long,
        endTime: Long,
        mobileSubscriberId: String?
    ): List<AppUsageInput> = coroutineScope {
        if (startTime > endTime) throw IllegalArgumentException("Start time must be before end time.")

        val apps = installedAppProvider.getInstalledLauncherApps(context)
        // [02] Limit simultaneous lookups so collecting many apps does not put all of them to work at once.
        val dispatcher = Dispatchers.IO.limitedParallelism(3)

        // [03] Read the usage summary once for this window, then match each app to that same set of
        // readings.
        val foregroundMap: Map<String, Long> = usageStatsManager
            .queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
            .associate { it.packageName to it.totalTimeInForeground }

        apps.map { app ->
            async(dispatcher) {
                // [04] Keep a denied network reading marked unavailable. Missing access is different from
                // measured zero traffic.
                val wifiBytes: DataPoint = networkUsageDataSource.getUsageBytes(
                    networkType = NetworkType.WIFI,
                    subscriberId = null,
                    startTime = startTime,
                    endTime = endTime,
                    uid = app.uid
                )?.let { DataPoint.Measured(it.toDouble()) }
                    ?: DataPoint.Unavailable("permission denied")

                val cellularBytes: DataPoint = networkUsageDataSource.getUsageBytes(
                    networkType = NetworkType.CELLULAR,
                    subscriberId = mobileSubscriberId,
                    startTime = startTime,
                    endTime = endTime,
                    uid = app.uid
                )?.let { DataPoint.Measured(it.toDouble()) }
                    ?: DataPoint.Unavailable("permission denied")

                // [05] Android reports foreground time in milliseconds; the shared calculation expects
                // seconds.
                AppUsageInput(
                    appName             = app.name,
                    wifiBytes           = wifiBytes,
                    cellularBytes       = cellularBytes,
                    appCategory         = app.category,
                    totalForegroundTime = ((foregroundMap[app.packageName] ?: 0L) / 1_000L).toInt()
                )
            }
        }.awaitAll()
    }

}

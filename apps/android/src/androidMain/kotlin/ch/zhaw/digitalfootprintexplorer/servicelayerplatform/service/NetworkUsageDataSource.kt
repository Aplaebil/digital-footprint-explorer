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

import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.net.NetworkCapabilities
import android.os.RemoteException
import ch.zhaw.digitalfootprintexplorer.model.NetworkType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// [01] This reads the traffic Android makes available for one app and time window, away from the screen's
// work.
class NetworkUsageDataSource(
    private val context: Context
) {

    suspend fun getUsageBytes(
        networkType: NetworkType,
        subscriberId: String?,
        startTime: Long,
        endTime: Long,
        uid: Int
    ): Long? = withContext(Dispatchers.IO) {
        if (startTime > endTime) throw IllegalArgumentException("Start time must be before end time.")

        val networkStatsManager = context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager

        val androidNetworkType = when(networkType) {
            NetworkType.WIFI -> NetworkCapabilities.TRANSPORT_WIFI
            NetworkType.CELLULAR -> NetworkCapabilities.TRANSPORT_CELLULAR
        }

        try {
            val stats = networkStatsManager.queryDetailsForUid(
                androidNetworkType,
                subscriberId,
                startTime,
                endTime,
                uid
            )

            try {
                var rxBytes = 0L
                var txBytes = 0L
                val bucket = NetworkStats.Bucket()

                // [02] The total needs both incoming and outgoing traffic across all returned time blocks.
                while(stats.hasNextBucket()) {
                    stats.getNextBucket(bucket)
                    rxBytes += bucket.rxBytes
                    txBytes += bucket.txBytes
                }
                rxBytes + txBytes
            // [03] If Android stops the lookup part way through, return no reading rather than a misleading
            // partial total.
            } catch (e: RemoteException) {
                e.printStackTrace()
                null
            }
        // [04] A blocked lookup remains missing data. The caller can then keep the access problem separate
        // from zero usage.
        } catch (e: SecurityException) {
            e.printStackTrace()
            null
        }
    }

}

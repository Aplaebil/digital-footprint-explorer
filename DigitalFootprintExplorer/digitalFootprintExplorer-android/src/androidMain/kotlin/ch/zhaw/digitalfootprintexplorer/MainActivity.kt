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

package ch.zhaw.digitalfootprintexplorer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import ch.zhaw.digitalfootprintexplorer.permission.hasUsageStatsPermission
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.TrackingService
import ch.zhaw.digitalfootprintexplorer.worker.DailyFootprintWorker

// [01] Opening the Android app gives yesterday a chance to finish if its scheduled calculation has not run
// yet.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        // [02] Without usage access, a calculation would be missing its source data. Wait for the user to
        // allow it.
        if (hasUsageStatsPermission(this)) {
            DailyFootprintWorker.runNow(applicationContext)
        }

        setContent {
            App()
        }
    }

    // [03] Returning to the app is another chance to start tracking if Android blocked an earlier
    // background start.
    override fun onResume() {
        super.onResume()
        TrackingService.start(this)
    }
}

// [04] This preview lets a developer inspect the Android screens without using a phone.
@Preview
@Composable
fun AppAndroidPreview() {
    App()
}

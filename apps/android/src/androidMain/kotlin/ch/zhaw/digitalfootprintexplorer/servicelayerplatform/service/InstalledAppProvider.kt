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
import android.content.pm.ApplicationInfo
import android.os.Build
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.datasource.APP_CATEGORY_CONFIG
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.datasource.AndroidLauncherAppQuery
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.datasource.LauncherAppQuery
import ch.zhaw.digitalfootprintexplorer.model.AppCategory
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.model.App

// [01] Give each launchable Android app a display name and a model category before collecting its usage.
class InstalledAppProvider(
    private val launcherAppQuery: LauncherAppQuery = AndroidLauncherAppQuery()
) {

    fun getInstalledLauncherApps(context: Context): List<App> {
        return launcherAppQuery.create(context)
            .map { resolveInfo ->
                val appInfo = resolveInfo.activityInfo.applicationInfo
                generateApp(context = context, applicationInfo = appInfo)
            }

            // [02] Several visible apps can share one Android traffic identity. Counting that identity
            // twice would inflate traffic.
            .distinctBy { it.uid }
    }

    private fun generateApp(context: Context, applicationInfo: ApplicationInfo): App {
        val foundCategory = compareAppCategoryConfigWithPackageName(packageName = applicationInfo.packageName)

        // [03] A readable local app name is easier to recognise. The package name is a fallback if Android
        // cannot supply a label.
        val appName = runCatching {
            context.packageManager.getApplicationLabel(applicationInfo).toString()
        }.getOrDefault(applicationInfo.packageName)

        return App(
            uid         = applicationInfo.uid,
            name        = appName,
            packageName = applicationInfo.packageName,
            category    = if (foundCategory != AppCategory.MISCELLANEOUS) foundCategory else selectAppCategory(applicationInfo)
        )
    }

    // [04] Use Android's category when available; apps without a supported category stay in Other.
    private fun selectAppCategory(applicationInfo: ApplicationInfo): AppCategory {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return AppCategory.MISCELLANEOUS

        return when(applicationInfo.category) {
            ApplicationInfo.CATEGORY_GAME -> AppCategory.GAMING
            ApplicationInfo.CATEGORY_AUDIO -> AppCategory.AUDIO_STREAMING
            ApplicationInfo.CATEGORY_VIDEO -> AppCategory.VIDEO_STREAMING
            ApplicationInfo.CATEGORY_SOCIAL -> AppCategory.SOCIAL_MEDIA
            ApplicationInfo.CATEGORY_MAPS -> AppCategory.NAVIGATION
            ApplicationInfo.CATEGORY_NEWS,
            ApplicationInfo.CATEGORY_PRODUCTIVITY,
            ApplicationInfo.CATEGORY_ACCESSIBILITY -> AppCategory.MISCELLANEOUS
            else -> AppCategory.MISCELLANEOUS
        }
    }

    private fun selectAppCategoryFromAppCategoryConfig(category: String): AppCategory {
        return when(category) {
            "AI" -> AppCategory.ARTIFICIAL_INTELLIGENCE
            "Mail" -> AppCategory.E_MAIL
            "Messaging" -> AppCategory.MESSAGING
            "Video_Call" -> AppCategory.VIDEO_CALL
            else -> AppCategory.MISCELLANEOUS
        }
    }

    // [05] Known named exceptions take priority, but an unlisted app must still have a category.
    private fun compareAppCategoryConfigWithPackageName(packageName: String): AppCategory {
        APP_CATEGORY_CONFIG.forEach {
            (category, packageNames) -> if (packageName in packageNames)
                return selectAppCategoryFromAppCategoryConfig(category)
        }
        return AppCategory.MISCELLANEOUS
    }
}

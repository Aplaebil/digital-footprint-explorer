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

package ch.zhaw.digitalfootprintexplorer.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.unit.ColorProvider
import ch.zhaw.digitalfootprintexplorer.ui.theme.surfaceContainerLowDark
import ch.zhaw.digitalfootprintexplorer.MainActivity
import ch.zhaw.digitalfootprintexplorer.R
import ch.zhaw.digitalfootprintexplorer.model.GardenState

// [01] The Android Home Screen garden shows the saved daily state and opens the app when tapped.
class GardenWidget : GlanceAppWidget() {

    // [02] Let the widget framework watch its saved state, so a new result can trigger a redraw rather than
    // leaving an old picture.
    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {

            // [03] Read state inside the widget content so the next redraw can pick up a changed garden.
            val prefs     = currentState<Preferences>()
            val stateName = prefs[KEY_STATE] ?: GardenState.FLOURISHING.name
            val state     = runCatching { GardenState.valueOf(stateName) }.getOrDefault(GardenState.FLOURISHING)
            GardenContent(state)
        }
    }

    @Composable
    // [04] Use the same five garden pictures as the app, making the Home Screen summary familiar.
    private fun GardenContent(state: GardenState) {
        val imageRes = when (state) {
            GardenState.FLOURISHING -> R.drawable.garden_state_1_flourishing
            GardenState.GROWING     -> R.drawable.garden_state_2_growing
            GardenState.STABLE      -> R.drawable.garden_state_3_stable
            GardenState.WILTING     -> R.drawable.garden_state_4_wilting
            GardenState.WITHERED    -> R.drawable.garden_state_5_withered
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ColorProvider(surfaceContainerLowDark))
                .clickable(actionStartActivity<MainActivity>()),
            contentAlignment = Alignment.Center
        ) {
            Image(
                provider = ImageProvider(imageRes),
                contentDescription = state.name,
                modifier = GlanceModifier.fillMaxSize(),
                contentScale = ContentScale.Fit
            )
        }
    }

    companion object {
        private val KEY_STATE = stringPreferencesKey("garden_state")

        // [05] Save the new state for every placed widget before asking Android to redraw each one.
        suspend fun updateState(context: Context, state: GardenState) {
            GlanceAppWidgetManager(context)
                .getGlanceIds(GardenWidget::class.java)
                .forEach { id ->
                    updateAppWidgetState(context, PreferencesGlanceStateDefinition, id) { prefs ->
                        prefs.toMutablePreferences().also { it[KEY_STATE] = state.name }
                    }
                    GardenWidget().update(context, id)
                }
        }
    }
}

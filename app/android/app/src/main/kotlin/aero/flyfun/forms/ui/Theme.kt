package aero.flyfun.forms.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

/**
 * Material You: the wallpaper's colours, light or dark with the system.
 *
 * Dynamic colour needs API 31 and the app's minimum is 33, so there is no
 * fallback palette to keep in step with the icon. The app has no brand colour
 * beyond the icon, and matching the rest of the phone is what an Android app is
 * expected to do.
 */
@Composable
fun FlyFunTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val colors = if (isSystemInDarkTheme()) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    MaterialTheme(colorScheme = colors, content = content)
}

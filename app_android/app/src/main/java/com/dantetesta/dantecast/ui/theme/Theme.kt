package com.dantetesta.dantecast.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/**
 * Tema Material 3 da marca Dante Cast, ciente de dark/light mode.
 * Optamos por NÃO usar dynamic color para manter a identidade da marca consistente.
 */

private val DarkColors = darkColorScheme(
    primary = BrandPurpleLight,
    onPrimary = BrandPurpleDark,
    primaryContainer = BrandPurpleDark,
    onPrimaryContainer = OnDark,
    secondary = BrandCyan,
    onSecondary = Color(0xFF003733),
    secondaryContainer = BrandCyanDark,
    onSecondaryContainer = OnDark,
    background = SurfaceDark,
    onBackground = OnDark,
    surface = SurfaceDark,
    onSurface = OnDark,
    surfaceVariant = SurfaceDarkElevated,
    onSurfaceVariant = BrandPurpleLight,
    error = ErrorRed,
    onError = Color.White
)

private val LightColors = lightColorScheme(
    primary = BrandPurple,
    onPrimary = Color.White,
    primaryContainer = BrandPurpleLight,
    onPrimaryContainer = BrandPurpleDark,
    secondary = BrandCyanDark,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFB8F4EC),
    onSecondaryContainer = Color(0xFF00201D),
    background = SurfaceLight,
    onBackground = OnLight,
    surface = SurfaceLight,
    onSurface = OnLight,
    surfaceVariant = Color(0xFFEAE6F7),
    onSurfaceVariant = BrandPurpleDark,
    error = ErrorRed,
    onError = Color.White
)

@Composable
fun DanteCastTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColors else LightColors

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            // Barras de sistema transparentes; ícones claros/escuros conforme o tema.
            WindowCompat.setDecorFitsSystemWindows(window, false)
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = !darkTheme
            controller.isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        content = content
    )
}

package ai.opentype.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import ai.opentype.android.model.AppTheme

private fun accent(theme: AppTheme): Color = when (theme) {
    AppTheme.OCEAN -> Color(0xFF087AFF)
    AppTheme.VIOLET -> Color(0xFF7357FF)
    AppTheme.MINT -> Color(0xFF008E74)
    AppTheme.SUNSET -> Color(0xFFE65D37)
    AppTheme.SAKURA -> Color(0xFFD84F84)
    AppTheme.GRAPHITE -> Color(0xFF52606D)
}

@Composable
fun OpenTypeTheme(
    theme: AppTheme,
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val primary = accent(theme)
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = primary.copy(red = (primary.red + 0.22f).coerceAtMost(1f)),
            secondary = primary,
            background = Color(0xFF111318),
            surface = Color(0xFF191C22),
            surfaceVariant = Color(0xFF252930),
            onBackground = Color(0xFFF4F6FA),
            onSurface = Color(0xFFF4F6FA)
        )
    } else {
        lightColorScheme(
            primary = primary,
            secondary = primary,
            background = Color(0xFFF8FAFF),
            surface = Color(0xFFFFFFFF),
            surfaceVariant = Color(0xFFF0F2F7),
            onBackground = Color(0xFF16181D),
            onSurface = Color(0xFF16181D)
        )
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}

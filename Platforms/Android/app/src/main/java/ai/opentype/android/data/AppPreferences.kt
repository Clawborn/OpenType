package ai.opentype.android.data

import android.content.Context
import android.content.SharedPreferences
import ai.opentype.android.model.AppSettings
import ai.opentype.android.model.AppTheme
import ai.opentype.android.model.InputMode
import ai.opentype.android.model.InterfaceLanguage
import ai.opentype.android.model.TextProvider

class AppPreferences(context: Context) {
    private val preferences: SharedPreferences = context.applicationContext
        .getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    fun load(): AppSettings {
        val provider = TextProvider.fromId(preferences.getString(KEY_PROVIDER, null))
        return AppSettings(
            interfaceLanguage = InterfaceLanguage.fromId(preferences.getString(KEY_LANGUAGE, null)),
            theme = AppTheme.fromId(preferences.getString(KEY_THEME, null)),
            mode = InputMode.fromId(preferences.getString(KEY_MODE, null)),
            provider = provider,
            endpoint = preferences.getString(KEY_ENDPOINT, null)?.takeIf { it.isNotBlank() }
                ?: provider.defaultEndpoint,
            model = preferences.getString(KEY_MODEL, null)?.takeIf { it.isNotBlank() }
                ?: provider.defaultModel,
            recognitionLanguage = preferences.getString(KEY_RECOGNITION_LANGUAGE, "auto") ?: "auto",
            includeRecentTasks = preferences.getBoolean(KEY_RECENT_TASKS, true)
        )
    }

    fun save(settings: AppSettings) {
        preferences.edit()
            .putString(KEY_LANGUAGE, settings.interfaceLanguage.id)
            .putString(KEY_THEME, settings.theme.id)
            .putString(KEY_MODE, settings.mode.id)
            .putString(KEY_PROVIDER, settings.provider.id)
            .putString(KEY_ENDPOINT, settings.endpoint.trim())
            .putString(KEY_MODEL, settings.model.trim())
            .putString(KEY_RECOGNITION_LANGUAGE, settings.recognitionLanguage)
            .putBoolean(KEY_RECENT_TASKS, settings.includeRecentTasks)
            .apply()
    }

    fun setMode(mode: InputMode) {
        preferences.edit().putString(KEY_MODE, mode.id).apply()
    }

    companion object {
        private const val FILE_NAME = "opentype_preferences"
        private const val KEY_LANGUAGE = "interface_language"
        private const val KEY_THEME = "theme"
        private const val KEY_MODE = "mode"
        private const val KEY_PROVIDER = "text_provider"
        private const val KEY_ENDPOINT = "text_endpoint"
        private const val KEY_MODEL = "text_model"
        private const val KEY_RECOGNITION_LANGUAGE = "recognition_language"
        private const val KEY_RECENT_TASKS = "include_recent_tasks"
    }
}

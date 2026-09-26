package aero.flyfun.forms.data

import aero.flyfun.forms.logic.SpokenLanguages
import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Small app settings, in SharedPreferences: one string today. DataStore would
 * be a new dependency for a value this size.
 */
class Preferences(context: Context) {

    private val prefs = context.getSharedPreferences("flyfun-settings", Context.MODE_PRIVATE)

    private val _spokenLanguages = MutableStateFlow(SpokenLanguages.parse(prefs.getString(KEY_SPOKEN, null)))

    /** ISO 639-1 codes of the languages the pilot speaks besides English. */
    val spokenLanguages: StateFlow<Set<String>> = _spokenLanguages.asStateFlow()

    fun setSpeaks(code: String, speaks: Boolean) {
        val codes = if (speaks) _spokenLanguages.value + code else _spokenLanguages.value - code
        prefs.edit().putString(KEY_SPOKEN, SpokenLanguages.serialize(codes)).apply()
        _spokenLanguages.value = codes
    }

    private companion object {
        /** The iOS `@AppStorage` key, so the two read alike. */
        const val KEY_SPOKEN = "spokenLanguageCodes"
    }
}

package aero.flyfun.forms.logic

import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * A trip's form extras: stored as a JSON-encoded map on the Room row, as iOS
 * stores `Trip.extraFieldsData`, and carried as a plain map in the interchange
 * file.
 */
object TripExtras {

    private val serializer = MapSerializer(String.serializer(), String.serializer())
    private val json = Json { ignoreUnknownKeys = true }

    /** Unreadable JSON reads as empty, as `Trip.extraFields` does on iOS. */
    fun decode(stored: String?): Map<String, String> {
        if (stored.isNullOrBlank()) return emptyMap()
        return runCatching { json.decodeFromString(serializer, stored) }.getOrDefault(emptyMap())
    }

    /** Null for an empty map, so a trip without extras keeps a null column. */
    fun encode(extras: Map<String, String>): String? =
        if (extras.isEmpty()) null else json.encodeToString(serializer, extras)
}

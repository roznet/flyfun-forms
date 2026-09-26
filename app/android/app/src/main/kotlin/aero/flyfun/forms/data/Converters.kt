package aero.flyfun.forms.data

import androidx.room.TypeConverter
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate

/**
 * Two date shapes, kept deliberately distinct.
 *
 * [LocalDate] is a calendar day - a date of birth, a passport expiry. Those are
 * facts printed on a document and carry no timezone; giving them one is how
 * someone ends up born a day earlier in Sydney. Stored as ISO `YYYY-MM-DD`,
 * matching the interchange format in designs/future/move-my-data.md.
 *
 * [Instant] is an absolute moment - a departure, a row's updatedAt. Stored as
 * epoch millis so range queries and ordering are cheap.
 */
class Converters {
    @TypeConverter
    fun localDateFromString(value: String?): LocalDate? = value?.let(LocalDate::parse)

    @TypeConverter
    fun localDateToString(value: LocalDate?): String? = value?.toString()

    @TypeConverter
    fun instantFromEpochMillis(value: Long?): Instant? = value?.let(Instant::ofEpochMilli)

    @TypeConverter
    fun instantToEpochMillis(value: Instant?): Long? = value?.toEpochMilli()

    /** A JSON array: document numbers are free text, so no separator is safe. */
    @TypeConverter
    fun stringListFromJson(value: String?): List<String>? = value?.let { Json.decodeFromString<List<String>>(it) }

    @TypeConverter
    fun stringListToJson(value: List<String>?): String? = value?.let { Json.encodeToString(it) }
}

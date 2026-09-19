package aero.flyfun.forms.net

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

// --- GET /airports ---

@Serializable
data class AirportCatalogResponse(
    val airports: List<AirportInfo> = emptyList(),
    val prefixes: List<PrefixInfo> = emptyList(),
)

@Serializable
data class AirportInfo(val icao: String, val name: String, val forms: List<String> = emptyList())

@Serializable
data class PrefixInfo(val prefix: String, val country: String, val forms: List<String> = emptyList())

// --- GET /airports/{icao} ---

@Serializable
data class AirportDetailResponse(
    val icao: String,
    val name: String,
    val forms: List<FormInfo> = emptyList(),
)

@Serializable
data class EmailConfig(val to: List<String> = emptyList(), val cc: List<String> = emptyList())

@Serializable
data class FormInfo(
    val id: String,
    val label: String,
    val version: String = "",
    @SerialName("required_fields") val requiredFields: RequiredFields = RequiredFields(),
    @SerialName("extra_fields") val extraFields: List<ExtraFieldInfo> = emptyList(),
    @SerialName("max_crew") val maxCrew: Int = 0,
    @SerialName("max_passengers") val maxPassengers: Int = 0,
    @SerialName("has_connecting_flight") val hasConnectingFlight: Boolean = false,
    /** Optional so an older server keeps parsing. */
    @SerialName("has_return_flight") val hasReturnFlight: Boolean? = null,
    @SerialName("time_reference") val timeReference: String = "utc",
    @SerialName("send_to") val sendTo: String? = null,
    val email: EmailConfig? = null,
    /** "document" or "web". Optional so an older server keeps parsing. */
    val kind: String? = null,
    /** "departure" / "arrival" when the form only applies one way. */
    val direction: String? = null,
) {
    val isWebForm: Boolean get() = kind == "web"
}

@Serializable
data class RequiredFields(
    val flight: List<String> = emptyList(),
    val aircraft: List<String> = emptyList(),
    val crew: List<String> = emptyList(),
    val passengers: List<String> = emptyList(),
)

@Serializable
data class ExtraFieldInfo(
    val key: String,
    val label: String,
    val type: String,
    val options: List<String>? = null,
    @SerialName("maps_to") val mapsTo: Map<String, String>? = null,
)

// --- POST /prefill ---

@Serializable
data class FillPlan(
    val form: String,
    val label: String,
    val url: String,
    /** CSS selector of the <form> to fill, for pages holding several. */
    val scope: String? = null,
    /** Shown to the pilot above the page. */
    val note: String? = null,
    val fields: List<FillField> = emptyList(),
)

@Serializable
data class FillField(val name: String, val value: String, val type: String = "text")

// --- Extra field values: a string, or a person dictionary ---

/**
 * The server accepts either shape for an extra field, so the wire form is a
 * bare string or a bare object rather than a tagged union.
 */
@Serializable(with = ExtraFieldValueSerializer::class)
sealed interface ExtraFieldValue {
    @JvmInline value class Text(val value: String) : ExtraFieldValue
    @JvmInline value class Person(val value: Map<String, String>) : ExtraFieldValue
}

object ExtraFieldValueSerializer : KSerializer<ExtraFieldValue> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("ExtraFieldValue")

    override fun serialize(encoder: Encoder, value: ExtraFieldValue) {
        val json = encoder as? JsonEncoder ?: error("ExtraFieldValue requires JSON")
        when (value) {
            is ExtraFieldValue.Text -> json.encodeJsonElement(JsonPrimitive(value.value))
            is ExtraFieldValue.Person ->
                json.encodeSerializableValue(
                    MapSerializer(String.serializer(), String.serializer()),
                    value.value,
                )
        }
    }

    override fun deserialize(decoder: Decoder): ExtraFieldValue {
        val json = decoder as? JsonDecoder ?: error("ExtraFieldValue requires JSON")
        return when (val element = json.decodeJsonElement()) {
            is JsonObject -> ExtraFieldValue.Person(
                element.mapValues { (_, v) -> v.jsonPrimitive.content },
            )
            is JsonPrimitive -> ExtraFieldValue.Text(element.content)
            else -> ExtraFieldValue.Text("")
        }
    }
}

// --- POST /email-text ---

@Serializable
data class EmailTextRequest(
    val airport: String,
    val form: String,
    val origin: String,
    val destination: String,
    @SerialName("departure_date") val departureDate: String,
    val registration: String,
    @SerialName("aircraft_type") val aircraftType: String? = null,
)

@Serializable
data class EmailTextResponse(
    @SerialName("subject_en") val subjectEn: String = "",
    @SerialName("body_en") val bodyEn: String = "",
    @SerialName("subject_local") val subjectLocal: String = "",
    @SerialName("body_local") val bodyLocal: String = "",
    /** ISO 639-1 for the airport's language, or null when English/unknown. */
    @SerialName("local_language") val localLanguage: String? = null,
)

// --- POST /generate, /validate, /prefill ---

@Serializable
data class GenerateRequest(
    val airport: String,
    val form: String,
    val flight: FlightPayload,
    val aircraft: AircraftPayload,
    val crew: List<PersonPayload> = emptyList(),
    val passengers: List<PersonPayload> = emptyList(),
    @SerialName("connecting_flight") val connectingFlight: FlightPayload? = null,
    @SerialName("return_flight") val returnFlight: ReturnFlightPayload? = null,
    @SerialName("extra_fields") val extraFields: Map<String, ExtraFieldValue>? = null,
    val observations: String? = null,
)

@Serializable
data class FlightPayload(
    val origin: String,
    val destination: String,
    @SerialName("departure_date") val departureDate: String,
    @SerialName("departure_time_utc") val departureTimeUtc: String,
    @SerialName("arrival_date") val arrivalDate: String,
    @SerialName("arrival_time_utc") val arrivalTimeUtc: String,
    val nature: String? = null,
    val contact: String? = null,
)

@Serializable
data class ReturnFlightPayload(
    val origin: String,
    val destination: String,
    @SerialName("departure_date") val departureDate: String,
    @SerialName("departure_time_utc") val departureTimeUtc: String,
    @SerialName("arrival_date") val arrivalDate: String,
    @SerialName("arrival_time_utc") val arrivalTimeUtc: String,
    @SerialName("people_on_board") val peopleOnBoard: Int,
)

@Serializable
data class AircraftPayload(
    val registration: String,
    val type: String,
    val owner: String? = null,
    @SerialName("owner_address") val ownerAddress: String? = null,
    @SerialName("is_airplane") val isAirplane: Boolean? = null,
    @SerialName("usual_base") val usualBase: String? = null,
)

@Serializable
data class PersonPayload(
    val function: String? = null,
    @SerialName("first_name") val firstName: String,
    @SerialName("last_name") val lastName: String,
    val dob: String? = null,
    val nationality: String? = null,
    @SerialName("id_number") val idNumber: String? = null,
    @SerialName("id_type") val idType: String? = null,
    @SerialName("id_issuing_country") val idIssuingCountry: String? = null,
    @SerialName("id_expiry") val idExpiry: String? = null,
    val sex: String? = null,
    @SerialName("place_of_birth") val placeOfBirth: String? = null,
    val address: String? = null,
)

// --- 422 validation errors ---

@Serializable
data class ValidationErrorEnvelope(val detail: List<ServerValidationError> = emptyList())

@Serializable
data class ServerValidationError(
    val field: String = "",
    val error: String = "",
    val value: String? = null,
)

/**
 * Turns an API field path into something a pilot can act on:
 * `crew[0].id_number` becomes "Crew 1 - ID Number".
 *
 * An extension rather than a member: presentation logic does not belong on a
 * wire type, and a computed member on a @Serializable class is a property the
 * serialization plugin has an opinion about.
 */
val ServerValidationError.displayField: String
    get() {
        val match = Regex("^(\\w+)\\[(\\d+)]\\.(.+)\$").find(field)
        if (match != null) {
            val (section, index, leaf) = match.destructured
            return "${section.humanise()} ${index.toInt() + 1} - ${leaf.humanise()}"
        }
        return field.substringAfterLast('.').humanise().ifBlank { field }
    }

private fun String.humanise(): String =
    split('_', '.')
        .filter { it.isNotEmpty() }
        .joinToString(" ") { part ->
            when (part.lowercase()) {
                "id" -> "ID"
                "icao" -> "ICAO"
                "utc" -> "UTC"
                "dob" -> "Date of Birth"
                else -> part.replaceFirstChar { it.uppercaseChar() }
            }
        }

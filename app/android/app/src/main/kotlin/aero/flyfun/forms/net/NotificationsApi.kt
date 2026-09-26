package aero.flyfun.forms.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.GET
import retrofit2.http.Path

/**
 * Airport notices (customs notification rules, PPR and the like) from the
 * FlyFun maps service, shown under the route as iOS does
 * (`FlightEditView.fetchNotification`). Public: no token is sent there.
 */
interface NotificationsApi {
    @GET("api/notifications/{icao}")
    suspend fun notification(@Path("icao") icao: String): NotificationInfo
}

@Serializable
data class NotificationInfo(
    val found: Boolean = false,
    val icao: String = "",
    val summary: String? = null,
    @SerialName("raw_text") val rawText: String? = null,
    val pretty: String? = null,
)

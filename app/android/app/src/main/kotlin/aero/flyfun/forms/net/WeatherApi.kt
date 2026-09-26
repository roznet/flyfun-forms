package aero.flyfun.forms.net

import aero.flyfun.forms.R
import aero.flyfun.forms.logic.FlightExchange
import aero.flyfun.forms.logic.WeatherFlightSummary
import android.content.res.Resources
import androidx.annotation.StringRes
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.Path

/**
 * FlyFun Weather (`weather.flyfun.aero`), as the "Import from FlyFun Weather"
 * method uses it: the pilot's flights, and one of them in the cross-app
 * `FlightExchange` format. Port of iOS `WeatherImportService`.
 *
 * Bodies stay raw: `:core-logic` decodes them, where the format is tested.
 */
interface WeatherApi {
    @GET("api/flights")
    suspend fun flights(): Response<ResponseBody>

    @GET("api/flights/{id}/export")
    suspend fun export(@Path("id") id: String): Response<ResponseBody>
}

/** A failed weather call, with what to tell the pilot as a string resource. */
class WeatherImportException(@StringRes val text: Int, private vararg val args: Any) : Exception() {
    fun message(resources: Resources): String = resources.getString(text, *args)
}

/** The pilot's weather flights, newest departure first. */
suspend fun WeatherApi.listFlights(): List<WeatherFlightSummary> {
    val response = flights()
    return WeatherFlightSummary.decodeList(response.bodyOrThrow())
}

/** One weather flight as a `FlightExchange`. */
suspend fun WeatherApi.exportFlight(id: String): FlightExchange {
    val response = export(id)
    if (response.code() == 422) throw WeatherImportException(R.string.app_weather_no_route)
    val body = response.bodyOrThrow()
    return runCatching { FlightExchange.decode(body) }.getOrElse {
        throw WeatherImportException(R.string.app_weather_unreadable, it.message.orEmpty())
    }
}

private fun Response<ResponseBody>.bodyOrThrow(): String {
    if (code() == 401) throw WeatherImportException(R.string.app_weather_sign_in)
    if (!isSuccessful) {
        val detail = errorBody()?.string()?.take(200)?.takeIf { it.isNotBlank() }?.let { ": $it" }.orEmpty()
        throw WeatherImportException(R.string.app_weather_server_error, code(), detail)
    }
    return body()?.string() ?: throw WeatherImportException(R.string.app_weather_empty)
}

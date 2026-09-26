package aero.flyfun.forms.net

import aero.flyfun.forms.logic.FlightExchange
import aero.flyfun.forms.logic.WeatherFlightSummary
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

/** A failed weather call, with what to tell the pilot. */
class WeatherImportException(message: String) : Exception(message)

/** The pilot's weather flights, newest departure first. */
suspend fun WeatherApi.listFlights(): List<WeatherFlightSummary> {
    val response = flights()
    return WeatherFlightSummary.decodeList(response.bodyOrThrow())
}

/** One weather flight as a `FlightExchange`. */
suspend fun WeatherApi.exportFlight(id: String): FlightExchange {
    val response = export(id)
    if (response.code() == 422) throw WeatherImportException("This flight has no route to import.")
    return runCatching { FlightExchange.decode(response.bodyOrThrow()) }.getOrElse {
        if (it is WeatherImportException) throw it
        throw WeatherImportException(it.message ?: "That flight could not be read.")
    }
}

private fun Response<ResponseBody>.bodyOrThrow(): String {
    if (code() == 401) {
        throw WeatherImportException("Sign in to the same FlyFun account to import your weather flights.")
    }
    if (!isSuccessful) {
        val detail = errorBody()?.string()?.take(200)?.takeIf { it.isNotBlank() }?.let { ": $it" }.orEmpty()
        throw WeatherImportException("Weather server error (${code()})$detail")
    }
    return body()?.string() ?: throw WeatherImportException("Weather server sent nothing back.")
}

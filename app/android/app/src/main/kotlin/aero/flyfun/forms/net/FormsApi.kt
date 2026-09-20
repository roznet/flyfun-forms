package aero.flyfun.forms.net

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/** The flyfun-forms server, as this app uses it. See designs/api.md. */
interface FormsApi {

    @GET("airports")
    suspend fun airports(): AirportCatalogResponse

    @GET("airports/{icao}")
    suspend fun airport(
        @Path("icao") icao: String,
        @Query("include_web") includeWeb: Boolean = true,
    ): AirportDetailResponse

    /** Returns the filled file itself (PDF/DOCX/XLSX), so the body stays raw. */
    @POST("generate")
    suspend fun generate(
        @Body request: GenerateRequest,
        @Query("flatten") flatten: Boolean = true,
    ): Response<ResponseBody>

    @POST("validate")
    suspend fun validate(@Body request: GenerateRequest): Response<Unit>

    @POST("prefill")
    suspend fun prefill(@Body request: GenerateRequest): FillPlan

    @POST("email-text")
    suspend fun emailText(@Body request: EmailTextRequest): EmailTextResponse
}

@kotlinx.serialization.Serializable
data class ExchangeRequest(val code: String, val state: String)

@kotlinx.serialization.Serializable
data class ExchangeResponse(val token: String, @kotlinx.serialization.SerialName("user_id") val userId: String)

@kotlinx.serialization.Serializable
data class MeResponse(
    val id: String = "",
    val email: String = "",
    @kotlinx.serialization.SerialName("display_name") val displayName: String? = null,
)

interface AuthApi {
    /**
     * Trades the short-TTL auth code for the session JWT.
     *
     * The code, not the token, comes back through the redirect: on Android any
     * app can register the `flyfunforms` scheme, so a token in the URL would be
     * interceptable. See flyfun-common designs/oauth-deeplink-hardening.md.
     */
    @POST("auth/exchange")
    suspend fun exchange(@Body request: ExchangeRequest): ExchangeResponse

    @GET("auth/me")
    suspend fun me(): MeResponse

    @POST("auth/logout")
    suspend fun logout(): Response<Unit>
}

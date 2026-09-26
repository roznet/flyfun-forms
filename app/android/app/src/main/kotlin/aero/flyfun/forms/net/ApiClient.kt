package aero.flyfun.forms.net

import aero.flyfun.forms.auth.TokenStore
import kotlinx.serialization.json.Json
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import java.util.concurrent.TimeUnit

object ApiConfig {
    /**
     * Production. The iOS app points the simulator at a local dev server; the
     * Android emulator cannot resolve `localhost.ro-z.me` to the host, so a dev
     * build would use 10.0.2.2 instead.
     */
    const val BASE_URL = "https://forms.flyfun.aero/"

    /** Airport notices; see [NotificationsApi]. */
    const val MAPS_URL = "https://maps.flyfun.aero/"

    /** Reused from iOS: the allowlist already contains it, and the two platforms cannot collide on one device. */
    const val CALLBACK_SCHEME = "flyfunforms"
    const val CALLBACK_URL = "$CALLBACK_SCHEME://auth/callback"
}

class ApiClient(private val tokens: TokenStore, baseUrl: String = ApiConfig.BASE_URL) {

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    /**
     * Attaches the bearer token when there is one; requests before sign-in go
     * out bare.
     *
     * A 401 to a request that carried a token means the session is over
     * (expired, revoked, account deleted elsewhere). The token is dropped, and
     * the UI, which observes [TokenStore.signedIn], goes back to sign-in -
     * rather than every later request failing with the same 401.
     */
    private val authInterceptor = Interceptor { chain ->
        val token = tokens.token
        val request = if (token != null) {
            chain.request().newBuilder().addHeader("Authorization", "Bearer $token").build()
        } else {
            chain.request()
        }
        val response = chain.proceed(request)
        if (response.code == 401 && token != null) tokens.clearIfCurrent(token)
        response
    }

    private val http = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .connectTimeout(20, TimeUnit.SECONDS)
        // Form generation renders a PDF server-side, which is slower than a
        // plain JSON round trip.
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private val retrofit = Retrofit.Builder()
        .baseUrl(baseUrl)
        .client(http)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()

    val forms: FormsApi = retrofit.create(FormsApi::class.java)
    val auth: AuthApi = retrofit.create(AuthApi::class.java)

    /** Another service, so its own client: the forms token must not travel there. */
    val notifications: NotificationsApi = Retrofit.Builder()
        .baseUrl(ApiConfig.MAPS_URL)
        .client(OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).build())
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(NotificationsApi::class.java)

    /** Parses a 422 body into the structured errors the UI shows. */
    fun parseValidationErrors(body: String): List<ServerValidationError> = runCatching {
        json.decodeFromString(ValidationErrorEnvelope.serializer(), body).detail
    }.getOrElse { emptyList() }
}

package aero.flyfun.forms.logic

/**
 * The languages a pilot may say they speak beyond English, and how that picks
 * the language of a form's covering e-mail. Port of iOS `SpokenLanguage`,
 * `SpokenLanguageStorage` and the body choice in `generateAndEmail`.
 */
object SpokenLanguages {

    /** ISO 639-1, matching the server's `local_language`, with each language's own name. */
    val ALL: List<Pair<String, String>> = listOf(
        "fr" to "Français",
        "de" to "Deutsch",
        "it" to "Italiano",
        "es" to "Español",
        "pt" to "Português",
        "nl" to "Nederlands",
    )

    /** Comma-separated, as iOS stores `spokenLanguageCodes`. */
    fun parse(stored: String?): Set<String> =
        stored.orEmpty().split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet()

    fun serialize(codes: Set<String>): String = codes.sorted().joinToString(",")
}

object EmailText {

    data class Message(val subject: String, val body: String)

    /**
     * The server's text, in the airport's language when the pilot speaks it
     * and English otherwise. The local subject is used either way, as on
     * iOS: it is codes and dates, and some airports mandate it word for word.
     */
    fun choose(
        localLanguage: String?,
        spoken: Set<String>,
        subjectEn: String,
        subjectLocal: String,
        bodyEn: String,
        bodyLocal: String,
    ): Message {
        val speaksLocal = !localLanguage.isNullOrBlank() && localLanguage in spoken
        return Message(
            subject = subjectLocal.ifBlank { subjectEn },
            body = if (speaksLocal) bodyLocal.ifBlank { bodyEn } else bodyEn,
        )
    }

    /** When `/email-text` cannot be reached. Same wording as iOS `emailSubject` / `emailBody`. */
    fun fallback(
        formLabel: String,
        origin: String,
        destination: String,
        departureDate: String,
        registration: String,
    ): Message = Message(
        subject = "$formLabel - $destination - $departureDate - $registration",
        body = "Please find attached the $formLabel for flight $origin → $destination " +
            "on $departureDate, aircraft $registration.",
    )
}

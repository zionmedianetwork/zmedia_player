package com.zionmedianetwork.zmedia_player

/**
 * Strips query-string parameters from URLs before they reach a log line.
 *
 * `android.util.Log.d/.v/.i` calls are already removed from release builds
 * entirely by the `-assumenosideeffects` ProGuard rule in `proguard-rules.pro`
 * (see H-03), so debug-level "Loading media: $url" style logs never ship.
 * `Log.e`/`Log.w` are intentionally kept for crash diagnostics and are NOT
 * stripped, but the exception messages they print (from network, DRM and
 * media-loading failures) frequently embed the offending request URL —
 * which can carry signed-cookie or DRM auth tokens in its query string.
 * Call sites that log such messages should route them through
 * [redactUrls] first so only the scheme/host/path survive.
 */
object LogSanitizer {

    private val URL_REGEX = Regex("""https?://[^\s"'<>)]+""")

    /**
     * Returns [message] with the query string of any embedded URL replaced by
     * `?<redacted>`. Text that contains no URL is returned unchanged. Safe to
     * call with `null`.
     */
    fun redactUrls(message: String?): String {
        if (message.isNullOrEmpty()) return message ?: ""
        return URL_REGEX.replace(message) { redactQuery(it.value) }
    }

    /** Strips the query string (and everything after `?`) from a single URL. */
    fun redactQuery(url: String): String {
        val queryIndex = url.indexOf('?')
        return if (queryIndex >= 0) url.substring(0, queryIndex) + "?<redacted>" else url
    }
}

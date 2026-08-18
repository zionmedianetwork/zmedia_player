package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.media3.common.C
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManager
import androidx.media3.exoplayer.drm.ExoMediaDrm
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.common.util.Util
import io.flutter.plugin.common.MethodChannel
import okhttp3.CertificatePinner
import okhttp3.OkHttpClient
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Handles DRM (Digital Rights Management) for media playback.
 * Supports Widevine, PlayReady, and ClearKey DRM schemes for ExoPlayer v2.
 *
 * When [drmConfig] contains a "certificatePinning" map (populated from
 * [DrmConfig.toMap]), licence requests are made through an OkHttpClient
 * whose [CertificatePinner] enforces SHA-256 / SPKI pins.  Without that
 * key the existing [DefaultHttpDataSource] path is used unchanged.
 *
 * Pin wire-format: lowercase hex string of SHA-256(DER SubjectPublicKeyInfo).
 * This is the same format stored in CertificatePinningConfig.pins on the
 * Dart side.  OkHttp requires "sha256/<base64>" so each hex pin is converted:
 *     hex bytes → raw bytes → standard Base64 (no padding stripped).
 */
class DrmHandler(
    private val context: Context,
    private val playerId: String,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "DrmHandler"

        // DRM scheme UUIDs
        val WIDEVINE_UUID: UUID = C.WIDEVINE_UUID
        val PLAYREADY_UUID: UUID = C.PLAYREADY_UUID
        val CLEARKEY_UUID: UUID = C.CLEARKEY_UUID

        private const val USER_AGENT = "FlutterMediaPlayer"
    }

    /**
     * Create DRM session manager for ExoPlayer v2.
     */
    fun createDrmSessionManager(
        drmConfig: Map<String, Any>?
    ): DrmSessionManager? {
        if (drmConfig == null) {
            return null
        }

        // Wave 2 security hardening (gate item: "Wire validateDrmConfig /
        // getWidevineSecurityLevel into the load path with a fail-closed
        // minimum-security-level policy"). validateDrmConfig() previously
        // existed but was never called from anywhere in the load path — see
        // its own doc for what it now enforces, including the opt-in
        // minWidevineSecurityLevel policy. Structural checks (URL format,
        // HTTPS) already ran on the Dart side (InputValidator.validateDrmConfig);
        // this adds checks only native code can make: whether this device
        // actually supports the requested DRM scheme, and whether its actual
        // Widevine security level satisfies the configured minimum. On
        // failure we refuse to build a DrmSessionManager at all — the caller
        // (MediaPlayerInstance.loadMediaItem) must NOT fall back to loading
        // the item without DRM protection.
        val (isValid, validationError) = validateDrmConfig(drmConfig)
        if (!isValid) {
            Log.e(TAG, "DRM configuration rejected: $validationError")
            notifyDrmError(validationError ?: "DRM configuration is invalid")
            return null
        }

        val scheme = drmConfig["scheme"] as? String ?: "widevine"
        val licenseUrl = drmConfig["licenseUrl"] as? String
            ?: run {
                Log.e(TAG, "License URL is required for DRM")
                notifyDrmError("License URL is required for DRM")
                return null
            }

        val schemeUuid = when (scheme.lowercase()) {
            "widevine" -> WIDEVINE_UUID
            "playready" -> PLAYREADY_UUID
            "clearkey" -> CLEARKEY_UUID
            else -> {
                Log.w(TAG, "Unknown DRM scheme: $scheme, defaulting to Widevine")
                WIDEVINE_UUID
            }
        }

        try {
            // Signal that DRM initialisation is starting.
            notifyDrmSessionState("acquiringLicense")

            // Create HTTP data source factory for license requests.
            // When certificatePinning is configured this uses OkHttp; otherwise
            // it falls through to DefaultHttpDataSource (unchanged behaviour).
            val dataSourceFactory = buildHttpDataSourceFactory(drmConfig)

            // Create DRM callback
            val drmCallback = HttpMediaDrmCallback(licenseUrl, dataSourceFactory)

            // DrmConfig.customData (Wave C, gate item "DrmConfig.customData is
            // serialised and ignored"): applied as additional key-request HTTP
            // properties, scoped to license requests only. See
            // applyCustomDataKeyRequestProperties() doc for exactly how each
            // value type is converted.
            applyCustomDataKeyRequestProperties(drmCallback, drmConfig)

            // Create DRM session manager
            val drmSessionManager = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(
                    schemeUuid,
                    FrameworkMediaDrm.DEFAULT_PROVIDER
                )
                .setMultiSession(false)
                .build(drmCallback)

            Log.d(TAG, "DRM session manager created successfully for scheme: $scheme")
            // Manager is built; actual license acquisition happens when ExoPlayer prepares
            // the media source. Emit idle to indicate the session is set up but not yet active.
            notifyDrmSessionState("idle")

            return drmSessionManager

        } catch (e: Exception) {
            // e.message may embed the license/media URL (including auth token query
            // params) surfaced by the underlying DRM/network stack. Log.e survives
            // release ProGuard stripping, so redact before logging (see H-03).
            Log.e(TAG, "Failed to create DRM session manager: ${LogSanitizer.redactUrls(e.message)}", e)
            notifyDrmError("Failed to initialize DRM: ${e.message}")
            return null
        }
    }

    /**
     * Build HTTP data source factory with custom headers and optional certificate pinning.
     *
     * When [drmConfig] contains a non-null "certificatePinning" entry (a Map with
     * key "pins": Map<String, List<String>>), an OkHttpClient with a
     * [CertificatePinner] is created and wrapped in [OkHttpDataSource.Factory].
     *
     * Pin format expected in "pins": domain → list of lowercase hex-encoded
     * SHA-256 digests of the DER SubjectPublicKeyInfo (SPKI) of certificates in
     * the server's TLS chain.  Each hex string is 64 characters long.
     *
     * OkHttp's [CertificatePinner] accepts pins in the form "sha256/<base64>",
     * so each hex pin is converted:  hex → raw bytes → Base64 (standard, padded).
     *
     * Wildcard host patterns ("*.example.com") are supported by OkHttp natively
     * and mirror the Dart-side getPinsForDomain wildcard logic.
     *
     * When "certificatePinning" is absent or null, the existing
     * [DefaultHttpDataSource.Factory] path is returned unchanged.
     */
    internal fun buildHttpDataSourceFactory(
        drmConfig: Map<String, Any>
    ): HttpDataSource.Factory {
        val userAgent = Util.getUserAgent(context, USER_AGENT)

        // Collect request headers (shared by both code paths)
        val requestHeaders = buildRequestHeaders(drmConfig)

        // --- Certificate-pinning path ---
        val pinningConfig = drmConfig["certificatePinning"] as? Map<*, *>
        if (pinningConfig != null) {
            val okHttpClient = buildPinnedOkHttpClient(pinningConfig)
            if (okHttpClient != null) {
                val factory = OkHttpDataSource.Factory(okHttpClient)
                    .setUserAgent(userAgent)
                if (requestHeaders.isNotEmpty()) {
                    factory.setDefaultRequestProperties(requestHeaders)
                }
                Log.d(TAG, "Using OkHttpDataSource with certificate pinning for DRM requests")
                return factory
            }
            // Pin parsing failed – we refuse to silently fall back to an
            // unpinned connection because the caller explicitly requested
            // pinning.  Throw so createDrmSessionManager catches it and
            // emits a DRM error.
            throw IllegalStateException(
                "Certificate pinning was configured but no valid pins could be parsed. " +
                    "DRM licence requests will not proceed without pinning enforcement."
            )
        }

        // --- Default path (no pinning configured) ---
        val dataSourceFactory = DefaultHttpDataSource.Factory().setUserAgent(userAgent)
        if (requestHeaders.isNotEmpty()) {
            dataSourceFactory.setDefaultRequestProperties(requestHeaders)
        }
        return dataSourceFactory
    }

    /**
     * Collect custom headers and optional Bearer token into a single map.
     */
    private fun buildRequestHeaders(drmConfig: Map<String, Any>): Map<String, String> {
        val requestHeaders = mutableMapOf<String, String>()
        val headers = drmConfig["headers"] as? Map<*, *>
        headers?.forEach { (k, v) ->
            if (k is String && v is String) requestHeaders[k] = v
        }
        val token = drmConfig["token"] as? String
        if (token != null) {
            requestHeaders["Authorization"] = "Bearer $token"
        }
        return requestHeaders
    }

    /**
     * Applies [DrmConfig.customData] (a `Map<String, dynamic>` on the Dart side,
     * `lib/src/models/drm_config.dart`) as additional HTTP header key/value pairs
     * on outgoing DRM key-request (licence) requests only, via
     * [HttpMediaDrmCallback.setKeyRequestProperty].
     *
     * This is deliberately distinct from `drmConfig["headers"]` (see
     * [buildRequestHeaders]): those headers are set as *default* request
     * properties on the whole [HttpDataSource.Factory], so they apply to every
     * request made through it (provisioning included). `setKeyRequestProperty`
     * only affects the key/licence request `HttpMediaDrmCallback` issues, which
     * matches `customData`'s dartdoc ("custom license request data").
     *
     * Value conversion — `customData` values are `dynamic` on the Dart side, so
     * not everything is naturally a header-safe `String`:
     *  - [String] values are passed through unchanged.
     *  - [Boolean]/[Int]/[Long]/[Double]/[Float] use their own well-defined
     *    `toString()` (e.g. `"true"`, `"42"`, `"3.14"`) — unambiguous scalar
     *    representations.
     *  - [Map]/[List] values are serialized as JSON via `org.json` (NOT Kotlin's
     *    `Map`/`List.toString()`, which produces a non-parseable, undocumented
     *    `"{key=value}"` representation) so a license server expecting
     *    structured data in a header receives valid JSON.
     *  - `null` values and any other type are skipped (with a warning log)
     *    rather than silently sent as the literal string `"null"`.
     */
    private fun applyCustomDataKeyRequestProperties(
        drmCallback: HttpMediaDrmCallback,
        drmConfig: Map<String, Any>
    ) {
        val customData = drmConfig["customData"] as? Map<*, *> ?: return
        for ((rawKey, rawValue) in customData) {
            val key = rawKey as? String ?: continue
            val value = stringifyCustomDataValue(key, rawValue) ?: continue
            drmCallback.setKeyRequestProperty(key, value)
        }
    }

    /**
     * Converts a single [DrmConfig.customData] entry value to a header-safe
     * string. See [applyCustomDataKeyRequestProperties] for the conversion
     * rules. Returns null (and logs a warning) for `null`/unsupported types so
     * the caller can skip setting that header entirely.
     */
    private fun stringifyCustomDataValue(key: String, value: Any?): String? {
        return when (value) {
            null -> null
            is String -> value
            is Boolean, is Int, is Long, is Double, is Float -> value.toString()
            is Map<*, *> -> JSONObject(value).toString()
            is List<*> -> JSONArray(value).toString()
            else -> {
                Log.w(
                    TAG,
                    "Skipping DrmConfig.customData['$key']: unsupported value type " +
                        value::class.java.simpleName
                )
                null
            }
        }
    }

    /**
     * Build an [OkHttpClient] with a [CertificatePinner] derived from the
     * Dart-side CertificatePinningConfig.toMap() payload.
     *
     * Expected [pinningConfig] structure:
     * ```
     * {
     *   "pins": {
     *     "example.com": ["<64-char hex>", ...],
     *     "*.cdn.example.com": ["<64-char hex>", ...]
     *   }
     * }
     * ```
     *
     * Returns null only if the "pins" key is absent or the map is empty,
     * which is treated as a parse error by the caller.
     */
    private fun buildPinnedOkHttpClient(pinningConfig: Map<*, *>): OkHttpClient? {
        val pinsMap = pinningConfig["pins"] as? Map<*, *> ?: return null
        if (pinsMap.isEmpty()) return null

        val pinnerBuilder = CertificatePinner.Builder()
        var validPinCount = 0

        for ((hostKey, pinListValue) in pinsMap) {
            val host = hostKey as? String ?: continue
            val pinList = pinListValue as? List<*> ?: continue

            for (hexPin in pinList) {
                val hexStr = (hexPin as? String)?.lowercase() ?: continue
                // Each hex pin must be 64 characters (32 bytes = SHA-256)
                if (hexStr.length != 64 || !hexStr.all { it in '0'..'9' || it in 'a'..'f' }) {
                    Log.w(TAG, "Skipping malformed pin for host '$host': '$hexStr'")
                    continue
                }
                val okHttpPin = hexToOkHttpPin(hexStr)
                pinnerBuilder.add(host, okHttpPin)
                validPinCount++
                Log.d(TAG, "Registered pin for '$host': $okHttpPin")
            }
        }

        if (validPinCount == 0) {
            Log.e(TAG, "Certificate pinning config contained no valid pins")
            return null
        }

        return OkHttpClient.Builder()
            .certificatePinner(pinnerBuilder.build())
            .build()
    }

    /**
     * Convert a 64-character lowercase hex string (32 raw bytes, SHA-256 of SPKI)
     * into the "sha256/<base64>" format required by [CertificatePinner].
     *
     * Steps:
     *   1. Parse hex pairs → ByteArray (32 bytes)
     *   2. Base64-encode with standard alphabet and padding (no URL-safe, no NO_WRAP flags
     *      that would strip the trailing '=' – OkHttp accepts padded Base64)
     *   3. Prepend "sha256/"
     */
    private fun hexToOkHttpPin(hex: String): String {
        val bytes = ByteArray(hex.length / 2) { i ->
            hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
        val base64 = Base64.encodeToString(bytes, Base64.DEFAULT).trim()
        return "sha256/$base64"
    }

    /**
     * Check if Widevine DRM is supported on this device.
     */
    fun isWidevineSupported(): Boolean {
        return try {
            val mediaDrm = FrameworkMediaDrm.newInstance(WIDEVINE_UUID)
            mediaDrm.release()
            true
        } catch (e: Exception) {
            Log.w(TAG, "Widevine not supported: ${e.message}")
            false
        }
    }

    /**
     * Get Widevine security level.
     */
    fun getWidevineSecurityLevel(): String {
        return try {
            val mediaDrm = FrameworkMediaDrm.newInstance(WIDEVINE_UUID)
            val securityLevel = mediaDrm.getPropertyString("securityLevel")
            mediaDrm.release()
            securityLevel ?: "Unknown"
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get security level: ${e.message}")
            "Unknown"
        }
    }

    /**
     * Check if PlayReady is supported.
     */
    fun isPlayReadySupported(): Boolean {
        return try {
            val mediaDrm = FrameworkMediaDrm.newInstance(PLAYREADY_UUID)
            mediaDrm.release()
            true
        } catch (e: Exception) {
            Log.w(TAG, "PlayReady not supported: ${e.message}")
            false
        }
    }

    /**
     * Check if ClearKey is supported.
     */
    fun isClearKeySupported(): Boolean {
        return try {
            val mediaDrm = FrameworkMediaDrm.newInstance(CLEARKEY_UUID)
            mediaDrm.release()
            true
        } catch (e: Exception) {
            Log.w(TAG, "ClearKey not supported: ${e.message}")
            false
        }
    }

    /**
     * Notify Flutter of DRM errors by emitting an onDrmSessionUpdate with state=error.
     *
     * This is the single event for DRM failures. Do not add a second/legacy
     * `onDrmError` call here: the Dart side only handles `onDrmSessionUpdate`
     * (see `MediaPlayer._handleDrmSessionUpdate`), which already carries a
     * strictly richer payload (session id, timestamps, playerId) than a
     * standalone error event would. A previous `onDrmError` call had no Dart
     * handler and was removed (see C-09) - re-adding it would either be dead
     * code again or, if wired up, would double-emit the same failure that
     * `onDrmSessionUpdate` already reports.
     */
    private fun notifyDrmError(errorMessage: String) {
        try {
            val now = System.currentTimeMillis()
            methodChannel.invokeMethod(
                "onDrmSessionUpdate",
                buildDrmSessionPayload(
                    state = "error",
                    license = null,
                    errorMessage = errorMessage,
                    nowMs = now
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify DRM error: ${e.message}")
        }
    }

    /**
     * Notify Flutter of DRM session state changes via onDrmSessionUpdate.
     *
     * The payload matches DrmSession.fromMap exactly:
     *   id          – String  (session identifier, playerId-scoped)
     *   state       – String  (DrmSessionState.name: idle|acquiringLicense|licensed|renewing|error|closed)
     *   license     – Map?    (DrmLicense fields or null)
     *   errorMessage– String? (null unless state=error)
     *   createdAt   – Long    (epoch millis)
     *   updatedAt   – Long    (epoch millis)
     *   playerId    – String  (required by the Dart static dispatcher)
     */
    fun notifyDrmSessionState(state: String, license: Map<String, Any>? = null) {
        try {
            methodChannel.invokeMethod(
                "onDrmSessionUpdate",
                buildDrmSessionPayload(
                    state = state,
                    license = license,
                    errorMessage = null,
                    nowMs = System.currentTimeMillis()
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify DRM session state: ${e.message}")
        }
    }

    /**
     * Build the argument map that matches DrmSession.fromMap.
     *
     * Uses Map<String, Any> (non-nullable values) so Flutter's StandardMessageCodec
     * serialises it correctly.  Nullable fields are omitted when null; DrmSession.fromMap
     * handles missing nullable keys via `as String?` / `as Map?` casts which return null.
     */
    private fun buildDrmSessionPayload(
        state: String,
        license: Map<String, Any>?,
        errorMessage: String?,
        nowMs: Long
    ): Map<String, Any> {
        val payload = mutableMapOf<String, Any>(
            "playerId" to playerId,
            "id" to "drm-session-$playerId",
            "state" to state,
            "createdAt" to nowMs,
            "updatedAt" to nowMs
        )
        if (license != null) {
            payload["license"] = license
        }
        if (errorMessage != null) {
            payload["errorMessage"] = errorMessage
        }
        return payload
    }

    /**
     * Get DRM system info.
     */
    fun getDrmSystemInfo(): Map<String, Any> {
        val info = mutableMapOf<String, Any>()

        info["widevineSupported"] = isWidevineSupported()
        if (info["widevineSupported"] as Boolean) {
            info["widevineSecurity"] = getWidevineSecurityLevel()
        }

        info["playreadySupported"] = isPlayReadySupported()
        info["clearkeySupported"] = isClearKeySupported()

        // Add device info
        info["deviceManufacturer"] = android.os.Build.MANUFACTURER
        info["deviceModel"] = android.os.Build.MODEL
        info["androidVersion"] = android.os.Build.VERSION.SDK_INT

        return info
    }

    /**
     * Validate DRM configuration.
     *
     * Wired into the load path from [createDrmSessionManager] (wave 2
     * security hardening — previously this function existed but was dead
     * code, never called from anywhere). In addition to the original
     * scheme/URL/device-support checks, this also enforces the opt-in,
     * fail-closed minimum Widevine security-level policy carried by
     * `drmConfig["minWidevineSecurityLevel"]` (populated from
     * `DrmConfig.minWidevineSecurityLevel` on the Dart side — see its
     * dartdoc). Absent means no policy was requested (default, unchanged
     * behaviour). Present means: the device's *actual* security level
     * (queried live via [getWidevineSecurityLevel]) must meet or exceed the
     * requested minimum, and an indeterminate device level always fails the
     * check — see [meetsMinimumSecurityLevel].
     */
    fun validateDrmConfig(drmConfig: Map<String, Any>): Pair<Boolean, String?> {
        val scheme = drmConfig["scheme"] as? String
        if (scheme == null) {
            return Pair(false, "DRM scheme is required")
        }

        val licenseUrl = drmConfig["licenseUrl"] as? String
        if (licenseUrl == null || licenseUrl.isBlank()) {
            return Pair(false, "License URL is required")
        }

        // Validate scheme is supported
        when (scheme.lowercase()) {
            "widevine" -> {
                if (!isWidevineSupported()) {
                    return Pair(false, "Widevine DRM is not supported on this device")
                }

                val minLevel = drmConfig["minWidevineSecurityLevel"] as? String
                if (minLevel != null) {
                    val actualLevel = getWidevineSecurityLevel()
                    if (!meetsMinimumSecurityLevel(actualLevel, minLevel)) {
                        return Pair(
                            false,
                            "Widevine security level '$actualLevel' does not satisfy the " +
                                "configured minimum '$minLevel' (fail-closed: refusing DRM " +
                                "playback)"
                        )
                    }
                }
            }
            "playready" -> {
                if (!isPlayReadySupported()) {
                    return Pair(false, "PlayReady DRM is not supported on this device")
                }
            }
            "clearkey" -> {
                if (!isClearKeySupported()) {
                    return Pair(false, "ClearKey DRM is not supported on this device")
                }
            }
            else -> {
                return Pair(false, "Unknown DRM scheme: $scheme")
            }
        }

        return Pair(true, null)
    }

    /**
     * Ranks a Widevine security-level string, most secure first: L1 (1) <
     * L2 (2) < L3 (3). Returns `null` for anything unrecognized (including
     * `"Unknown"`, which [getWidevineSecurityLevel] itself returns when the
     * underlying `MediaDrm` property read fails) so that an unranked level
     * can never be treated as satisfying a policy — see
     * [meetsMinimumSecurityLevel].
     */
    private fun securityLevelRank(level: String): Int? = when (level.trim().uppercase()) {
        "L1" -> 1
        "L2" -> 2
        "L3" -> 3
        else -> null
    }

    /**
     * Fail-closed comparison for the minimum-security-level policy: returns
     * `true` only when both [actualLevel] and [minLevel] rank to a known
     * value AND the device's actual rank is numerically <= the requested
     * minimum's rank (lower number = more secure, since L1 is Widevine's
     * highest tier). Returns `false` — never throws — whenever either level
     * cannot be ranked, so an indeterminate device level (or a malformed
     * policy value) always refuses playback rather than silently allowing
     * it through.
     */
    internal fun meetsMinimumSecurityLevel(actualLevel: String, minLevel: String): Boolean {
        val actualRank = securityLevelRank(actualLevel) ?: return false
        val minRank = securityLevelRank(minLevel) ?: return false
        return actualRank <= minRank
    }
}

/**
 * Extension to FrameworkMediaDrm for easier instantiation.
 */
object FrameworkMediaDrm {
    val DEFAULT_PROVIDER = androidx.media3.exoplayer.drm.FrameworkMediaDrm.DEFAULT_PROVIDER

    fun newInstance(uuid: UUID): androidx.media3.exoplayer.drm.ExoMediaDrm {
        return androidx.media3.exoplayer.drm.FrameworkMediaDrm.newInstance(uuid)
    }
}

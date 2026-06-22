package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.util.Log
import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.drm.DefaultDrmSessionManager
import com.google.android.exoplayer2.drm.DrmSessionManager
import com.google.android.exoplayer2.drm.ExoMediaDrm
import com.google.android.exoplayer2.drm.FrameworkMediaDrm
import com.google.android.exoplayer2.drm.HttpMediaDrmCallback
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.upstream.HttpDataSource
import com.google.android.exoplayer2.util.Util
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Handles DRM (Digital Rights Management) for media playback
 * Supports Widevine, PlayReady, and ClearKey DRM schemes for ExoPlayer v2
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
     * Create DRM session manager for ExoPlayer v2
     */
    fun createDrmSessionManager(
        drmConfig: Map<String, Any>?
    ): DrmSessionManager? {
        if (drmConfig == null) {
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

            // Create HTTP data source factory for license requests
            val dataSourceFactory = buildHttpDataSourceFactory(drmConfig)

            // Create DRM callback
            val drmCallback = HttpMediaDrmCallback(licenseUrl, dataSourceFactory)

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
            Log.e(TAG, "Failed to create DRM session manager: ${e.message}", e)
            notifyDrmError("Failed to initialize DRM: ${e.message}")
            return null
        }
    }

    /**
     * Build HTTP data source factory with custom headers
     */
    private fun buildHttpDataSourceFactory(
        drmConfig: Map<String, Any>
    ): HttpDataSource.Factory {
        val userAgent = Util.getUserAgent(context, USER_AGENT)
        val dataSourceFactory = DefaultHttpDataSource.Factory().setUserAgent(userAgent)

        // Add custom headers
        val headers = drmConfig["headers"] as? Map<String, String>
        val token = drmConfig["token"] as? String

        val requestHeaders = mutableMapOf<String, String>()
        headers?.let { requestHeaders.putAll(it) }
        if (token != null) {
            requestHeaders["Authorization"] = "Bearer $token"
        }

        if (requestHeaders.isNotEmpty()) {
            dataSourceFactory.setDefaultRequestProperties(requestHeaders)
        }

        return dataSourceFactory
    }

    /**
     * Check if Widevine DRM is supported on this device
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
     * Get Widevine security level
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
     * Check if PlayReady is supported
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
     * Check if ClearKey is supported
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
     * Acquire offline license (placeholder for future implementation)
     */
    fun acquireOfflineLicense(
        drmConfig: Map<String, Any>,
        callback: (String?, String?) -> Unit
    ) {
        // TODO: Implement offline license acquisition
        // This requires ExoPlayer's OfflineLicenseHelper
        Log.w(TAG, "Offline license acquisition not yet implemented")
        callback(null, "Offline licenses not yet implemented")
    }

    /**
     * Release offline license (placeholder)
     */
    fun releaseOfflineLicense(licenseId: String) {
        // TODO: Implement offline license release
        Log.w(TAG, "Offline license release not yet implemented")
    }

    /**
     * Renew offline license (placeholder)
     */
    fun renewOfflineLicense(licenseId: String) {
        // TODO: Implement offline license renewal
        Log.w(TAG, "Offline license renewal not yet implemented")
    }

    /**
     * Notify Flutter of DRM errors by emitting an onDrmSessionUpdate with state=error.
     * Also emits the legacy onDrmError call so any other consumers still receive it.
     */
    private fun notifyDrmError(errorMessage: String) {
        try {
            val now = System.currentTimeMillis()
            // Primary: emit onDrmSessionUpdate with state=error so drmSessionStream surfaces the failure.
            methodChannel.invokeMethod(
                "onDrmSessionUpdate",
                buildDrmSessionPayload(
                    state = "error",
                    license = null,
                    errorMessage = errorMessage,
                    nowMs = now
                )
            )
            // Secondary: keep legacy onDrmError for any future consumers.
            methodChannel.invokeMethod(
                "onDrmError",
                mapOf(
                    "playerId" to playerId,
                    "error" to errorMessage,
                    "timestamp" to now
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
     * DrmSession.fromMap reads:
     *   map['id']           as String
     *   map['state']        as String  → DrmSessionState.name
     *   map['license']      as Map?    → DrmLicense.fromMap (nullable)
     *   map['errorMessage'] as String? (nullable)
     *   map['createdAt']    as int     → DateTime.fromMillisecondsSinceEpoch
     *   map['updatedAt']    as int     → DateTime.fromMillisecondsSinceEpoch
     *
     * The static Dart dispatcher additionally reads map['playerId'] to route to the
     * correct MediaPlayer instance before calling _handleDrmSessionUpdate.
     */
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
     * Get DRM system info
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
     * Validate DRM configuration
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
}

/**
 * Extension to FrameworkMediaDrm for easier instantiation
 */
object FrameworkMediaDrm {
    val DEFAULT_PROVIDER = com.google.android.exoplayer2.drm.FrameworkMediaDrm.DEFAULT_PROVIDER

    fun newInstance(uuid: UUID): com.google.android.exoplayer2.drm.ExoMediaDrm {
        return com.google.android.exoplayer2.drm.FrameworkMediaDrm.newInstance(uuid)
    }
}

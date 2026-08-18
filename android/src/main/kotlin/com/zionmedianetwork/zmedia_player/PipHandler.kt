package com.zionmedianetwork.zmedia_player

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Handles Picture-in-Picture mode for Android O and above
 */
class PipHandler(
    activity: Activity?,
    private val playerId: String,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "PipHandler"

        // Explicit-component broadcast action for PipActionReceiver. Since
        // every PendingIntent we hand to the system targets the receiver by
        // component (setClass), this string is never matched via an
        // intent-filter -- it exists purely for logcat/debugging clarity.
        private const val ACTION_PIP_ACTION = "com.zionmedianetwork.zmedia_player.PIP_ACTION"

        // The system enforces a maximum number of visible PiP actions (3 on
        // API 26-31, 5 on API 32+ / 12L); actions beyond the max are simply
        // not shown by the system (no crash). We defensively cap at the
        // lowest common value so behaviour is consistent across every
        // supported API level rather than silently varying by OS version.
        private const val MAX_PIP_ACTIONS = 3

        // Registry of live PipHandler instances keyed by playerId.
        //
        // PipActionReceiver (below) is a manifest-registered BroadcastReceiver:
        // the OS instantiates it fresh for every broadcast, so it cannot hold a
        // reference to "its" PipHandler directly. Instead, each handler
        // publishes itself here on construction and removes itself in
        // dispose(), and the receiver looks the handler up by the "playerId"
        // extra carried on the PendingIntent built in buildActionPendingIntent().
        // Held as a WeakReference so a handler that failed to dispose() cleanly
        // for any reason cannot be kept alive by this registry (same pattern as
        // NotificationHandler.liveHandlers).
        private val liveHandlers = mutableMapOf<String, WeakReference<PipHandler>>()

        internal fun handlerFor(playerId: String): PipHandler? = liveHandlers[playerId]?.get()
    }

    init {
        liveHandlers[playerId] = WeakReference(this)
    }

    // Mutable so the plugin can refresh it on activity lifecycle callbacks
    // (rotation/config change). PipHandler instances are cached in a long-lived
    // map keyed by playerId, so the Activity captured at construction time can
    // otherwise become stale/destroyed after a configuration change while the
    // handler itself lives on. See updateActivity().
    private var activity: Activity? = activity

    private var config: Map<String, Any>? = null
    private var isInPipMode = false

    /**
     * Refresh the Activity reference held by this handler.
     *
     * Must be called by the owner (ZMediaPlayerPlugin) whenever its own
     * activity reference changes - i.e. from [ActivityAware.onAttachedToActivity]
     * and [ActivityAware.onReattachedToActivityForConfigChanges], and with `null`
     * from [ActivityAware.onDetachedFromActivity] - so that a cached PipHandler
     * never operates against a destroyed pre-rotation Activity.
     */
    fun updateActivity(activity: Activity?) {
        this.activity = activity
    }

    /**
     * Persist the PiP config map so that subsequent [enterPip] calls (and
     * [buildPipParams]) can read autoEnterOnBackground even if the caller
     * does not pass the config again at that point.
     */
    fun applyConfig(config: Map<String, Any>?) {
        if (config != null) {
            this.config = config
        }
    }

    /**
     * Check if PiP is available on this device
     */
    fun checkAvailability(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.d(TAG, "PiP not available: Android version ${Build.VERSION.SDK_INT} < O (26)")
            notifyPipStatusChanged(
                state = "unavailable",
                isSupported = false,
                isActive = false,
                errorMessage = "PiP requires Android 8.0 (API 26) or higher"
            )
            return false
        }

        val currentActivity = activity
        if (currentActivity == null) {
            android.util.Log.d(TAG, "PiP not available: No activity context")
            notifyPipStatusChanged(
                state = "unavailable",
                isSupported = false,
                isActive = false,
                errorMessage = "No activity available"
            )
            return false
        }

        val hasPipFeature = currentActivity.packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE
        )

        android.util.Log.d(TAG, "PiP availability check: SDK=${Build.VERSION.SDK_INT}, hasFeature=$hasPipFeature, activity=true")

        // Notify status
        notifyPipStatusChanged(
            state = if (hasPipFeature) "available" else "unavailable",
            isSupported = hasPipFeature,
            isActive = isInPipMode
        )

        return hasPipFeature
    }

    /**
     * Enter Picture-in-Picture mode
     */
    fun enterPip(config: Map<String, Any>?): Boolean {
        android.util.Log.d(TAG, "Attempting to enter PiP mode")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.w(TAG, "PiP not supported on Android version < O")
            notifyPipStatusChanged(
                state = "failed",
                isSupported = false,
                isActive = false,
                errorMessage = "PiP requires Android 8.0 or higher"
            )
            return false
        }

        val currentActivity = activity
        if (currentActivity == null) {
            android.util.Log.w(TAG, "Cannot enter PiP: No activity context")
            notifyPipStatusChanged(
                state = "failed",
                isSupported = true,
                isActive = false,
                errorMessage = "No activity available"
            )
            return false
        }

        // Merge: caller-supplied config takes precedence; fall back to previously
        // stored config (primed by applyConfig during checkPipAvailability).
        val effectiveConfig = config ?: this.config
        this.config = effectiveConfig

        return try {
            val params = buildPipParams(effectiveConfig, currentActivity)
            android.util.Log.d(TAG, "Built PiP params, entering PiP mode...")

            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                currentActivity.enterPictureInPictureMode(params)
            } else {
                false
            }

            if (result) {
                isInPipMode = true
                notifyPipStatusChanged(
                    state = "active",
                    isSupported = true,
                    isActive = true
                )
                android.util.Log.d(TAG, "Entered PiP mode successfully")
            } else {
                android.util.Log.w(TAG, "Activity.enterPictureInPictureMode() returned false")
                notifyPipStatusChanged(
                    state = "failed",
                    isSupported = true,
                    isActive = false,
                    errorMessage = "Failed to enter PiP mode"
                )
            }

            result
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error entering PiP mode: ${e.message}", e)
            notifyPipStatusChanged(
                state = "failed",
                isSupported = true,
                isActive = false,
                errorMessage = e.message
            )
            false
        }
    }

    /**
     * Exit Picture-in-Picture mode
     */
    fun exitPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        if (activity == null || !isInPipMode) {
            return
        }

        // The activity will automatically exit PiP when we request it
        // We can't programmatically exit PiP, but we can notify the state change
        isInPipMode = false
        notifyPipStatusChanged(
            state = "available",
            isSupported = true,
            isActive = false
        )

        android.util.Log.d(TAG, "Exited PiP mode")
    }

    /**
     * Handle PiP mode changed (called from activity)
     */
    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        android.util.Log.d(TAG, "PiP mode changed: $isInPictureInPictureMode")

        isInPipMode = isInPictureInPictureMode

        notifyPipStatusChanged(
            state = if (isInPictureInPictureMode) "active" else "available",
            isSupported = true,
            isActive = isInPictureInPictureMode
        )
    }

    /**
     * Build PiP parameters
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipParams(config: Map<String, Any>?, context: Context): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()

        // Set aspect ratio
        val aspectRatio = config?.get("aspectRatio") as? Double ?: (16.0 / 9.0)
        val rational = Rational(
            (aspectRatio * 100).toInt(),
            100
        )
        builder.setAspectRatio(rational)

        // PipConfig.actions / PipConfig.showPlaybackControls (Wave C, gate item
        // "PipConfig.actions and PipConfig.showPlaybackControls are ignored
        // natively"). RemoteAction and PictureInPictureParams.setActions() are
        // both available from API 26 (O) -- the same level this whole function
        // is already guarded at -- so no extra @RequiresApi is needed here.
        //
        // showPlaybackControls == false suppresses the actions entirely (no
        // setActions() call at all, matching "do not add playback actions");
        // when true (the default) the configured actions list, if any, is
        // rendered in the PiP overlay.
        val showPlaybackControls = config?.get("showPlaybackControls") as? Boolean ?: true
        if (showPlaybackControls) {
            val actionsRaw = config?.get("actions") as? List<*>
            val remoteActions = buildRemoteActions(context, actionsRaw)
            if (remoteActions.isNotEmpty()) {
                builder.setActions(remoteActions)
            }
        }

        // For Android 12+, we can add additional features
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Set auto-enter enabled
            val autoEnter = config?.get("autoEnterOnBackground") as? Boolean ?: false
            builder.setAutoEnterEnabled(autoEnter)

            // Set seamless resize enabled for smoother transitions
            builder.setSeamlessResizeEnabled(true)
        }

        return builder.build()
    }

    /**
     * Converts [PipConfig.actions] (a `List<Map>` produced by `PipAction.toMap()`
     * on the Dart side -- `lib/src/models/pip_config.dart`, shape
     * `{"id": String, "title": String, "icon": String?}`) into
     * [RemoteAction]s for [PictureInPictureParams.Builder.setActions].
     *
     * Icon resolution mirrors `NotificationHandler.resolveSmallIcon`: `icon` is
     * looked up as a drawable resource name in the host app's own resources;
     * if absent, blank, or unresolved, a stock system icon is used instead so
     * an action is never silently dropped just because its icon could not be
     * resolved.
     *
     * Each action's [PendingIntent] targets [PipActionReceiver] (declared in
     * this module's `AndroidManifest.xml`), which invokes `onPipAction` on the
     * method channel with `{"playerId": ..., "actionId": ...}` when tapped --
     * mirroring the `createAction`/`NotificationActionReceiver` mechanism in
     * `NotificationHandler.kt`.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildRemoteActions(context: Context, actionsRaw: List<*>?): List<RemoteAction> {
        if (actionsRaw.isNullOrEmpty()) return emptyList()

        return actionsRaw.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = map["id"] as? String ?: return@mapNotNull null
            val title = map["title"] as? String ?: id
            val icon = resolveActionIcon(context, map["icon"] as? String)

            RemoteAction(
                icon,
                title,
                title,
                buildActionPendingIntent(context, id)
            )
        }.take(MAX_PIP_ACTIONS)
    }

    /**
     * Resolves a [PipAction.icon] drawable resource name to an [Icon], falling
     * back to a stock system icon when the name is absent/blank or does not
     * resolve to a drawable in the host app's resources.
     */
    private fun resolveActionIcon(context: Context, name: String?): Icon {
        if (!name.isNullOrBlank()) {
            val resId = context.resources.getIdentifier(name, "drawable", context.packageName)
            if (resId != 0) {
                return Icon.createWithResource(context, resId)
            }
            android.util.Log.w(
                TAG,
                "PipAction icon '$name' was not found in the host app's drawable resources; " +
                    "using a fallback icon."
            )
        }
        return Icon.createWithResource(context, android.R.drawable.ic_media_play)
    }

    /**
     * Builds the broadcast [PendingIntent] for a single PiP action, explicitly
     * targeting [PipActionReceiver] and carrying this instance's [playerId]
     * plus the tapped action's [actionId].
     */
    private fun buildActionPendingIntent(context: Context, actionId: String): PendingIntent {
        val intent = Intent(ACTION_PIP_ACTION).apply {
            setClass(context, PipActionReceiver::class.java)
            putExtra(PipActionReceiver.EXTRA_PLAYER_ID, playerId)
            putExtra(PipActionReceiver.EXTRA_ACTION_ID, actionId)
        }

        return PendingIntent.getBroadcast(
            context,
            // Distinct request code per (playerId, actionId) so concurrent
            // instances' actions don't collide and overwrite each other's
            // PendingIntents via FLAG_UPDATE_CURRENT.
            31 * playerId.hashCode() + actionId.hashCode(),
            intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
    }

    /**
     * Called by [PipActionReceiver] when a custom PiP action is tapped.
     * Forwards the tap to Flutter as `onPipAction`.
     */
    internal fun onPipActionSelected(actionId: String) {
        android.util.Log.d(TAG, "PiP action selected: $actionId")
        methodChannel.invokeMethod(
            "onPipAction",
            mapOf("playerId" to playerId, "actionId" to actionId)
        )
    }

    /**
     * Notify Flutter of PiP status changes
     */
    private fun notifyPipStatusChanged(
        state: String,
        isSupported: Boolean,
        isActive: Boolean,
        errorMessage: String? = null
    ) {
        val statusMap = mapOf(
            "playerId" to playerId,
            "state" to state,
            "isSupported" to isSupported,
            "isActive" to isActive,
            "errorMessage" to errorMessage
        )

        activity?.runOnUiThread {
            methodChannel.invokeMethod("onPipStatusChanged", statusMap)
        }
    }

    /**
     * Get current PiP status
     */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "state" to if (isInPipMode) "active" else if (checkAvailability()) "available" else "unavailable",
            "isSupported" to checkAvailability(),
            "isActive" to isInPipMode
        )
    }

    /**
     * Dispose the PiP handler
     */
    fun dispose() {
        android.util.Log.d(TAG, "Disposing PiP handler")
        liveHandlers.remove(playerId)
        config = null
        isInPipMode = false
    }
}

/**
 * Manifest-registered receiver (see `android/src/main/AndroidManifest.xml`)
 * that routes taps on custom PiP actions (see
 * [PipHandler.buildActionPendingIntent]) back to Flutter.
 *
 * Every [PendingIntent] that reaches this receiver is built by
 * [PipHandler.buildActionPendingIntent] with an explicit component target
 * (this class) and always carries [EXTRA_PLAYER_ID] plus [EXTRA_ACTION_ID].
 * The system instantiates a fresh receiver instance per broadcast, so it
 * cannot hold player state itself -- it looks the owning [PipHandler] up via
 * [PipHandler.handlerFor] and forwards the tap via
 * [PipHandler.onPipActionSelected], which invokes `onPipAction` on the method
 * channel with `{"playerId": ..., "actionId": ...}`.
 *
 * No host-app manifest changes are required: this receiver is declared in
 * this module's own `AndroidManifest.xml` and is merged into every consuming
 * app's manifest automatically by the Android Gradle build's manifest merger.
 */
class PipActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val playerId = intent.getStringExtra(EXTRA_PLAYER_ID) ?: return
        val actionId = intent.getStringExtra(EXTRA_ACTION_ID) ?: return
        val handler = PipHandler.handlerFor(playerId) ?: return
        handler.onPipActionSelected(actionId)
    }

    companion object {
        const val EXTRA_PLAYER_ID = "playerId"
        const val EXTRA_ACTION_ID = "actionId"
    }
}

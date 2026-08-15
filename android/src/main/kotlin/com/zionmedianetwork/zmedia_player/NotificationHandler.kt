package com.zionmedianetwork.zmedia_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.lang.ref.WeakReference
import java.net.URL

/**
 * Process-wide arbiter of which [NotificationHandler] instance currently owns
 * hardware media-button routing and the visible tray notification.
 *
 * This is the Android analogue of the `Ownership` type in
 * `ios/zmedia_player/Sources/zmedia_player/NotificationHandler.swift` (see its
 * doc comment for the full rationale) and deliberately mirrors its policy:
 * **last `initialize()` call always wins ownership**. The underlying shared
 * resource differs by platform, though:
 *
 * - On iOS, `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter` are process-wide
 *   OS singletons, so *every* instance writes to the same object and
 *   coordination is about who is allowed to write.
 * - On Android, each [NotificationHandler] owns its own [MediaSessionCompat]
 *   and posts to its own, distinct notification id (derived from `playerId` —
 *   see [NotificationHandler.notificationId]), so nothing is literally
 *   shared. The coordination problem here is instead that (a) multiple
 *   simultaneously-`isActive` `MediaSessionCompat` instances compete for
 *   hardware media-button routing (the OS routes to whichever was most
 *   recently made active, which is not necessarily the one the app/user
 *   still cares about), and (b) device-verified behaviour shows the system's
 *   persistent "now playing" surface can be left with nothing shown at all
 *   once the session it was tracking is torn down, rather than falling back
 *   to another still-active session on its own. Restricting "active +
 *   visibly posted" to a single owner at a time avoids both problems and
 *   gives `dispose()` an explicit, deterministic hand-off to perform.
 */
private object NotificationOwnership {
    private val lock = Any()
    private var owner: WeakReference<NotificationHandler>? = null
    private val liveInstances = mutableListOf<WeakReference<NotificationHandler>>()

    /** Registers [handler] in the live-instance registry used to pick a successor owner later. */
    fun register(handler: NotificationHandler) {
        synchronized(lock) {
            liveInstances.removeAll { it.get() == null }
            if (liveInstances.none { it.get() === handler }) {
                liveInstances.add(WeakReference(handler))
            }
        }
    }

    /**
     * Last-writer-wins: makes [handler] the current owner and returns whoever
     * owned it before (or `null` if there was no owner, or if [handler] was
     * already the owner), so the caller can demote that previous owner.
     */
    fun claimOwnership(handler: NotificationHandler): NotificationHandler? {
        synchronized(lock) {
            val previous = owner?.get()
            owner = WeakReference(handler)
            return if (previous === handler) null else previous
        }
    }

    fun isOwner(handler: NotificationHandler): Boolean = synchronized(lock) { owner?.get() === handler }

    sealed class ReleaseResult {
        /** [handler] was not the owner; nothing to do. */
        object NotOwner : ReleaseResult()

        /** [handler] was the owner; [successor] is the new owner and must be promoted. */
        data class HandedOff(val successor: NotificationHandler) : ReleaseResult()

        /** [handler] was the owner and no other instance is alive. */
        object TornDown : ReleaseResult()
    }

    /**
     * Removes [handler] from the live registry and, if it was the owner,
     * either hands ownership to another live instance (the most recently
     * registered one still alive) or reports that a full teardown is
     * required.
     */
    fun release(handler: NotificationHandler): ReleaseResult {
        synchronized(lock) {
            liveInstances.removeAll { it.get() == null || it.get() === handler }
            if (owner?.get() !== handler) {
                return ReleaseResult.NotOwner
            }
            val successor = liveInstances.lastOrNull()?.get()
            return if (successor != null) {
                owner = WeakReference(successor)
                ReleaseResult.HandedOff(successor)
            } else {
                owner = null
                ReleaseResult.TornDown
            }
        }
    }
}

/**
 * Handles media notifications using MediaSession and NotificationCompat.
 *
 * ## Ownership
 *
 * Only one [NotificationHandler] instance is ever the *owner* at a time (see
 * [NotificationOwnership] above): its [MediaSessionCompat] is the only one
 * kept `isActive`, and it is the only instance whose tray notification is
 * actually posted via [NotificationManager.notify]. Non-owning instances
 * still track their media/playback state locally (title, position,
 * `mediaSession` metadata) and keep their [MediaSessionCompat] object alive
 * and registered in [activeSessions], but their session is left inactive and
 * their notification is not shown — so they can republish immediately,
 * correctly, if they are later promoted (see [promoteToOwner]).
 *
 * `initialize()` always claims ownership (last-writer-wins, matching iOS).
 * `dispose()` releases it: if the disposed instance was the owner, the most
 * recently registered still-live instance is promoted — its session is
 * reactivated and its notification (re)posted — so lock-screen/notification
 * control is never left pointing at a dead player. If no other instance is
 * alive, the disposed owner's notification/session (already cancelled by
 * `dismiss()`, called at the top of `dispose()`) simply stays torn down.
 */
class NotificationHandler(
    private val context: Context,
    internal val playerId: String,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "NotificationHandler"

        // java.net.URLConnection has no timeout by default and will block
        // connect()/getInputStream() indefinitely on a stalled or
        // misbehaving connection. A non-owner resolves artwork entirely in
        // the background with no user-visible symptom if that hangs (see
        // resolveArtworkIfNeeded doc), so an unbounded wait here could
        // silently leave a later-promoted player with no artwork forever,
        // long past the point promoteToOwner() ran. Bounding it lets a
        // stuck fetch fail and (via promoteToOwner's retry) be attempted
        // again instead.
        private const val ARTWORK_FETCH_TIMEOUT_MS = 8000

        // Registry of active MediaSessionCompat instances keyed by playerId.
        //
        // NotificationActionReceiver (below) is a manifest-registered
        // BroadcastReceiver: the OS instantiates it fresh for every broadcast, so it
        // cannot hold a reference to "its" NotificationHandler directly. Instead,
        // each handler publishes its MediaSessionCompat here on initialize() and
        // removes it on dispose(), and the receiver looks the session up by the
        // "playerId" extra carried on the PendingIntent built in createAction().
        // This preserves support for multiple concurrent player instances (see
        // AGENTS.md/CLAUDE.md: "Multiple instances are supported").
        //
        // Entries are kept here regardless of NotificationOwnership state (a
        // non-owner's session object is still valid and still routable to —
        // it is simply inactive and not currently posting a notification), and
        // are only removed in dispose(), the sole teardown path for a handler.
        private val activeSessions = mutableMapOf<String, MediaSessionCompat>()

        internal fun sessionFor(playerId: String): MediaSessionCompat? = activeSessions[playerId]
    }

    /**
     * `true` when this instance currently owns hardware media-button routing
     * and is allowed to post its notification / keep its media session
     * active. See [NotificationOwnership].
     */
    private val isOwner: Boolean
        get() = NotificationOwnership.isOwner(this)

    // Per-instance notification ID derived from playerId so that multiple concurrent
    // player instances do not overwrite or cancel each other's notifications.
    // hashCode() can be negative; AND with 0x7FFFFFFF ensures a positive value and
    // avoids 0 (which is reserved/invalid for notification IDs on some Android versions).
    private val notificationId: Int = (playerId.hashCode() and 0x7FFFFFFF).let { if (it == 0) 1 else it }

    // Owned scope: all coroutines are cancelled in dispose() to prevent leaks.
    // Main dispatcher matches the original intent (invokeMethod must run on Main).
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private var notificationManager: NotificationManager? = null
    private var mediaSession: MediaSessionCompat? = null
    private var notification: Notification? = null
    private var isShowing = false

    // Configuration
    private var channelId: String = "media_playback"
    private var channelName: String = "Media Playback"
    private var showPlayPause: Boolean = true
    private var showNext: Boolean = true
    private var showPrevious: Boolean = true
    private var showStop: Boolean = false
    private var showSeekForward: Boolean = false
    private var showSeekBackward: Boolean = false
    private var seekInterval: Int = 10

    // Resolved small-icon drawable resource id (see resolveSmallIcon()). Defaults to
    // 0 (unresolved) until initialize() runs; buildNotification() re-resolves
    // defensively if it is still 0.
    private var smallIconResId: Int = 0

    // Current media info
    private var currentTitle: String? = null
    private var currentArtist: String? = null
    private var currentArtworkUrl: String? = null
    private var currentMediaUrl: String? = null
    private var currentArtworkBitmap: Bitmap? = null

    // True while a loadArtwork()/generateThumbnail() coroutine is between
    // being launched and finishing (success or failure). Prevents
    // resolveArtworkIfNeeded() from starting a redundant concurrent fetch
    // -- e.g. one launched from showNotification() and another from a
    // promoteToOwner() retry that races with it.
    private var artworkLoadInFlight: Boolean = false

    private var isPlaying: Boolean = false
    private var position: Long = 0
    private var duration: Long = 0

    /**
     * Initialize the notification handler
     */
    fun initialize(config: Map<String, Any>) {
        android.util.Log.d(TAG, "Initializing notification handler for player: $playerId")

        // Parse configuration
        channelId = config["channelId"] as? String ?: channelId
        channelName = config["channelName"] as? String ?: channelName
        showPlayPause = config["showPlayPause"] as? Boolean ?: showPlayPause
        showNext = config["showNext"] as? Boolean ?: showNext
        showPrevious = config["showPrevious"] as? Boolean ?: showPrevious
        showStop = config["showStop"] as? Boolean ?: showStop
        showSeekForward = config["showSeekForward"] as? Boolean ?: showSeekForward
        showSeekBackward = config["showSeekBackward"] as? Boolean ?: showSeekBackward
        seekInterval = (config["seekInterval"] as? Number)?.toInt() ?: seekInterval
        smallIconResId = resolveSmallIcon(config["smallIcon"] as? String)

        // Initialize notification manager
        notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel for Android O and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = config["channelDescription"] as? String ?: "Media playback notifications"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager?.createNotificationChannel(channel)
        }

        // Create media session
        mediaSession = MediaSessionCompat(context, "FlutterMediaPlayer_$playerId").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    android.util.Log.d(TAG, "MediaSession: onPlay")
                    sendActionToFlutter("play")
                }

                override fun onPause() {
                    android.util.Log.d(TAG, "MediaSession: onPause")
                    sendActionToFlutter("pause")
                }

                override fun onSkipToNext() {
                    android.util.Log.d(TAG, "MediaSession: onSkipToNext")
                    sendActionToFlutter("next")
                }

                override fun onSkipToPrevious() {
                    android.util.Log.d(TAG, "MediaSession: onSkipToPrevious")
                    sendActionToFlutter("previous")
                }

                override fun onStop() {
                    android.util.Log.d(TAG, "MediaSession: onStop")
                    sendActionToFlutter("stop")
                }

                override fun onSeekTo(pos: Long) {
                    android.util.Log.d(TAG, "MediaSession: onSeekTo $pos")
                    // Forward the requested absolute position (milliseconds, per the
                    // MediaSessionCompat.Callback.onSeekTo contract) to Flutter so it
                    // can drive the actual seek -- mirrors iOS's
                    // changePlaybackPositionCommand handling, which forwards via the
                    // same "seekTo" action + "position" payload shape (see
                    // NotificationHandler.swift). This handler does not seek the
                    // player itself; Dart/the host app owns that (same contract as
                    // every other transport action here).
                    sendActionToFlutter("seekTo", pos)
                }
            })
            // isActive is set below, gated by NotificationOwnership: multiple
            // concurrently-active MediaSessionCompat instances compete for
            // hardware media-button routing, so only the current owner's
            // session may be active.
        }

        // Publish this instance's session so NotificationActionReceiver can route
        // notification-button taps back to it (see activeSessions above).
        mediaSession?.let { activeSessions[playerId] = it }

        // Ownership: last initialize() call always wins (mirrors the iOS
        // NotificationHandler.Ownership policy — see NotificationOwnership doc
        // above). Claiming ownership demotes whoever held it before:
        // deactivates their MediaSessionCompat and hides their tray
        // notification, so at most one player's session is ever eligible for
        // hardware media-button routing / the system's "now playing" surface.
        NotificationOwnership.register(this)
        val previousOwner = NotificationOwnership.claimOwnership(this)
        previousOwner?.demoteFromOwner()
        mediaSession?.isActive = true

        android.util.Log.d(TAG, "Notification handler initialized successfully (now the notification owner)")
    }

    /**
     * Show or update the notification
     */
    fun showNotification(mediaItem: Map<String, Any>, state: Map<String, Any>) {
        android.util.Log.d(TAG, "Showing notification")

        val newArtworkUrl = mediaItem["artworkUrl"] as? String
        val newMediaUrl = mediaItem["url"] as? String

        // Detect when the media item changes so a stale bitmap is not reused
        // for a different video.  A change is identified by either the artworkUrl
        // or the media URL changing.
        val mediaChanged = (newArtworkUrl != currentArtworkUrl) || (newMediaUrl != currentMediaUrl)
        if (mediaChanged) {
            currentArtworkBitmap = null
        }

        // Update media info
        currentTitle = mediaItem["title"] as? String ?: "Unknown Title"
        currentArtist = mediaItem["artist"] as? String ?: "Unknown Artist"
        currentArtworkUrl = newArtworkUrl
        currentMediaUrl = newMediaUrl

        // Update playback state
        isPlaying = state["isPlaying"] as? Boolean ?: false
        position = (state["position"] as? Number)?.toLong() ?: 0
        duration = (state["duration"] as? Number)?.toLong() ?: 0

        // Update media session metadata
        updateMediaSessionMetadata()

        // Update playback state
        updateMediaSessionPlaybackState()

        // Artwork resolution (see resolveArtworkIfNeeded doc): started here
        // unconditionally, regardless of ownership -- acquiring the bitmap
        // is never ownership-gated, only *posting* it is.
        resolveArtworkIfNeeded()

        isShowing = true

        // Only the current owner may post the tray notification (see
        // NotificationOwnership doc above). A non-owner still updates its
        // local isShowing/mediaSession state above so it can republish
        // immediately if promoteToOwner() is called later.
        if (isOwner) {
            buildAndShowNotification()
        }
    }

    /**
     * Update notification state without changing media info
     */
    fun updateState(state: Map<String, Any>) {
        if (!isShowing) return

        android.util.Log.d(TAG, "Updating notification state")

        isPlaying = state["isPlaying"] as? Boolean ?: false
        position = (state["position"] as? Number)?.toLong() ?: 0

        // Never let an already-known-good duration regress to 0/absent here.
        // updateState() never changes which media item is showing (see the
        // doc above), so a previously established duration is always still
        // correct for the *current* item -- there is no legitimate reason
        // for it to become unknown again mid-playback. Guarding against that
        // is cheap insurance against any caller (present or future, Dart or
        // native) that forwards a transient/unknown zero: without it, one
        // such call would permanently blank METADATA_KEY_DURATION -- the
        // progress bar's denominator -- for the rest of this instance's
        // life, since nothing else ever re-derives it once showNotification()
        // has already run. (showNotification() itself is deliberately NOT
        // guarded this way: a genuine media-item change there *should* reset
        // duration to whatever the new item's is, including 0/unknown, until
        // it becomes known.)
        val incomingDuration = (state["duration"] as? Number)?.toLong() ?: 0
        if (incomingDuration > 0) {
            duration = incomingDuration
        }

        // Keep METADATA_KEY_DURATION in sync here too, not just
        // PlaybackStateCompat's position/state. These live on two separate
        // objects on MediaSessionCompat (MediaMetadataCompat vs
        // PlaybackStateCompat) -- previously only the latter was refreshed
        // in this method, via updateMediaSessionPlaybackState() below. If
        // the real duration became known (or changed) only after the
        // initial showNotification() call, the session's *declared total*
        // duration -- which is what drives the notification's progress-bar
        // "total" -- could stay stale (or 0) here indefinitely. That
        // mattered least for an owner, which rebuilds/reposts its
        // notification on every one of these calls anyway (see
        // buildAndShowNotification() below) and so gets many chances to
        // pick up a corrected value; a non-owner never posts at all until
        // promoteToOwner() runs, so it only ever gets whichever duration
        // was last written to the session's metadata -- which, without
        // this call, would not necessarily be the latest one.
        updateMediaSessionMetadata()
        updateMediaSessionPlaybackState()
        if (isOwner) {
            buildAndShowNotification()
        }
    }

    /**
     * Update notification position
     */
    fun updatePosition(position: Long) {
        if (!isShowing) return

        this.position = position
        updateMediaSessionPlaybackState()
    }

    /**
     * Dismiss the notification
     */
    fun dismiss() {
        android.util.Log.d(TAG, "Dismissing notification")

        notificationManager?.cancel(notificationId)
        mediaSession?.isActive = false
        isShowing = false
        currentArtworkBitmap = null
    }

    /**
     * Called on the *previous* owner when another [NotificationHandler]
     * instance claims ownership via `initialize()`. Deactivates this
     * instance's [MediaSessionCompat] so it stops competing for hardware
     * media-button routing, and cancels its tray notification so only the
     * current owner's notification is visible. Local media/playback state
     * (title, position, `mediaSession` metadata) is left untouched so this
     * instance can republish immediately and correctly if it is later
     * promoted back via [promoteToOwner].
     */
    internal fun demoteFromOwner() {
        android.util.Log.d(TAG, "Player $playerId demoted from notification ownership")
        mediaSession?.isActive = false
        if (isShowing) {
            notificationManager?.cancel(notificationId)
        }
    }

    /**
     * Called on the successor instance when the current owner disposes (see
     * [dispose]). Reactivates this instance's [MediaSessionCompat] — so it is
     * eligible again for hardware media-button routing / the system's "now
     * playing" surface — and, if it has content to show, republishes its own
     * tray notification (a distinct [notificationId] per player, so this
     * never collides with the disposed owner's already-cancelled
     * notification) built from its most recently tracked metadata/playback
     * state, and applies that same state to the correct
     * [PlaybackStateCompat] actions so the lock screen responds, not just the
     * notification.
     */
    internal fun promoteToOwner() {
        android.util.Log.d(TAG, "Player $playerId promoted to notification owner")
        mediaSession?.isActive = true
        if (isShowing) {
            // Give artwork resolution one more explicit chance. A
            // non-owner's background attempt (kicked off unconditionally by
            // resolveArtworkIfNeeded from showNotification()) may still be
            // missing here -- still in flight, already failed, or (before
            // the ARTWORK_FETCH_TIMEOUT_MS fix on loadArtwork) silently
            // hung -- and a non-owner had no way to notice or retry on its
            // own, since buildAndShowNotification() below (the only thing
            // that would have surfaced a missing bitmap) was never called
            // for it. No-ops if a bitmap is already resolved or a fetch is
            // already in flight (see artworkLoadInFlight).
            resolveArtworkIfNeeded()
            updateMediaSessionMetadata()
            updateMediaSessionPlaybackState()
            buildAndShowNotification()
        }
    }

    /**
     * Dispose the notification handler
     */
    fun dispose() {
        android.util.Log.d(TAG, "Disposing notification handler")

        // Cancel all coroutines owned by this handler (artwork loading, action forwarding).
        scope.cancel()

        // Always clear this instance's own visible notification / session-
        // active state first. dismiss() is a self-only operation regardless
        // of ownership (each player has its own notification id and
        // MediaSessionCompat — see class doc), so it never disturbs another
        // player. It does not release ownership by itself; the hand-off is
        // evaluated explicitly below.
        dismiss()

        when (val result = NotificationOwnership.release(this)) {
            is NotificationOwnership.ReleaseResult.NotOwner -> {
                // This instance never owned hardware routing / the tray
                // notification (or had already lost it to a later
                // initialize() call elsewhere), so its disposal does not
                // affect any other player.
            }
            is NotificationOwnership.ReleaseResult.HandedOff -> {
                android.util.Log.d(
                    TAG,
                    "Notification ownership handed off from $playerId to ${result.successor.playerId}"
                )
                result.successor.promoteToOwner()
            }
            NotificationOwnership.ReleaseResult.TornDown -> {
                android.util.Log.d(TAG, "No other player active — notification ownership fully released")
            }
        }

        // Always remove this instance's own registry entry, on every dispose
        // path, regardless of the ownership outcome above — a static registry
        // holding MediaSessionCompat objects would otherwise leak if this
        // were ever skipped.
        activeSessions.remove(playerId)
        mediaSession?.release()
        mediaSession = null
        notificationManager = null
    }

    // Private helper methods

    private fun buildAndShowNotification() {
        val notification = buildNotification()
        this.notification = notification
        notificationManager?.notify(notificationId, notification)
    }

    private fun buildNotification(): Notification {
        if (smallIconResId == 0) {
            // Defensive: buildNotification() should only run after initialize(),
            // but never ship a notification with an unresolved (0) icon resource.
            smallIconResId = resolveSmallIcon(null)
        }

        // Track the index each added action will occupy so the compact-view
        // indices below always match the actions actually present, regardless of
        // which showXxx flags are enabled. A stale hardcoded (0, 1, 2) referencing
        // indices past the end of the action list is what M-13 fixes.
        val compactViewIndices = mutableListOf<Int>()
        var nextActionIndex = 0

        val builder = NotificationCompat.Builder(context, channelId)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setSmallIcon(smallIconResId)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(isPlaying)
            .setShowWhen(false)

        // Add artwork if available
        currentArtworkBitmap?.let {
            builder.setLargeIcon(it)
        }

        // Add actions
        if (showPrevious) {
            builder.addAction(createAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                "previous"
            ))
            compactViewIndices.add(nextActionIndex++)
        }

        if (showPlayPause) {
            if (isPlaying) {
                builder.addAction(createAction(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    "pause"
                ))
            } else {
                builder.addAction(createAction(
                    android.R.drawable.ic_media_play,
                    "Play",
                    "play"
                ))
            }
            compactViewIndices.add(nextActionIndex++)
        }

        if (showNext) {
            builder.addAction(createAction(
                android.R.drawable.ic_media_next,
                "Next",
                "next"
            ))
            compactViewIndices.add(nextActionIndex++)
        }

        if (showStop) {
            builder.addAction(createAction(
                android.R.drawable.ic_delete,
                "Stop",
                "stop"
            ))
            nextActionIndex++
            // Stop intentionally not prioritized into the (max 3) compact view
            // slots; previous/play-pause/next take priority there, matching the
            // original (0, 1, 2) intent for the default flag configuration.
        }

        // MediaStyle.setShowActionsInCompactView supports at most 3 indices.
        builder.setStyle(androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(mediaSession?.sessionToken)
            .setShowActionsInCompactView(*compactViewIndices.take(3).toIntArray()))

        return builder.build()
    }

    /**
     * Resolves the notification's small-icon drawable resource id.
     *
     * Priority:
     *  1. The host app's [NotificationConfig.smallIcon] (a drawable resource *name*,
     *     e.g. "ic_notification") looked up in the host app's own resources via
     *     [android.content.res.Resources.getIdentifier]. This is the field already
     *     defined and serialized by `NotificationConfig` in the Dart layer
     *     (lib/src/models/notification_config.dart) — it was simply never read
     *     natively before this fix.
     *  2. The host app's own launcher/application icon ([android.content.pm.
     *     ApplicationInfo.icon]), which every installed app has, so every
     *     integrating app gets a distinct, branded icon by default instead of a
     *     generic system glyph.
     *  3. `android.R.drawable.ic_media_play` as a last-resort fallback that can
     *     never fail to resolve.
     */
    private fun resolveSmallIcon(configuredName: String?): Int {
        if (!configuredName.isNullOrBlank()) {
            val resId = context.resources.getIdentifier(configuredName, "drawable", context.packageName)
            if (resId != 0) {
                return resId
            }
            android.util.Log.w(
                TAG,
                "NotificationConfig.smallIcon '$configuredName' was not found in the host app's " +
                    "drawable resources; falling back to the app icon. Ensure a drawable with " +
                    "that name exists in the host app's res/drawable."
            )
        }
        val appIcon = context.applicationInfo.icon
        return if (appIcon != 0) appIcon else android.R.drawable.ic_media_play
    }

    /**
     * Builds a notification action whose PendingIntent routes through
     * [NotificationActionReceiver] to this instance's [MediaSessionCompat]. This
     * replaces a prior implementation that broadcast a bespoke
     * "com.zionmedianetwork.zmedia_player.NOTIFICATION_ACTION" intent with no
     * registered receiver anywhere in the module or the example app — those taps
     * were silently dropped by the OS (B-08). Bluetooth/lock-screen/Android Auto
     * controls were never affected because they call the MediaSessionCompat.Callback
     * below directly; this fix makes notification taps use that same, already-working
     * path instead of finishing the abandoned parallel mechanism.
     */
    private fun createAction(icon: Int, title: String, action: String): NotificationCompat.Action {
        val playbackAction = when (action) {
            "previous" -> PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
            "play" -> PlaybackStateCompat.ACTION_PLAY
            "pause" -> PlaybackStateCompat.ACTION_PAUSE
            "next" -> PlaybackStateCompat.ACTION_SKIP_TO_NEXT
            "stop" -> PlaybackStateCompat.ACTION_STOP
            else -> PlaybackStateCompat.ACTION_PLAY_PAUSE
        }

        return NotificationCompat.Action.Builder(icon, title, buildMediaButtonPendingIntent(playbackAction)).build()
    }

    /**
     * Builds an explicit `ACTION_MEDIA_BUTTON` broadcast [PendingIntent] targeting
     * [NotificationActionReceiver], carrying a synthetic [android.view.KeyEvent] for
     * [playbackAction] plus this instance's [playerId].
     *
     * This mirrors `androidx.media.session.MediaButtonReceiver
     * .buildMediaButtonPendingIntent(Context, ComponentName, long)` (same action,
     * same explicit-component broadcast contract, same key-code mapping via
     * `PlaybackStateCompat.toKeyCode`) but is hand-built rather than calling that
     * helper directly, because the helper does not let us attach the "playerId"
     * extra our receiver needs to route to the right session when multiple player
     * instances are active concurrently.
     *
     * We deliberately do *not* declare an `ACTION_MEDIA_BUTTON` intent-filter on
     * [NotificationActionReceiver] in the manifest — every PendingIntent we hand to
     * the system here already targets it explicitly by component, so no implicit
     * intent-filter is needed. That also avoids colliding with any other
     * MediaSessionCompat-based plugin (e.g. audio_service, just_audio_background)
     * that a host app may combine with this one and that also wants to be the
     * unique implicit `ACTION_MEDIA_BUTTON` receiver.
     */
    private fun buildMediaButtonPendingIntent(playbackAction: Long): PendingIntent {
        val keyCode = PlaybackStateCompat.toKeyCode(playbackAction)
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setClass(context, NotificationActionReceiver::class.java)
            putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode))
            putExtra(NotificationActionReceiver.EXTRA_PLAYER_ID, playerId)
        }

        return PendingIntent.getBroadcast(
            context,
            // Distinct request code per (playerId, key code) so concurrent
            // instances' actions don't collide and overwrite each other's
            // PendingIntents via FLAG_UPDATE_CURRENT.
            31 * playerId.hashCode() + keyCode,
            intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
    }

    private fun updateMediaSessionMetadata() {
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)

        currentArtworkBitmap?.let {
            metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
        }

        mediaSession?.setMetadata(metadata.build())
    }

    /**
     * Kicks off artwork resolution (network fetch of [currentArtworkUrl], or
     * a generated video-frame thumbnail from [currentMediaUrl] if no artwork
     * URL was provided) if no bitmap is available yet and nothing is already
     * in flight. A no-op otherwise.
     *
     * Deliberately **not** gated on [isOwner]: acquiring the bitmap and
     * *posting* a notification that displays it are two different concerns.
     * Only the latter is ownership-gated (in [showNotification],
     * [updateState], and the completion callbacks below, all of which check
     * `if (isOwner)` before calling [buildAndShowNotification]). A non-owner
     * still needs the data resolved and cached on [currentArtworkBitmap] so
     * that whenever it *is* promoted (see [promoteToOwner]), it has
     * something to show immediately instead of starting from scratch.
     *
     * Called from three places: [showNotification] (the original,
     * unconditional attempt every player instance makes, owner or not),
     * [promoteToOwner] (a safety-net retry — see its doc for why one may
     * still be needed), and nowhere else; [updateState] intentionally does
     * not call this since it never changes which media item is showing.
     */
    private fun resolveArtworkIfNeeded() {
        if (currentArtworkBitmap != null || artworkLoadInFlight) return
        val artworkUrl = currentArtworkUrl
        val mediaUrl = currentMediaUrl
        if (!artworkUrl.isNullOrEmpty()) {
            loadArtwork(artworkUrl)
        } else if (!mediaUrl.isNullOrEmpty()) {
            generateThumbnail(mediaUrl)
        }
    }

    private fun updateMediaSessionPlaybackState() {
        val state = PlaybackStateCompat.Builder()
            .setState(
                if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                position,
                1.0f
            )
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SEEK_TO
            )
            .build()

        mediaSession?.setPlaybackState(state)
    }

    private fun loadArtwork(url: String) {
        artworkLoadInFlight = true
        // Load artwork asynchronously on the IO dispatcher via the owned scope.
        scope.launch(Dispatchers.IO) {
            try {
                val connection = URL(url).openConnection()
                // URLConnection has no timeout by default and will block
                // connect()/getInputStream() indefinitely on a stalled
                // connection -- see ARTWORK_FETCH_TIMEOUT_MS doc.
                connection.connectTimeout = ARTWORK_FETCH_TIMEOUT_MS
                connection.readTimeout = ARTWORK_FETCH_TIMEOUT_MS
                connection.connect()
                val input = connection.getInputStream()
                val bitmap = android.graphics.BitmapFactory.decodeStream(input)
                input.close()

                withContext(Dispatchers.Main) {
                    // Discard a stale fetch if the media item's artwork URL
                    // changed while this request was in flight (mirrors the
                    // equivalent guard in generateThumbnail).
                    if (currentArtworkUrl == url && currentArtworkBitmap == null) {
                        currentArtworkBitmap = bitmap
                        if (isShowing) {
                            updateMediaSessionMetadata()
                            if (isOwner) {
                                buildAndShowNotification()
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to load artwork: ${e.message}")
            }
            withContext(Dispatchers.Main) {
                artworkLoadInFlight = false
            }
        }
    }

    /**
     * Generates a thumbnail from the video at [url] and sets it as the
     * notification artwork.  Called only when artworkUrl is absent.
     * Works with remote URLs; MediaMetadataRetriever reads just the range
     * it needs so it does not download the entire file.
     *
     * Black-frame avoidance strategy
     * ─────────────────────────────
     * Many videos (e.g. Big Buck Bunny) open with a black fade-in.
     * The previous implementation called getFrameAtTime(1_000_000,
     * OPTION_CLOSEST_SYNC), which snaps to the nearest sync (I-frame)
     * at or before the requested time — often frame 0 (black).
     *
     * The fix has two parts:
     *   1. Read the actual duration before choosing the target position so we
     *      can pick a time well inside real content.
     *   2. Use OPTION_CLOSEST instead of OPTION_CLOSEST_SYNC so the decoder
     *      returns the actual frame at the target time rather than the nearest
     *      (possibly distant, possibly black) sync keyframe.
     *
     * Target time calculation (same formula as iOS):
     *   • durationMs ≥ 3 000 ms → clamp(durationMs × 0.1, 3 000 ms, 10 000 ms)
     *   • 0 < durationMs < 3 000 ms  → durationMs / 2   (short clip, midpoint)
     *   • fallback (unknown / 0)      → 5 000 ms fixed
     */
    private fun generateThumbnail(url: String) {
        artworkLoadInFlight = true
        scope.launch(Dispatchers.IO) {
            val retriever = android.media.MediaMetadataRetriever()
            try {
                // Pass an empty headers map so the overload that accepts headers
                // is used — this avoids the deprecated single-argument setDataSource.
                retriever.setDataSource(url, emptyMap<String, String>())

                // Read the actual duration so we can pick a meaningful target time.
                val durationMs = retriever
                    .extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L

                // Compute target time in milliseconds, then convert to microseconds.
                val targetMs: Long = when {
                    durationMs >= 3_000L -> {
                        // 10 % of duration, clamped to [3 s, 10 s]
                        val tenPercent = (durationMs * 0.1).toLong()
                        tenPercent.coerceIn(3_000L, 10_000L)
                    }
                    durationMs > 0L -> {
                        // Very short clip — use the midpoint
                        durationMs / 2
                    }
                    else -> {
                        // Unknown duration — fixed 5-second offset
                        5_000L
                    }
                }
                val targetUs = targetMs * 1_000L

                android.util.Log.d(TAG, "Thumbnail: duration=${durationMs}ms → target=${targetMs}ms")

                // OPTION_CLOSEST returns the actual decoded frame nearest the
                // requested time, not the nearest sync keyframe.  This means
                // we get the frame at ~targetMs even if it is a P- or B-frame,
                // rather than snapping back to the (potentially black) keyframe
                // at t=0.
                val bitmap = retriever.getFrameAtTime(
                    targetUs,
                    android.media.MediaMetadataRetriever.OPTION_CLOSEST
                )

                withContext(Dispatchers.Main) {
                    // Only apply if the media item hasn't changed while we were
                    // generating (guard by comparing the URL captured at trigger time).
                    if (currentMediaUrl == url && currentArtworkBitmap == null) {
                        currentArtworkBitmap = bitmap
                        if (isShowing && bitmap != null) {
                            updateMediaSessionMetadata()
                            if (isOwner) {
                                buildAndShowNotification()
                            }
                            android.util.Log.d(TAG, "Video thumbnail generated and applied")
                        }
                    } else {
                        android.util.Log.d(TAG, "Thumbnail discarded — media changed during generation")
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to generate thumbnail: ${e.message}")
            } finally {
                try {
                    retriever.release()
                } catch (ignore: Exception) {
                    // release() itself can throw on some older API levels; ignore.
                }
            }
            withContext(Dispatchers.Main) {
                artworkLoadInFlight = false
            }
        }
    }

    private fun sendActionToFlutter(action: String, position: Long? = null) {
        scope.launch {
            val arguments = mutableMapOf<String, Any>(
                "playerId" to playerId,
                "action" to action
            )
            // Only "seekTo" ever carries a position; matches the iOS payload
            // shape exactly (see NotificationHandler.swift's
            // sendActionToFlutter) so Dart's NotificationActionEvent.fromMap
            // parses the same map shape from either platform.
            if (position != null) {
                arguments["position"] = position
            }
            methodChannel.invokeMethod("onNotificationAction", arguments)
        }
    }
}

/**
 * Manifest-registered receiver (see `android/src/main/AndroidManifest.xml`) that
 * routes taps on media-notification action buttons back to the correct player's
 * [MediaSessionCompat].
 *
 * Every [android.app.PendingIntent] that reaches this receiver is built by
 * [NotificationHandler.buildMediaButtonPendingIntent] with an explicit component
 * target (this class) and always carries [Intent.EXTRA_KEY_EVENT] plus
 * [EXTRA_PLAYER_ID]. The system instantiates a fresh receiver instance per
 * broadcast, so it cannot hold player state itself — it looks the owning
 * [MediaSessionCompat] up via [NotificationHandler.sessionFor] and hands the intent
 * to `androidx.media.session.MediaButtonReceiver.handleIntent`, which decodes the
 * [android.view.KeyEvent] and calls
 * `MediaControllerCompat.dispatchMediaButtonEvent`. That, in turn, invokes the same
 * [MediaSessionCompat.Callback] (onPlay/onPause/onSkipToNext/onSkipToPrevious/
 * onStop) already wired in [NotificationHandler.initialize] and already used by
 * Bluetooth/lock-screen/Android Auto controls — so notification taps now forward to
 * Flutter via the exact same, already-verified path (fixes B-08).
 *
 * No host-app manifest changes are required: this receiver is declared in this
 * module's own `AndroidManifest.xml` and is merged into every consuming app's
 * manifest automatically by the Android Gradle build's manifest merger, the same
 * mechanism most plugins use to register their own receivers/services. The host app
 * does not need to add anything for the notification buttons themselves to work.
 */
class NotificationActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val playerId = intent.getStringExtra(EXTRA_PLAYER_ID) ?: return
        val session = NotificationHandler.sessionFor(playerId) ?: return
        MediaButtonReceiver.handleIntent(session, intent)
    }

    companion object {
        const val EXTRA_PLAYER_ID = "playerId"
    }
}

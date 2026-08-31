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

        // Registry of live NotificationHandler instances keyed by playerId, used by
        // NotificationDismissReceiver and NotificationCustomActionReceiver below --
        // same rationale as activeSessions (both are manifest-registered
        // BroadcastReceivers the OS instantiates fresh per broadcast). Held as a
        // WeakReference so a handler that failed to dispose() cleanly for any reason
        // cannot be kept alive by this registry.
        private val liveHandlers = mutableMapOf<String, WeakReference<NotificationHandler>>()

        internal fun handlerFor(playerId: String): NotificationHandler? = liveHandlers[playerId]?.get()
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

    // NotificationConfig.showSeekForward / showSeekBackward / seekInterval (see
    // notification_config.dart). Contract, identical on both platforms: a seek
    // button is rendered if and only if the flag is true AND the current item is
    // seekable (see isSeekable below) -- a live stream without DVR can never show
    // one, even if the host app asks for it. Applied in buildNotification() (the
    // notification buttons themselves) and updateMediaSessionPlaybackState()
    // (ACTION_FAST_FORWARD/ACTION_REWIND, which is what Bluetooth/Android Auto/
    // Wear surfaces read). Because both run again on every showNotification()/
    // updateState() call, a mid-playback change to isSeekable (e.g. a DVR toggle)
    // re-applies the gating automatically.
    //
    // seekInterval is a *display* value here, exactly as it is on iOS
    // (skipForwardCommand.preferredIntervals): it only labels the buttons
    // ("Forward 10s"). The actual seek is performed by the host app's
    // NotificationService.actionEventStream handler, which must apply the same
    // interval itself -- native never seeks the player for a transport action.
    private var showSeekForward: Boolean = false
    private var showSeekBackward: Boolean = false
    private var seekInterval: Int = 10

    // NotificationConfig.priority (see notification_config.dart): resolved once in
    // initialize() into both the Android-version-appropriate representations, since
    // channel importance (API 26+, fixed at channel-creation time) and
    // NotificationCompat's legacy priority int (pre-26, and still read by some OEM
    // skins/Wear/Auto surfaces even on 26+) are two different value spaces.
    private var channelImportance: Int = NotificationManager.IMPORTANCE_LOW
    private var compatPriority: Int = NotificationCompat.PRIORITY_LOW

    // NotificationConfig.dismissible (see notification_config.dart): true posts the
    // notification as non-ongoing with a delete intent instead of the historical
    // always-ongoing-while-playing behavior. See buildNotification()/buildDeleteIntent().
    private var dismissible: Boolean = false

    // NotificationConfig.customActions (see notification_config.dart): rendered as
    // real additional NotificationCompat.Action buttons in buildNotification(),
    // dispatched back to Flutter by id via NotificationCustomActionReceiver.
    private var customActions: List<Map<String, Any?>> = emptyList()

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

    // Wired from the "mediaItem" map's "isLive"/"dvrEnabled" keys in
    // showNotification(), and re-synced from the "state" map's own
    // "isLive"/"dvrEnabled" keys on every updateState() call (see that
    // method) -- both are read from MediaPlayer.isLive/MediaPlayer.dvrEnabled
    // on the Dart side (see NotificationService.show()/updateState() in
    // notification_service.dart). dvrEnabled in particular can change while
    // the same media item keeps playing (e.g. the host app reconfigures
    // HlsConfig.enableDvr and reloads), so updateState() -- not just
    // showNotification() -- must be able to update these. Both default to
    // false, matching every non-live item.
    private var isLive: Boolean = false
    private var dvrEnabled: Boolean = false

    /**
     * `false` only for a live stream without DVR enabled -- mirrors
     * `MediaPlayer.isSeekable` in media_player.dart exactly. Gates
     * [PlaybackStateCompat.ACTION_SEEK_TO] (see [updateMediaSessionPlaybackState]),
     * [MediaMetadataCompat.METADATA_KEY_DURATION] (see [updateMediaSessionMetadata]),
     * the [MediaSessionCompat.Callback.onSeekTo] callback below, and -- together with
     * the `showSeekForward`/`showSeekBackward` config flags -- the seek-forward/
     * seek-backward notification buttons plus their
     * [PlaybackStateCompat.ACTION_FAST_FORWARD]/[PlaybackStateCompat.ACTION_REWIND]
     * advertisement. A live stream with no DVR must not offer, or honor, scrubbing or
     * relative seeking from the lock screen / notification.
     */
    private val isSeekable: Boolean
        get() = !(isLive && !dvrEnabled)

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

        // NotificationConfig.priority: resolved once here into both value spaces --
        // see the channelImportance/compatPriority doc above.
        val priorityName = config["priority"] as? String
        channelImportance = resolveChannelImportance(priorityName)
        compatPriority = resolveCompatPriority(priorityName)

        // NotificationConfig.dismissible: see the dismissible field doc above and
        // buildNotification()/buildDeleteIntent() for how it's applied.
        dismissible = config["dismissible"] as? Boolean ?: dismissible

        // NotificationConfig.customActions: a List<Map> from NotificationAction.toMap()
        // (id/title/icon). Cast defensively -- this crosses a MethodChannel boundary.
        @Suppress("UNCHECKED_CAST")
        customActions = (config["customActions"] as? List<*>)
            ?.mapNotNull { it as? Map<String, Any?> }
            ?: emptyList()

        // Initialize notification manager
        notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel for Android O and above. Importance can only be
        // set at creation time -- the OS ignores changes to an already-created
        // channel's importance -- so a changed priority only takes effect for a
        // channel the user hasn't already seen (a new channelId, a fresh install, or
        // the user manually reset notification settings for this app).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                channelImportance
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

                /**
                 * Reached both by a tap on the notification's seek-forward button (via
                 * [buildMediaButtonPendingIntent]'s synthetic `KEYCODE_MEDIA_FAST_FORWARD`
                 * routed through [NotificationActionReceiver]) and by any hardware /
                 * Bluetooth / Android Auto fast-forward control, exactly like the
                 * play/pause/next/previous callbacks above.
                 *
                 * Forwards `"seekForward"` -- the same action string iOS's
                 * `skipForwardCommand` target sends (see NotificationHandler.swift) and the
                 * value of `NotificationActions.seekForward` in notification_service.dart.
                 * This handler does not seek the player itself; Dart/the host app owns that,
                 * including choosing the seek amount (see the seekInterval field doc).
                 */
                override fun onFastForward() {
                    android.util.Log.d(TAG, "MediaSession: onFastForward")
                    if (!isSeekable) {
                        // Belt-and-braces: ACTION_FAST_FORWARD is already omitted from
                        // PlaybackStateCompat and the button is not rendered at all while
                        // !isSeekable (see updateMediaSessionPlaybackState/buildNotification).
                        // Reject explicitly anyway, mirroring onSeekTo's guard above.
                        android.util.Log.d(TAG, "MediaSession: onFastForward ignored -- not seekable (live without DVR)")
                        return
                    }
                    sendActionToFlutter("seekForward")
                }

                /** Seek-backward counterpart of [onFastForward]; forwards `"seekBackward"`. */
                override fun onRewind() {
                    android.util.Log.d(TAG, "MediaSession: onRewind")
                    if (!isSeekable) {
                        android.util.Log.d(TAG, "MediaSession: onRewind ignored -- not seekable (live without DVR)")
                        return
                    }
                    sendActionToFlutter("seekBackward")
                }

                override fun onSeekTo(pos: Long) {
                    android.util.Log.d(TAG, "MediaSession: onSeekTo $pos")
                    if (!isSeekable) {
                        // Belt-and-braces: ACTION_SEEK_TO is already omitted from
                        // PlaybackStateCompat while !isSeekable (see
                        // updateMediaSessionPlaybackState), which should prevent the OS
                        // from ever routing here for a live-without-DVR stream. Still
                        // reject explicitly rather than forwarding to Flutter, in case
                        // some surface (e.g. a stale controller) calls it anyway --
                        // mirrors MediaPlayer.seekTo's own guard in media_player.dart.
                        android.util.Log.d(TAG, "MediaSession: onSeekTo ignored -- not seekable (live without DVR)")
                        return
                    }
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

        // Publish this instance so NotificationDismissReceiver/
        // NotificationCustomActionReceiver can route back to it (see liveHandlers
        // above).
        liveHandlers[playerId] = WeakReference(this)

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

        // Read isLive/dvrEnabled before touching duration below -- isSeekable
        // (derived from both) decides whether the incoming duration is honored at
        // all. Sent by NotificationService.show() (see notification_service.dart);
        // both default to false, i.e. non-live, if absent (an older cached Dart
        // build that predates this wiring).
        isLive = mediaItem["isLive"] as? Boolean ?: false
        dvrEnabled = mediaItem["dvrEnabled"] as? Boolean ?: false

        // Update playback state
        isPlaying = state["isPlaying"] as? Boolean ?: false
        position = (state["position"] as? Number)?.toLong() ?: 0
        // A live-without-DVR item must never publish a scrubbable duration -- see
        // isSeekable doc. This is a genuine media-item change (showNotification, not
        // updateState), so -- unlike updateState()'s anti-regression guard below --
        // resetting duration to 0 here is exactly the intended behavior, not a
        // regression: a live-without-DVR item is never expected to have a meaningful
        // total duration.
        duration = if (isSeekable) (state["duration"] as? Number)?.toLong() ?: 0 else 0

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

        // Re-sync isLive/dvrEnabled from this call too -- see the field doc
        // above for why this can legitimately change without a new
        // showNotification() call (a DVR toggle on the same media item).
        // Only overwrite when the key is actually present, so an older
        // cached Dart build that predates this wiring (and never sends these
        // keys to updateNotificationState) cannot silently reset a
        // live-without-DVR item back to "seekable", or vice versa.
        if (state.containsKey("isLive")) {
            isLive = state["isLive"] as? Boolean ?: isLive
        }
        if (state.containsKey("dvrEnabled")) {
            dvrEnabled = state["dvrEnabled"] as? Boolean ?: dvrEnabled
        }

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
        // it becomes known.) isSeekable is excepted from that guard: a
        // live-without-DVR item must never publish a scrubbable duration (see
        // isSeekable doc), so duration is forced back to 0 on every call while it
        // holds, same as showNotification() above.
        if (!isSeekable) {
            duration = 0
        } else {
            val incomingDuration = (state["duration"] as? Number)?.toLong() ?: 0
            if (incomingDuration > 0) {
                duration = incomingDuration
            }
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
     * Called via [buildDeleteIntent]'s [PendingIntent] (routed through
     * [NotificationDismissReceiver]) when the user swipes away a `dismissible`
     * notification. Only syncs local [isShowing] state so a later
     * [showNotification]/[updateState] call correctly reposts rather than treating
     * the notification as still visible; deliberately does not touch
     * [mediaSession] activation or forward anything to Flutter -- swiping away the
     * notification does not necessarily mean the user wants playback (or hardware
     * media-button routing) to stop, only that the visible notification is gone.
     */
    internal fun onNotificationDismissedByUser() {
        android.util.Log.d(TAG, "Notification dismissed by user swipe (dismissible=true)")
        isShowing = false
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

        // Always remove this instance's own registry entries, on every dispose
        // path, regardless of the ownership outcome above — a static registry
        // holding MediaSessionCompat/NotificationHandler references would
        // otherwise leak if this were ever skipped.
        activeSessions.remove(playerId)
        liveHandlers.remove(playerId)
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
            .setPriority(compatPriority)
            // This notification is rebuilt and re-`notify()`'d on every
            // showNotification()/updateState() call -- i.e. on every playback
            // state change and, effectively, on every position tick, since
            // updateState() is driven by MediaPlayer.stateStream. Without
            // onlyAlertOnce, each repost is a distinct alert to the OS; at
            // typical position-update frequency Android's "noisy
            // notification" throttling (NotificationManagerService) detects
            // this as spam and force-mutes the whole channel/app
            // ("Muting recently noisy ..." in logcat), silently killing the
            // notification altogether. true makes only the *first* post of a
            // given ongoing notification alert (sound/vibrate/heads-up);
            // every subsequent update-in-place is silent, which is exactly
            // what a continuously-refreshing media notification needs.
            .setOnlyAlertOnce(true)
            // NotificationConfig.dismissible (see field doc): true makes the
            // notification swipeable at any playback state instead of the
            // historical always-ongoing-while-playing behavior.
            .setOngoing(!dismissible)
            .setShowWhen(false)

        if (dismissible) {
            builder.setDeleteIntent(buildDeleteIntent())
        }

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

        // NotificationConfig.showSeekBackward (see field doc): rendered if and only if
        // the flag is set AND the current item is seekable. Placed between
        // "previous" and play/pause so the expanded notification reads
        // previous / -Ns / play-pause / +Ns / next, and deliberately left out of
        // compactViewIndices -- the (max 3) compact slots stay reserved for the
        // primary transport controls.
        if (showSeekBackward && isSeekable) {
            builder.addAction(createAction(
                android.R.drawable.ic_media_rew,
                "Back ${seekInterval}s",
                "seekBackward"
            ))
            nextActionIndex++
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

        // NotificationConfig.showSeekForward (see field doc): same contract and same
        // compact-view treatment as showSeekBackward above.
        if (showSeekForward && isSeekable) {
            builder.addAction(createAction(
                android.R.drawable.ic_media_ff,
                "Forward ${seekInterval}s",
                "seekForward"
            ))
            nextActionIndex++
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

        // NotificationConfig.customActions (see field doc): app-defined buttons in
        // addition to the built-in transport controls above. Like "stop", not
        // prioritized into the (max 3) compact-view slots -- those are reserved for
        // the primary transport controls.
        for (customAction in customActions) {
            val id = customAction["id"] as? String ?: continue
            val title = customAction["title"] as? String ?: id
            val icon = resolveActionIcon(customAction["icon"] as? String)
            builder.addAction(
                NotificationCompat.Action.Builder(icon, title, buildCustomActionPendingIntent(id)).build()
            )
            nextActionIndex++
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
            // Map to the two transport actions PlaybackStateCompat.toKeyCode() knows
            // how to turn into KEYCODE_MEDIA_FAST_FORWARD / KEYCODE_MEDIA_REWIND, which
            // MediaSessionCompat.Callback.onMediaButtonEvent then dispatches to
            // onFastForward()/onRewind() above -- the same already-working route the
            // other buttons take.
            "seekForward" -> PlaybackStateCompat.ACTION_FAST_FORWARD
            "seekBackward" -> PlaybackStateCompat.ACTION_REWIND
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

    /**
     * Builds the [PendingIntent] handed to [NotificationCompat.Builder.setDeleteIntent]
     * for a `dismissible` notification (see the `dismissible` field doc). Broadcasts to
     * [NotificationDismissReceiver], which routes to this instance via
     * [handlerFor]/[onNotificationDismissedByUser] so [isShowing] stays in sync with
     * what's actually on screen.
     */
    private fun buildDeleteIntent(): PendingIntent {
        val intent = Intent(context, NotificationDismissReceiver::class.java).apply {
            putExtra(NotificationDismissReceiver.EXTRA_PLAYER_ID, playerId)
        }
        return PendingIntent.getBroadcast(
            context,
            31 * playerId.hashCode() + 1,
            intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
    }

    /**
     * Builds the [PendingIntent] for a single [NotificationConfig.customActions] entry
     * (see the `customActions` field doc). Broadcasts to
     * [NotificationCustomActionReceiver], which routes to this instance's
     * [dispatchCustomAction] so the tap reaches Flutter the same way every other
     * notification action does (via `onNotificationAction` / [NotificationActionEvent]).
     */
    private fun buildCustomActionPendingIntent(actionId: String): PendingIntent {
        val intent = Intent(context, NotificationCustomActionReceiver::class.java).apply {
            putExtra(NotificationCustomActionReceiver.EXTRA_PLAYER_ID, playerId)
            putExtra(NotificationCustomActionReceiver.EXTRA_ACTION_ID, actionId)
        }
        return PendingIntent.getBroadcast(
            context,
            // Distinct request code per (playerId, action id) so concurrent instances'
            // and different custom actions' PendingIntents don't collide -- mirrors
            // buildMediaButtonPendingIntent's rationale above.
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
     * Resolves a [NotificationAction.icon] resource name the same way
     * [resolveSmallIcon] resolves [NotificationConfig.smallIcon]. Falls back to the
     * same last-resort glyph [resolveSmallIcon] uses (`android.R.drawable.ic_media_play`,
     * guaranteed to resolve on every API level) rather than the host app's own icon --
     * an unresolved custom-action icon should look like a generic system glyph, not
     * silently reuse the app's launcher icon for an arbitrary button.
     */
    private fun resolveActionIcon(configuredName: String?): Int {
        if (!configuredName.isNullOrBlank()) {
            val resId = context.resources.getIdentifier(configuredName, "drawable", context.packageName)
            if (resId != 0) {
                return resId
            }
            android.util.Log.w(
                TAG,
                "NotificationAction.icon '$configuredName' was not found in the host app's " +
                    "drawable resources; falling back to a generic icon. Ensure a drawable with " +
                    "that name exists in the host app's res/drawable."
            )
        }
        return android.R.drawable.ic_media_play
    }

    /**
     * Maps [NotificationConfig.priority]'s wire value (a [NotificationPriority] enum
     * name, e.g. `"high"`, or `null`/absent if the host app never set it) onto a
     * [NotificationChannel] importance. Only meaningful at channel-creation time
     * (API 26+) -- see the call site's comment for why a changed priority may not
     * retroactively apply. Unrecognized/absent values (including `null`, which is
     * `NotificationConfig.priority`'s default -- see its dartdoc in
     * notification_config.dart) fall back to `IMPORTANCE_LOW`, matching this
     * handler's original hardcoded behavior so a host app that never sets `priority`
     * sees no change. A host app that explicitly opts into
     * [NotificationPriority.high] (or another non-default value) gets that value
     * honored, which is the actual point of wiring this field up.
     */
    private fun resolveChannelImportance(priority: String?): Int = when (priority) {
        "min" -> NotificationManager.IMPORTANCE_MIN
        "low" -> NotificationManager.IMPORTANCE_LOW
        "defaultPriority" -> NotificationManager.IMPORTANCE_DEFAULT
        "high" -> NotificationManager.IMPORTANCE_HIGH
        // Android has no channel importance above IMPORTANCE_HIGH (the deprecated
        // IMPORTANCE_MAX constant is documented as behaving identically to HIGH).
        "max" -> NotificationManager.IMPORTANCE_HIGH
        else -> NotificationManager.IMPORTANCE_LOW
    }

    /** Same mapping as [resolveChannelImportance], but onto [NotificationCompat]'s
     * legacy `PRIORITY_*` ints -- read by [NotificationCompat.Builder.setPriority] on
     * every posted notification (pre-26 devices, and still consulted by some OEM
     * skins/Wear/Auto surfaces even on 26+, unlike channel importance which is
     * API-26-only). Unlike channel importance, PRIORITY_MAX is a distinct, real value
     * here, so `"max"` maps to it rather than being folded into `"high"`.
     */
    private fun resolveCompatPriority(priority: String?): Int = when (priority) {
        "min" -> NotificationCompat.PRIORITY_MIN
        "low" -> NotificationCompat.PRIORITY_LOW
        "defaultPriority" -> NotificationCompat.PRIORITY_DEFAULT
        "high" -> NotificationCompat.PRIORITY_HIGH
        "max" -> NotificationCompat.PRIORITY_MAX
        else -> NotificationCompat.PRIORITY_LOW
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
        // ACTION_SEEK_TO is omitted while !isSeekable (live stream, no DVR) -- its
        // absence is what tells the system (and Bluetooth/Android
        // Auto/Wear/lock-screen surfaces reading PlaybackStateCompat) not to offer
        // scrubbing at all, on top of onSeekTo's own belt-and-braces rejection above.
        var actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
            PlaybackStateCompat.ACTION_STOP
        if (isSeekable) {
            actions = actions or PlaybackStateCompat.ACTION_SEEK_TO
        }
        // ACTION_FAST_FORWARD/ACTION_REWIND follow the exact same
        // "flag AND isSeekable" contract as the notification buttons themselves
        // (see buildNotification and the showSeekForward field doc). Advertising
        // them here is what makes non-notification surfaces (Bluetooth, Android
        // Auto, Wear) offer the controls, and is also what lets the synthetic
        // media-button KeyEvent built by buildMediaButtonPendingIntent be
        // dispatched to onFastForward()/onRewind().
        if (showSeekForward && isSeekable) {
            actions = actions or PlaybackStateCompat.ACTION_FAST_FORWARD
        }
        if (showSeekBackward && isSeekable) {
            actions = actions or PlaybackStateCompat.ACTION_REWIND
        }

        val state = PlaybackStateCompat.Builder()
            .setState(
                if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                position,
                1.0f
            )
            .setActions(actions)
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
                // e.message may embed the artwork URL (with any query-string token) — redact
                // before logging since Log.e is not stripped from release builds (H-03).
                android.util.Log.e(TAG, "Failed to load artwork: ${LogSanitizer.redactUrls(e.message)}")
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
                // e.message may embed the source media URL — redact before logging (H-03).
                android.util.Log.e(TAG, "Failed to generate thumbnail: ${LogSanitizer.redactUrls(e.message)}")
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

    /**
     * Entry point for [NotificationCustomActionReceiver]: forwards a tapped
     * [NotificationConfig.customActions] entry's id to Flutter via the same
     * `onNotificationAction` path as every built-in action (never carries a
     * position -- only "seekTo" ever does).
     */
    internal fun dispatchCustomAction(actionId: String) {
        sendActionToFlutter(actionId)
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
 * onStop/onFastForward/onRewind) already wired in [NotificationHandler.initialize]
 * and already used by
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

/**
 * Manifest-registered receiver (see `android/src/main/AndroidManifest.xml`) for
 * [NotificationCompat.Builder.setDeleteIntent], fired when the user swipes away a
 * `dismissible` notification (see [NotificationConfig.dismissible]'s field doc). Routes
 * to the correct player's [NotificationHandler.onNotificationDismissedByUser] via
 * [NotificationHandler.handlerFor], by the same per-broadcast-instantiation
 * constraint documented on [NotificationActionReceiver].
 *
 * `exported="false"`: only ever triggered via a [PendingIntent] this module builds for
 * itself (see [NotificationHandler.buildDeleteIntent]).
 */
class NotificationDismissReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val playerId = intent.getStringExtra(EXTRA_PLAYER_ID) ?: return
        NotificationHandler.handlerFor(playerId)?.onNotificationDismissedByUser()
    }

    companion object {
        const val EXTRA_PLAYER_ID = "playerId"
    }
}

/**
 * Manifest-registered receiver (see `android/src/main/AndroidManifest.xml`) that
 * routes taps on [NotificationConfig.customActions] buttons back to the correct
 * player's [NotificationHandler.dispatchCustomAction], by the same
 * per-broadcast-instantiation constraint documented on [NotificationActionReceiver].
 * Unlike [NotificationActionReceiver] (which decodes a synthetic media-button
 * [android.view.KeyEvent] for the fixed transport-control set), custom actions carry
 * no such key code -- there is no `PlaybackStateCompat.ACTION_*`/key-code mapping for
 * an app-defined action id -- so this receiver instead carries the action id directly
 * as a string extra (see [NotificationHandler.buildCustomActionPendingIntent]).
 *
 * `exported="false"`: only ever triggered via a [PendingIntent] this module builds for
 * itself.
 */
class NotificationCustomActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val playerId = intent.getStringExtra(EXTRA_PLAYER_ID) ?: return
        val actionId = intent.getStringExtra(EXTRA_ACTION_ID) ?: return
        NotificationHandler.handlerFor(playerId)?.dispatchCustomAction(actionId)
    }

    companion object {
        const val EXTRA_PLAYER_ID = "playerId"
        const val EXTRA_ACTION_ID = "actionId"
    }
}

package com.zionmedianetwork.zmedia_player

import android.app.Activity
import android.util.Log
import android.view.WindowManager

/**
 * B-12 (wave 2 security hardening): opt-in screen-capture protection.
 *
 * Maps [setSecure] to `WindowManager.LayoutParams.FLAG_SECURE` on the host
 * [Activity]'s window. `FLAG_SECURE` is a hard OS-level block — screenshots
 * of the window come back black, the window is excluded from the
 * recent-apps thumbnail, and screen recording / casting APIs cannot capture
 * its contents. There is no way to detect a blocked capture attempt (unlike
 * iOS's `UIScreen.isCaptured`, see `ScreenCaptureHandler.swift`) because a
 * blocked capture never produces any content to react to — this handler
 * never emits any event.
 *
 * `FLAG_SECURE` is scoped to the *window*, not to an individual player
 * surface: Android has no API to mark only part of a window's content as
 * secure. Multiple [MediaPlayer] instances can share the same host
 * `Activity` (e.g. a `ListView` of players, per CLAUDE.md's "Multiple
 * instances are supported" note), so this handler tracks *which* player ids
 * currently want protection and only clears the flag once none of them do —
 * otherwise disabling protection on one player would silently unprotect
 * every other player sharing that window.
 *
 * Deliberately mirrors [PipHandler]'s activity-lifecycle pattern: instances
 * are cached in a long-lived map keyed by playerId
 * ([ZMediaPlayerPlugin.secureSurfaceHandler] — actually a single
 * plugin-lifetime instance here, not one per player, since the window is
 * shared — see [updateActivity]), and the Activity reference is refreshed on
 * every [android.content.pm.ActivityInfo] config-change lifecycle callback
 * so a rotation never leaves this operating against a destroyed Activity.
 */
class SecureSurfaceHandler(activity: Activity?) {
    companion object {
        private const val TAG = "SecureSurfaceHandler"
    }

    // Mutable so the plugin can refresh it on activity lifecycle callbacks
    // (rotation/config change), exactly like PipHandler.activity.
    private var activity: Activity? = activity

    // Player ids that currently want FLAG_SECURE applied. The flag stays set
    // on the window as long as this is non-empty.
    private val securePlayerIds = mutableSetOf<String>()

    /**
     * Refresh the Activity reference held by this handler. Must be called by
     * the owner ([ZMediaPlayerPlugin]) from [android.content.pm.ActivityInfo]
     * config-change-aware `ActivityAware` callbacks
     * (`onAttachedToActivity`/`onReattachedToActivityForConfigChanges`/
     * `onDetachedFromActivity`) exactly like [PipHandler.updateActivity], so
     * that a cached instance never operates against a destroyed
     * pre-rotation Activity — and so the flag is re-applied to the *new*
     * window after a rotation if any player still wants protection.
     */
    fun updateActivity(activity: Activity?) {
        this.activity = activity
        applyFlag()
    }

    /**
     * Enable or disable screen-capture protection for [playerId]. The
     * window-level `FLAG_SECURE` flag reflects whether ANY tracked player id
     * currently wants it — see the class doc.
     */
    fun setSecure(playerId: String, enabled: Boolean) {
        if (enabled) {
            securePlayerIds.add(playerId)
        } else {
            securePlayerIds.remove(playerId)
        }
        applyFlag()
    }

    /**
     * Stop tracking [playerId] entirely (called from `dispose`). Equivalent
     * to `setSecure(playerId, false)` but also removes the id so it can't
     * leak into [securePlayerIds] forever for a player that no longer
     * exists.
     */
    fun clear(playerId: String) {
        securePlayerIds.remove(playerId)
        applyFlag()
    }

    private fun applyFlag() {
        val window = activity?.window
        if (window == null) {
            // No Activity currently attached (e.g. between onDetachedFromActivity
            // and a reattach) — nothing to apply to right now. updateActivity()
            // re-applies once an Activity is available again.
            Log.d(TAG, "applyFlag: no Activity attached, deferring (securePlayerIds=${securePlayerIds.size})")
            return
        }
        if (securePlayerIds.isNotEmpty()) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            Log.d(TAG, "FLAG_SECURE applied (${securePlayerIds.size} player(s) requesting it)")
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            Log.d(TAG, "FLAG_SECURE cleared (no player requesting it)")
        }
    }
}

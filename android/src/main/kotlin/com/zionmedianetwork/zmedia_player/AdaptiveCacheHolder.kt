package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.util.Log
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

/**
 * C-03b: process-wide singleton owner of the single [SimpleCache] instance
 * backing transparent Media3 segment caching for HLS/DASH adaptive streams.
 * Android-only — see `AdaptiveCacheConfig` in
 * lib/src/core/media_config.dart for the full Dart-facing contract
 * (opt-in, default off, DRM never cached, iOS has no equivalent).
 *
 * Media3 hard-requires exactly one [SimpleCache] per cache directory, per
 * process: constructing a second one over the same directory throws
 * `IllegalStateException` (`SimpleCache.isCacheFolderLocked`). This plugin
 * supports multiple concurrent players via [MediaPlayerManager]'s
 * `_instances`-equivalent `players` registry, and — in an add-to-app host —
 * potentially multiple [MediaPlayerManager] instances across multiple
 * `FlutterEngine`s in the same process. A Kotlin `object` is a process-
 * lifetime singleton, so anchoring the cache here (rather than as a
 * [MediaPlayerManager] instance field) is what actually guarantees "one
 * `SimpleCache` per process" regardless of how many plugin/engine instances
 * exist.
 *
 * Reference-counted: each [MediaPlayerManager] calls [acquire] at most once
 * (lazily, the first time any of its players loads an adaptive-cache-
 * enabled HLS/DASH item) and [release] exactly once, from its own
 * `shutdown()`. The underlying [SimpleCache] — and its open SQLite index —
 * is only actually released when the last outstanding acquirer releases.
 */
object AdaptiveCacheHolder {
    private const val TAG = "AdaptiveCacheHolder"
    private const val CACHE_DIR_NAME = "zmedia_adaptive_cache"

    private var cache: SimpleCache? = null
    private var refCount = 0
    private var configuredMaxSizeBytes: Long = 0L

    /**
     * Returns the shared [SimpleCache], creating it on first call. Every
     * call increments the reference count; pair with exactly one call to
     * [release] per caller.
     *
     * [maxSizeBytes] only has effect on the call that actually creates the
     * cache (evictor bounds cannot be changed on an already-open
     * `SimpleCache`); a later call requesting a different size is honored
     * for reference counting but logs a warning that the original size is
     * still in effect.
     */
    @Synchronized
    fun acquire(context: Context, maxSizeBytes: Long): SimpleCache {
        val existing = cache
        if (existing != null) {
            refCount++
            if (maxSizeBytes != configuredMaxSizeBytes) {
                Log.w(
                    TAG,
                    "Adaptive cache already created with maxCacheSizeBytes=" +
                        "$configuredMaxSizeBytes; ignoring differing request for " +
                        "$maxSizeBytes bytes. Media3 allows only one SimpleCache " +
                        "per process/directory, so the first caller's size wins " +
                        "for the lifetime of this process."
                )
            }
            return existing
        }

        val cacheDir = File(context.applicationContext.cacheDir, CACHE_DIR_NAME)
        val evictor = LeastRecentlyUsedCacheEvictor(maxSizeBytes)
        val databaseProvider = StandaloneDatabaseProvider(context.applicationContext)
        val created = SimpleCache(cacheDir, evictor, databaseProvider)

        cache = created
        configuredMaxSizeBytes = maxSizeBytes
        refCount = 1
        Log.d(
            TAG,
            "Created shared adaptive-stream SimpleCache at $cacheDir " +
                "(maxSizeBytes=$maxSizeBytes)"
        )
        return created
    }

    /**
     * Releases one reference previously obtained via [acquire]. Once the
     * reference count reaches zero, the [SimpleCache] is released
     * (`SimpleCache.release()`) and a subsequent [acquire] call creates a
     * fresh instance.
     */
    @Synchronized
    fun release() {
        if (refCount <= 0) return
        refCount--
        if (refCount == 0) {
            try {
                cache?.release()
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing shared adaptive-stream SimpleCache: ${e.message}", e)
            }
            cache = null
            configuredMaxSizeBytes = 0L
        }
    }
}

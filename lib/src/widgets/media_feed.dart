import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/exceptions.dart';
import '../core/media_config.dart';
import '../core/media_controller.dart';
import '../core/media_player_pool.dart';
import '../models/media_item.dart';
import '../models/network_status.dart';
import '../models/player_state.dart';
import 'media_player_widget.dart';

/// Looks up the [MediaItem] descriptor to show at [index]. Called on every
/// build, so it should be cheap (typically indexing into a list the host
/// already holds) — mirrors [IndexedWidgetBuilder]'s own contract.
typedef MediaFeedItemLookup = MediaItem Function(int index);

/// Optional per-item [MediaConfig] override, consulted whenever [MediaFeed]
/// asks its pool to acquire (or reassign) a slot for [item] at [index]. `null`
/// keeps whatever config that slot's controller was created with.
typedef MediaFeedConfigLookup = MediaConfig? Function(
    int index, MediaItem item);

/// Optional per-item pool key override. Defaults to [MediaItem.id] — see
/// [MediaFeed.keyAt] for when a feed needs to disambiguate the same item id
/// appearing at more than one simultaneously-active index.
typedef MediaFeedKeyLookup = String Function(int index, MediaItem item);

/// Decides whether [MediaFeed] should autoplay an item once it becomes the
/// active/visible one, given the device's current [NetworkStatus] — Stage
/// 7d / F-06. Set via [MediaFeedConfig.autoPlayPolicy]; `null` (the default)
/// means "autoplay regardless of network", i.e. no behaviour change from
/// every release before Stage 7d. Return `false` to hold the item loaded
/// (or prewarmed, if [MediaFeedConfig.prewarmWindow] already prepared it)
/// without starting playback — the host's [MediaFeedItemState.play] callback
/// remains available so the user can start it manually. See
/// [conservativeAutoPlayPolicy] for a ready-made policy that refuses on a
/// metered connection or poor/offline/unknown quality.
typedef MediaFeedAutoPlayPolicy = bool Function(NetworkStatus status);

/// A ready-made [MediaFeedAutoPlayPolicy]: refuses autoplay when
/// [NetworkStatus.isMetered] is `true`, or when [NetworkStatus.quality] is
/// [NetworkQuality.poor], [NetworkQuality.offline] or
/// [NetworkQuality.unknown] (treating "we don't know yet" as "don't spend
/// the user's data automatically"); allows it for [NetworkQuality.fair],
/// [NetworkQuality.good] and [NetworkQuality.excellent] on an unmetered
/// connection.
///
/// This is opt-in — pass it as [MediaFeedConfig.autoPlayPolicy] explicitly.
/// [MediaFeedConfig.autoPlayPolicy] itself defaults to `null` ("autoplay
/// regardless"), so supplying this function is what changes behaviour, not
/// upgrading the package.
bool conservativeAutoPlayPolicy(NetworkStatus status) {
  if (status.isMetered) return false;
  switch (status.quality) {
    case NetworkQuality.poor:
    case NetworkQuality.offline:
    case NetworkQuality.unknown:
      return false;
    case NetworkQuality.fair:
    case NetworkQuality.good:
    case NetworkQuality.excellent:
      return true;
  }
}

/// Builds the widget for one feed item from its current [MediaFeedItemState].
/// Called on every rebuild the item's underlying playback state or pool
/// membership changes; keep it cheap.
typedef MediaFeedItemBuilder = Widget Function(
  BuildContext context,
  MediaFeedItemState state,
);

/// Read-only snapshot of one [MediaFeed] item, handed to
/// [MediaFeed.itemBuilder] instead of a raw controller.
///
/// [MediaFeed] owns every controller it creates (see the class doc comment
/// on why that ownership model is the point of this widget); hosts get this
/// state object plus a handful of action callbacks instead of the
/// controller itself, so lifetime — dispose, source-swap-on-reassignment,
/// pool eviction — stays entirely inside the package.
@immutable
class MediaFeedItemState {
  /// Index of this item within the feed.
  final int index;

  /// The media descriptor this index currently shows.
  final MediaItem item;

  /// Whether this index currently holds a live pool slot (a controller,
  /// hence a native decoder session). When `false`, [videoSurface] is a
  /// placeholder and every action callback is `null` — there is nothing to
  /// act on yet (the item has not become active) or not anymore (its slot
  /// was reassigned elsewhere by the pool).
  final bool isActive;

  /// Whether this index is currently visible per the feed's configured
  /// [MediaFeedConfig.visibilityThreshold]. Independent of [isActive]: an
  /// item can be visible while still awaiting its pool slot (the async
  /// [MediaPlayerPool.acquire] has not resolved yet), or inactive-but-still
  /// visible for a single frame right after its slot was reassigned away.
  final bool isVisible;

  /// Current playback state. When [isActive] is `false` this is always the
  /// idle default — there is no controller to report real state.
  final PlaybackState playback;

  /// Pre-built widget for this item's video surface: a real
  /// [MediaPlayerWidget] bound to the pool-assigned controller when
  /// [isActive], otherwise a placeholder. Place this wherever the item's
  /// layout wants the video to render — [MediaFeed] never places it for
  /// you, so custom overlays (title, like button, progress bar, ...) can be
  /// composed around it freely.
  final Widget videoSurface;

  /// Starts/resumes playback. `null` when [isActive] is `false`.
  final VoidCallback? play;

  /// Pauses playback. `null` when [isActive] is `false`.
  final VoidCallback? pause;

  /// Toggles play/pause. `null` when [isActive] is `false`.
  final VoidCallback? togglePlayPause;

  /// Toggles mute. `null` when [isActive] is `false`.
  final VoidCallback? toggleMute;

  /// Seeks to a position. `null` when [isActive] is `false`.
  final ValueChanged<Duration>? seekTo;

  /// Stage 7d / F-06: `true` when this item became active and would
  /// otherwise have autoplayed, but [MediaFeedConfig.autoPlayPolicy]
  /// refused given the device's network status at the time — the slot is
  /// still loaded (see [isActive]) and [play] is still available for the
  /// user to start it manually. Always `false` when
  /// [MediaFeedConfig.autoPlayPolicy] is `null` (the default) or when
  /// [isActive] is `false`. Convenience for hosts that want to surface a
  /// "paused for your data" affordance instead of a silent non-autoplay.
  final bool autoPlayBlockedByPolicy;

  const MediaFeedItemState({
    required this.index,
    required this.item,
    required this.isActive,
    required this.isVisible,
    required this.playback,
    required this.videoSurface,
    this.play,
    this.pause,
    this.togglePlayPause,
    this.toggleMute,
    this.seekTo,
    this.autoPlayBlockedByPolicy = false,
  });

  /// Whether this index holds a live pool slot but is *not* currently
  /// visible — i.e. it was prepared ahead of need by
  /// [MediaFeedConfig.prewarmWindow] (`load()`, never `play()`) rather than
  /// because the user is actually looking at it. Convenience for hosts that
  /// want to render prewarmed neighbours differently from the active item
  /// (e.g. a subtle "ready" badge) — see [MediaFeedConfig.prewarmWindow]
  /// for the full design.
  bool get isPrewarmed => isActive && !isVisible;

  /// Convenience accessors mirroring [MediaController]'s own getters, so an
  /// item builder rarely needs to reach into [playback] directly.
  bool get isPlaying => playback.state == PlayerState.playing;
  bool get isBuffering => playback.isBuffering;
  bool get hasError => playback.state == PlayerState.error;
  String? get errorMessage => playback.errorMessage;
  Duration get position => playback.position;
  Duration get duration => playback.duration;
  bool get isMuted => playback.isMuted;
}

/// Configuration for [MediaFeed]'s visibility-driven activation policy.
///
/// This is deliberately a smaller surface than
/// [MediaListPlayerConfig]: [MediaFeed] does not expose a
/// `maxConcurrentPlayers` cap of its own because [MediaPlayerPool.maxSize]
/// already bounds concurrent decoder-holding controllers by construction —
/// there is no separate "live but uncapped" set of controllers for a second
/// cap to police (see `MediaListPlayer`'s own cap, which exists precisely
/// because it has no pool to rely on).
class MediaFeedConfig {
  /// Minimum visible fraction (0.0-1.0) before an item is considered
  /// visible enough to acquire a pool slot / lose it.
  final double visibilityThreshold;

  /// Whether becoming visible should start playback (after
  /// [autoPlayDelay], and only if the item is still visible then).
  final bool autoPlay;

  /// Whether becoming invisible should stop playback. For a VOD item this
  /// pauses: the item's pool slot itself is not released on invisibility —
  /// see [MediaPlayerPool.acquire] — only actually reassigned once another
  /// item needs the capacity, so scrolling back resumes instantly.
  ///
  /// For a **live** item ([MediaItem.isLive]) this instead **releases** the
  /// pool slot outright (Stage 7d / F-04) rather than pausing it. On-device
  /// measurement found a paused, off-screen live stream still pulls ~13% of
  /// its playing bandwidth and never actually stops — pausing throttles a
  /// live session, it does not end it. Releasing tears the native player
  /// down; scrolling back re-acquires a slot and calls [MediaController.load]
  /// again, which is a full rejoin because a live stream is always joined at
  /// the live edge on load — no `seekToLive` call is needed or exists.
  /// Rejoining a released live item therefore costs a fresh `load()`
  /// (Measurement 3's cold-start numbers apply, uncushioned by prewarm,
  /// since a released item is not pinned) rather than an instant resume, in
  /// exchange for not leaking bandwidth for however long the item stays
  /// off-screen. VOD is unaffected and keeps the original pause-and-retain
  /// behaviour.
  final bool autoPause;

  /// Whether to mute an item while it is below [visibilityThreshold] (and
  /// restore its previous mute state once visible again).
  final bool muteWhenNotVisible;

  /// Whether starting playback on one item pauses every other
  /// currently-playing item this [MediaFeed] holds a slot for — the usual
  /// "only one item plays at a time" feed policy. Scoped to this widget's
  /// own pool only.
  final bool pauseOthersOnPlay;

  /// Small delay between an item crossing the visibility threshold and
  /// autoPlay actually starting, so a fast scroll-past does not start (and
  /// immediately have to stop) playback for items the user never actually
  /// stopped on. Mirrors [MediaListPlayerConfig]'s own smoothing delay.
  final Duration autoPlayDelay;

  /// Number of neighbouring items, on each side, to prepare ahead of need
  /// the moment an index becomes the visible/active item: acquire a pool
  /// slot and call [MediaController.load] for it — never
  /// [MediaController.play] — so scrolling one step in either direction
  /// resumes an already-loaded, already-buffered player instead of paying a
  /// cold `load()`. This is Stage 7c / F-03; on-device measurement found it
  /// collapses time-to-first-frame by 100-700x on Android and 3-5x on iOS,
  /// and removes a ~2s worst-case HLS cold-start tail on both platforms —
  /// see [MediaPlayerPool]'s doc comment and the Phase 7 architecture plan
  /// for the numbers.
  ///
  /// Default `1` prepares exactly one item ahead and one item behind,
  /// symmetrically: [MediaFeed] does not track scroll direction (that is
  /// later, separate work), so it cannot yet prefer one side over the
  /// other. `0` disables prewarming entirely and restores exactly the
  /// pre-Stage-7c behaviour, where a neighbouring item only acquires a pool
  /// slot once it crosses [visibilityThreshold] itself.
  ///
  /// ### Interaction with the pool's `maxSize`
  ///
  /// A prewarm window of `w` wants up to `1 + 2*w` live slots at once
  /// (current, plus `w` on each side) to prewarm every neighbour in the
  /// window without any contention. The default window (`1`) wants exactly
  /// 3 — which is [MediaPlayerPool.defaultMaxSize]. The two defaults were
  /// chosen together and need no adjustment out of the box.
  ///
  /// Raising [prewarmWindow] above `1` without also raising
  /// [MediaFeed.maxPoolSize] (or the `maxSize` of a pool supplied via
  /// [MediaFeed.pool]) is not an error — the pool degrades gracefully
  /// rather than misbehaving. The currently-visible item's slot is always
  /// protected (see [MediaPlayerPool.pin], which [MediaFeed] uses
  /// internally for exactly this) so it is never evicted to make room for
  /// a neighbour being prewarmed. Any prewarm request that cannot be
  /// satisfied without evicting a pinned slot is skipped (logged, not
  /// thrown), and that neighbour simply falls back to loading on demand
  /// when it becomes visible — no worse than prewarming being off for that
  /// one neighbour. Callers who want every neighbour in a wider window
  /// genuinely prewarmed should size their pool to `1 + 2 * prewarmWindow`
  /// or more; the measured Android decoder ceiling of 15
  /// (concurrently-*rendering* players, on one mid-range device) is an
  /// upper bound this should stay well under, not a target to reach for.
  final int prewarmWindow;

  /// Stage 7d / F-05: how long an item must stay continuously visible
  /// (past [visibilityThreshold]) before [MediaFeed] actually acquires a
  /// pool slot for it (and, transitively, prewarms its neighbours). Reset
  /// on every visibility crossing, so an item the user merely flings past
  /// — visible for less than this duration — never triggers a pool
  /// [MediaPlayerPool.acquire] at all.
  ///
  /// This exists because the debouncing that made a fast fling through 50
  /// items instantiate only ~5 players (rather than 50) was previously
  /// accidental: it came entirely from the `visibility_detector` package's
  /// own global `VisibilityDetectorController.instance.updateInterval`
  /// (default 500ms), which [MediaFeed] never set, read, or even referenced
  /// — any part of the host app (or a future version of that dependency)
  /// changing that *global, process-wide* value would silently change
  /// [MediaFeed]'s behaviour with it. [MediaFeed] deliberately does not
  /// mutate that global itself, either — doing so from inside a widget
  /// would reach out and change every other [VisibilityDetector] in the
  /// host app, including ones [MediaFeed] has no business touching. This
  /// field is a feed-local timer instead: owned, documented, testable
  /// independently of whatever the global happens to be set to (including
  /// `Duration.zero`, which this package's own tests set the global to for
  /// deterministic visibility delivery).
  ///
  /// Defaults to `500ms`, matching `visibility_detector`'s own default —
  /// chosen so a host that has never touched the global sees essentially
  /// the same fling behaviour as before, now for an owned reason instead of
  /// an accidental one. Pass [Duration.zero] to acquire a slot immediately
  /// on every visibility crossing (the pre-Stage-7d behaviour, and still
  /// exactly what happens if a host's own global `updateInterval` is what
  /// they want to rely on instead). Only *activation* (the [acquire] call
  /// this triggers, and the prewarm/play that follow it) is debounced —
  /// visibility bookkeeping ([muteWhenNotVisible], and the fraction used to
  /// re-check visibility after [autoPlayDelay]) is never deferred.
  ///
  /// Not asserted non-negative in the constructor below: [Duration]'s
  /// comparison operators are not const-evaluable, and this constructor
  /// must stay `const` (every existing caller in the package constructs
  /// `const MediaFeedConfig(...)`). A negative value is harmless in
  /// practice regardless — every read site compares with `<= Duration.zero`
  /// (see `_handleVisibility`), so a negative duration is simply treated
  /// the same as [Duration.zero]: immediate activation, no debounce.
  final Duration activationDebounce;

  /// Stage 7d / F-06: consulted immediately before autoplay would start for
  /// an item that just became active, given the device's current
  /// [NetworkStatus] at that moment. Return `false` to hold the item loaded
  /// without starting playback — see [MediaFeedAutoPlayPolicy].
  ///
  /// Defaults to `null`, meaning **no network policy is applied and
  /// [autoPlay] behaves exactly as it always has** — autoplay is not
  /// conditioned on network status unless a host opts in by supplying a
  /// policy (see [conservativeAutoPlayPolicy] for a ready-made one).
  /// Deliberately not "refuse on metered by default": every release before
  /// Stage 7d autoplayed regardless of connection, and changing that
  /// silently out from under existing hosts — some of whom may already
  /// handle metered connections themselves, or intentionally autoplay
  /// regardless — would be a behavioural regression disguised as a bug fix.
  /// Hosts that want the safer behaviour opt in explicitly.
  final MediaFeedAutoPlayPolicy? autoPlayPolicy;

  const MediaFeedConfig({
    this.visibilityThreshold = 0.6,
    this.autoPlay = true,
    this.autoPause = true,
    this.muteWhenNotVisible = false,
    this.pauseOthersOnPlay = true,
    this.autoPlayDelay = const Duration(milliseconds: 300),
    this.prewarmWindow = 1,
    this.activationDebounce = const Duration(milliseconds: 500),
    this.autoPlayPolicy,
  }) : assert(
          prewarmWindow >= 0,
          'MediaFeedConfig.prewarmWindow must not be negative',
        );
}

/// A scrolling media feed that owns a small, package-managed
/// [MediaPlayerPool] internally rather than taking a host-owned
/// [MediaController] per item.
///
/// ### Why this exists, alongside [MediaListPlayer]
///
/// [MediaListPlayer] wraps one host-supplied [MediaController]: the host
/// creates and disposes it, and the widget only plays/pauses it based on
/// visibility. That shape is right for "a list with some video items in
/// it", but it structurally cannot bound concurrent decoder sessions to a
/// small number, because it never owns the controllers — a `ListView` with
/// visibility-driven pausing keeps every item's controller (and therefore
/// its decoder session) alive for as long as the app holds it, however many
/// items have ever been scrolled past.
///
/// [MediaFeed] is the inverse: it owns [itemCount] media *descriptors*, not
/// controllers, and internally maintains a bounded [MediaPlayerPool] that
/// it reassigns across items as they scroll into and out of view. The host
/// supplies [itemAt] (which [MediaItem] belongs at an index) and
/// [itemBuilder] (how to render one item from a read-only
/// [MediaFeedItemState]); [MediaFeed] decides when an index acquires or
/// loses a pool slot, and disposes every remaining controller when it is
/// itself removed from the tree.
///
/// Nothing about [MediaListPlayer] changes — it remains the right choice
/// for a single host-owned controller inside a scrollable. [MediaFeed] is
/// additive, for the case where the package should own the whole feed's
/// controller lifetime.
///
/// ### What counts as "the same item" across scroll positions
///
/// Pool slots are keyed by [keyAt] (defaulting to [MediaItem.id]). If the
/// same item id can legitimately appear at two simultaneously-active
/// indices, supply an explicit [keyAt] that disambiguates them — two
/// indices sharing one pool key share one underlying native player, and
/// only the most-recently-created video surface for it will actually show
/// video (see `FullscreenMediaPlayer`'s single-native-view contract, which
/// this inherits unchanged).
///
/// ### Prewarming neighbouring items (Stage 7c / F-03)
///
/// When [MediaFeedConfig.prewarmWindow] is non-zero (default `1`), the
/// moment an index becomes the visible/active item [MediaFeed] also
/// requests a pool slot for up to that many items on each side of it —
/// `load()`, never `play()` — through the exact same [MediaPlayerPool]
/// path the active item itself uses, so every load-time guarantee (B-11
/// input validation, the fail-closed DRM setup, B-12 `secureSurface`)
/// applies unmodified. See [MediaFeedConfig.prewarmWindow] for the full
/// design, including how it interacts with the pool's `maxSize`. The
/// currently-visible item's own slot is pinned (see [MediaPlayerPool.pin])
/// for exactly as long as it remains visible, so a prewarm request for a
/// neighbour can never evict it to make room for itself.
class MediaFeed extends StatefulWidget {
  /// Number of items in the feed.
  final int itemCount;

  /// Media descriptor lookup — see [MediaFeedItemLookup].
  final MediaFeedItemLookup itemAt;

  /// Per-item widget builder — see [MediaFeedItemBuilder].
  final MediaFeedItemBuilder itemBuilder;

  /// Visibility/autoplay policy. See [MediaFeedConfig].
  final MediaFeedConfig config;

  /// Hard cap on concurrently live (decoder-holding) controllers, passed to
  /// the internally-created [MediaPlayerPool]. Ignored if [pool] is
  /// supplied directly. See [MediaPlayerPool.defaultMaxSize] for the
  /// reasoning behind the default, and [MediaFeedConfig.prewarmWindow] for
  /// how this interacts with a non-default prewarm window.
  final int maxPoolSize;

  /// Optional pre-built pool, for advanced use (sharing a pool across more
  /// than one [MediaFeed], or injecting a pool built with a fake controller
  /// factory in tests). When supplied, [MediaFeed] does not dispose it —
  /// the caller retains ownership.
  final MediaPlayerPool? pool;

  /// Optional per-item pool key override — see [MediaFeedKeyLookup] and the
  /// class doc comment's note on disambiguating repeated item ids.
  final MediaFeedKeyLookup? keyAt;

  /// Optional per-item [MediaConfig] override — see [MediaFeedConfigLookup].
  final MediaFeedConfigLookup? mediaConfigAt;

  /// Aspect ratio applied to every item's allocated space.
  final double aspectRatio;

  /// Scroll axis, forwarded to the internal [ListView.builder].
  final Axis scrollDirection;

  /// Scroll controller, forwarded to the internal [ListView.builder].
  final ScrollController? scrollController;

  /// Padding, forwarded to the internal [ListView.builder].
  final EdgeInsetsGeometry? padding;

  /// Placeholder shown in place of [MediaFeedItemState.videoSurface] for an
  /// index that does not currently hold a pool slot.
  final Widget? placeholder;

  const MediaFeed({
    super.key,
    required this.itemCount,
    required this.itemAt,
    required this.itemBuilder,
    this.config = const MediaFeedConfig(),
    this.maxPoolSize = MediaPlayerPool.defaultMaxSize,
    this.pool,
    this.keyAt,
    this.mediaConfigAt,
    this.aspectRatio = 16 / 9,
    this.scrollDirection = Axis.vertical,
    this.scrollController,
    this.padding,
    this.placeholder,
  });

  @override
  State<MediaFeed> createState() => _MediaFeedState();
}

class _MediaFeedState extends State<MediaFeed> {
  late final MediaPlayerPool _pool;
  late final bool _ownsPool;

  /// Most recently observed visible fraction per index, used to detect a
  /// threshold crossing (see [_handleVisibility]) and to re-check
  /// visibility after [MediaFeedConfig.autoPlayDelay] elapses.
  final Map<int, double> _visibleFraction = <int, double>{};

  /// Stage 7d / F-05: pending feed-local activation-debounce timers, keyed
  /// by index. An index only has an entry while it is visible but has not
  /// yet stayed visible for [MediaFeedConfig.activationDebounce] — see
  /// [_handleVisibility] and [MediaFeedConfig.activationDebounce]'s own doc
  /// comment for why this is a feed-local timer rather than the shared
  /// `visibility_detector` global.
  final Map<int, Timer> _activationTimers = <int, Timer>{};

  /// Stage 7d / F-06: indices whose most recent autoplay attempt was
  /// refused by [MediaFeedConfig.autoPlayPolicy] — mirrored to
  /// [MediaFeedItemState.autoPlayBlockedByPolicy]. Cleared whenever the
  /// index deactivates, so a stale "blocked" badge never survives a
  /// scroll-away-and-back.
  final Set<int> _autoPlayBlockedByPolicy = <int>{};

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _ownsPool = widget.pool == null;
    _pool = widget.pool ?? MediaPlayerPool(maxSize: widget.maxPoolSize);
    _pool.addListener(_onPoolChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _activationTimers.values) {
      timer.cancel();
    }
    _activationTimers.clear();
    _pool.removeListener(_onPoolChanged);
    if (_ownsPool) {
      _pool.dispose();
    }
    super.dispose();
  }

  void _onPoolChanged() {
    if (mounted && !_disposed) setState(() {});
  }

  String _keyFor(int index, MediaItem item) =>
      widget.keyAt?.call(index, item) ?? item.id;

  void _handleVisibility(int index, VisibilityInfo info) {
    if (_disposed) return;
    final threshold = widget.config.visibilityThreshold;
    final wasVisible = (_visibleFraction[index] ?? 0.0) >= threshold;
    final isVisible = info.visibleFraction >= threshold;
    _visibleFraction[index] = info.visibleFraction;

    if (widget.config.muteWhenNotVisible) {
      final item = widget.itemAt(index);
      final controller = _pool.controllerFor(_keyFor(index, item));
      if (controller != null && !controller.isDisposed) {
        if (!isVisible && !controller.isMuted) {
          _fireAndForget(
            'mute of index $index (scrolled out of view)',
            controller.toggleMute,
          );
        } else if (isVisible && controller.isMuted) {
          _fireAndForget(
            'unmute of index $index (scrolled into view)',
            controller.toggleMute,
          );
        }
      }
    }

    if (isVisible == wasVisible) return;

    // Stage 7d / F-05: whichever direction this crossing just went, any
    // activation timer scheduled from an *earlier* crossing is stale and
    // must never fire using state from before this one — see
    // MediaFeedConfig.activationDebounce.
    _activationTimers.remove(index)?.cancel();

    if (isVisible) {
      final debounce = widget.config.activationDebounce;
      if (debounce <= Duration.zero) {
        _beginActivation(index);
      } else {
        _activationTimers[index] = Timer(debounce, () {
          _activationTimers.remove(index);
          if (_disposed) return;
          final fraction = _visibleFraction[index] ?? 0.0;
          if (fraction < widget.config.visibilityThreshold) {
            // Scrolled away again before the debounce settled -- exactly
            // the fast-fling case F-05 exists to protect: an item merely
            // flown past never reaches a pool acquire() at all.
            return;
          }
          _beginActivation(index);
        });
      }
    } else {
      _deactivate(index);
    }
  }

  /// Pins [index]'s key (if prewarming is on), kicks off its own
  /// [_activate], and requests prewarm slots for its neighbours — the work
  /// that used to run directly inside [_handleVisibility]'s `isVisible`
  /// branch before Stage 7d's activation debounce (see
  /// [MediaFeedConfig.activationDebounce]) interposed a settle delay ahead
  /// of it. Called either synchronously (debounce == [Duration.zero]) or
  /// from the fired [_activationTimers] entry -- both call sites run
  /// synchronously up to [_activate]'s first `await`, preserving the pin
  /// race-closing guarantee described below.
  void _beginActivation(int index) {
    if (widget.config.prewarmWindow > 0) {
      // Pinned synchronously, BEFORE either this item's own acquire or any
      // prewarm acquire below is even enqueued on the pool's mutex (both
      // `acquire` calls only reach their first `await` after enqueueing —
      // see MediaPlayerPool._runExclusive). Pinning here closes a race
      // where a concurrently-requested prewarm neighbour could otherwise be
      // processed by the pool before this item's own acquire finishes
      // registering its slot, i.e. before `_activate` itself would get a
      // chance to pin it.
      final item = widget.itemAt(index);
      _pool.pin(_keyFor(index, item));
    }
    unawaited(_activate(index));
    if (widget.config.prewarmWindow > 0) {
      unawaited(_prewarmAround(index));
    }
  }

  Future<void> _activate(int index) async {
    final item = widget.itemAt(index);
    final key = _keyFor(index, item);
    final config = widget.mediaConfigAt?.call(index, item);

    final MediaController controller;
    try {
      controller = await _pool.acquire(key, item, config: config);
    } catch (e) {
      if (widget.config.prewarmWindow > 0) {
        // The slot never came to exist under this key, so nothing should
        // continue protecting it — undoes the pin set in
        // `_beginActivation` before this call.
        _pool.unpin(key);
      }
      debugPrint(
        'MediaFeed: failed to acquire a pool slot for index $index '
        '(key=$key): $e',
      );
      return;
    }
    if (_disposed || !mounted) return;

    if (widget.config.autoPlay) {
      if (widget.config.autoPlayDelay > Duration.zero) {
        await Future.delayed(widget.config.autoPlayDelay);
        if (_disposed || !mounted) return;
        final fraction = _visibleFraction[index] ?? 0.0;
        if (fraction < widget.config.visibilityThreshold) {
          // Scrolled away again before the delay elapsed; do not start
          // playback for an item the user is no longer looking at.
          return;
        }
      }
      if (!controller.isDisposed) {
        // Stage 7d / F-06: give the host's network policy the final say,
        // immediately before starting playback. `null` (the default)
        // preserves the exact pre-Stage-7d behaviour of autoplaying
        // unconditionally — see MediaFeedConfig.autoPlayPolicy.
        final policy = widget.config.autoPlayPolicy;
        final networkAllows =
            policy == null || policy(controller.player.networkStatus);
        if (networkAllows) {
          if (_autoPlayBlockedByPolicy.remove(index) && mounted) {
            setState(() {});
          }
          _fireAndForget(
            'autoplay of index $index (key=$key)',
            controller.play,
          );
        } else {
          debugPrint(
            'MediaFeed: autoplay held for index $index (key=$key) — '
            'refused by autoPlayPolicy given the current network status; '
            'the item stays loaded and playable via a manual play() call',
          );
          if (_autoPlayBlockedByPolicy.add(index) && mounted) {
            setState(() {});
          }
        }
      }
    }

    if (widget.config.pauseOthersOnPlay) {
      _pauseOthers(key);
    }
  }

  void _deactivate(int index) {
    final item = widget.itemAt(index);
    final key = _keyFor(index, item);

    // Always attempted, even if prewarming is off for the *current* build —
    // a cheap no-op if `key` was never pinned. This is the only place a pin
    // left over from an earlier build (e.g. `prewarmWindow` dropped to `0`
    // at runtime after this item was pinned while active) gets cleaned up,
    // so it cannot linger and make a key permanently non-evictable.
    _pool.unpin(key);

    if (_autoPlayBlockedByPolicy.remove(index) && mounted) {
      setState(() {});
    }

    final controller = _pool.controllerFor(key);
    if (controller == null ||
        controller.isDisposed ||
        !widget.config.autoPause) {
      return;
    }

    if (item.isLive) {
      // Stage 7d / F-04: a paused, off-screen live stream still measured
      // ~13% of its playing bandwidth and never actually stopped, so
      // pausing (VOD's behaviour, below) is not enough for live -- release
      // the slot entirely. This tears the native player down; scrolling
      // back re-acquires a fresh slot and calls MediaController.load()
      // again, which rejoins at the live edge (no seekToLive call exists or
      // is needed -- a freshly loaded live stream always joins at the live
      // edge). The pin above is already dropped before this branch runs, so
      // release never fights the pin/eviction guarantees Stage 7c relies
      // on.
      _fireAndForget(
        'release of index $index (key=$key)',
        () => _pool.release(key),
      );
      return;
    }

    if (controller.isPlaying) {
      _fireAndForget('pause of index $index (key=$key)', controller.pause);
    }
  }

  /// Requests a pool slot (`load()`, never `play()`) for up to
  /// [MediaFeedConfig.prewarmWindow] items on each side of [index] — see
  /// [MediaFeedConfig.prewarmWindow] for the full design. Symmetric because
  /// [MediaFeed] does not track scroll direction.
  Future<void> _prewarmAround(int index) async {
    final window = widget.config.prewarmWindow;
    if (window <= 0) return;
    for (var offset = 1; offset <= window; offset++) {
      final ahead = index + offset;
      final behind = index - offset;
      if (ahead < widget.itemCount) {
        unawaited(_prewarmIndex(ahead));
      }
      if (behind >= 0) {
        unawaited(_prewarmIndex(behind));
      }
    }
  }

  /// Prepares [index] without starting its playback: acquires a pool slot
  /// through the exact same [MediaPlayerPool.acquire] path [_activate] uses
  /// — which calls [MediaController.load], never `.play()` — so every
  /// load-time guarantee (B-11 input validation, the fail-closed DRM setup,
  /// B-12 `secureSurface`) applies exactly as it would for the active item.
  ///
  /// Never throws: a prewarm that cannot be satisfied (rejected input, pool
  /// capacity exhausted by pinned slots, disposal mid-flight) is logged and
  /// skipped — that neighbour simply falls back to loading on demand once
  /// it actually becomes visible, no worse than prewarming being off for
  /// it.
  Future<void> _prewarmIndex(int index) async {
    if (_disposed) return;
    final item = widget.itemAt(index);
    final key = _keyFor(index, item);

    // Belt-and-suspenders alongside "never call controller.play() below":
    // force the config this prewarm load uses to autoPlay: false regardless
    // of what the host's own per-item MediaConfig requests, in case native
    // ever auto-starts playback from an `initialize`/`load` pair with
    // `autoPlay: true` on a freshly-created slot. `null` is left as `null`
    // (rather than synthesizing a MediaConfig()) so a same-item re-acquire
    // still keeps whatever config the slot already has — see
    // MediaPlayerPool.acquire's doc comment on what `config: null` means.
    var config = widget.mediaConfigAt?.call(index, item);
    if (config != null && config.autoPlay) {
      config = config.copyWith(autoPlay: false);
    }

    try {
      await _pool.acquire(key, item, config: config);
    } catch (e) {
      debugPrint(
        'MediaFeed: prewarm skipped for index $index (key=$key): $e',
      );
    }
  }

  /// Starts a fire-and-forget async [operation] and makes sure its failure is
  /// handled *here* rather than escaping as an unhandled async error.
  ///
  /// [MediaFeed] drives controllers from UI and activation paths that must not
  /// block, so these calls are deliberately never awaited. A bare
  /// `controller.pause()` therefore discards a `Future` that can still fail,
  /// and the failure surfaces in the ambient `Zone`'s uncaught-error handler
  /// with no indication of which item or which operation produced it — which
  /// is exactly what this wrapper exists to prevent.
  ///
  /// Failures are always swallowed (one item must never be able to stop the
  /// feed, or the rest of a [_pauseOthers] loop), but not silently:
  ///
  /// * [PlayerDisposedException] is swallowed **quietly**. The controller was
  ///   torn down between the moment this feed selected it and the moment the
  ///   operation ran — an expected race while scrolling, and one the operation
  ///   is moot in anyway. `MediaController` itself already returns without
  ///   error when it is disposed before the call starts, so this only covers
  ///   the narrower window where the underlying `MediaPlayer` goes away
  ///   mid-flight.
  /// * Anything else — a genuine native failure — is reported with
  ///   [debugPrint], matching how [_activate] and [_prewarmIndex] already
  ///   report theirs.
  ///
  /// [description] should name the operation *and* the item it belongs to;
  /// the whole point is that the log line identifies the culprit.
  void _fireAndForget(String description, Future<void> Function() operation) {
    unawaited(() async {
      try {
        await operation();
      } on PlayerDisposedException {
        // Expected teardown race — see the doc comment above.
      } catch (e) {
        debugPrint('MediaFeed: $description failed: $e');
      }
    }());
  }

  /// Pauses every active controller except [activeKey].
  ///
  /// The `!other.isDisposed && other.isPlaying` test below is a check-then-act
  /// that can still lose the race (the controller may be disposed, or may have
  /// stopped on its own, before the queued `pause()` runs). That is fine: the
  /// resulting failure is absorbed per-controller by [_fireAndForget], so one
  /// controller failing to pause never prevents the others from being paused.
  void _pauseOthers(String activeKey) {
    for (final otherKey in _pool.activeKeys) {
      if (otherKey == activeKey) continue;
      final other = _pool.controllerFor(otherKey);
      if (other != null && !other.isDisposed && other.isPlaying) {
        _fireAndForget(
          'pause of key=$otherKey (superseded by key=$activeKey)',
          other.pause,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: widget.scrollDirection,
      controller: widget.scrollController,
      padding: widget.padding,
      itemCount: widget.itemCount,
      itemBuilder: _buildItem,
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = widget.itemAt(index);
    final key = _keyFor(index, item);
    final controller = _pool.controllerFor(key);
    final isVisible =
        (_visibleFraction[index] ?? 0.0) >= widget.config.visibilityThreshold;

    final Widget content;
    if (controller != null && !controller.isDisposed) {
      content = ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = _buildActiveState(index, item, controller, isVisible);
          return widget.itemBuilder(context, state);
        },
      );
    } else {
      final state = MediaFeedItemState(
        index: index,
        item: item,
        isActive: false,
        isVisible: isVisible,
        playback: const PlaybackState(state: PlayerState.idle),
        videoSurface: widget.placeholder ?? const SizedBox.shrink(),
      );
      content = widget.itemBuilder(context, state);
    }

    return VisibilityDetector(
      key: ValueKey('media_feed_item_$key'),
      onVisibilityChanged: (info) => _handleVisibility(index, info),
      child: AspectRatio(aspectRatio: widget.aspectRatio, child: content),
    );
  }

  MediaFeedItemState _buildActiveState(
    int index,
    MediaItem item,
    MediaController controller,
    bool isVisible,
  ) {
    return MediaFeedItemState(
      index: index,
      item: item,
      isActive: true,
      isVisible: isVisible,
      playback: controller.state,
      videoSurface: MediaPlayerWidget(
        controller: controller,
        showControls: false,
        wantKeepAlive: false,
      ),
      // These are `VoidCallback`/`ValueChanged`, so the `Future` each
      // controller call returns is discarded by the callback signature
      // itself — route them through [_fireAndForget] so a host tapping
      // play/pause cannot produce an unhandled async error.
      play: () => _fireAndForget('play of index $index', controller.play),
      pause: () => _fireAndForget('pause of index $index', controller.pause),
      togglePlayPause: () => _fireAndForget(
        'togglePlayPause of index $index',
        controller.togglePlayPause,
      ),
      toggleMute: () => _fireAndForget(
        'toggleMute of index $index',
        controller.toggleMute,
      ),
      seekTo: (position) => _fireAndForget(
        'seek of index $index',
        () => controller.seekTo(position),
      ),
      // Derived rather than the raw set membership so a manual play() via
      // the callback above (or any other path that starts playback) clears
      // the "blocked" badge immediately on the very next state broadcast,
      // without this widget needing to eagerly mutate its own bookkeeping
      // in response to a call it does not own.
      autoPlayBlockedByPolicy:
          _autoPlayBlockedByPolicy.contains(index) && !controller.isPlaying,
    );
  }
}

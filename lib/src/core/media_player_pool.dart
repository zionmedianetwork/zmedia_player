import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import 'media_config.dart';
import 'media_controller.dart';

/// Factory signature used by [MediaPlayerPool] to construct the
/// [MediaController] backing a pool slot. Overridable (see
/// [MediaPlayerPool.new]) so tests can inject a controller built against a
/// fake/mocked platform channel without changing the pool's own logic.
typedef MediaControllerFactory = MediaController Function({
  required String playerId,
  MediaConfig? config,
});

/// A single pool slot: one retained [MediaController] (and therefore one
/// native decoder session), currently assigned to at most one caller-defined
/// key. See [MediaPlayerPool] for why the controller instance itself is
/// never disposed and recreated on ordinary reassignment.
class _PoolSlot {
  final MediaController controller;
  String key;
  String itemId;

  _PoolSlot({
    required this.controller,
    required this.key,
    required this.itemId,
  });
}

/// A small, fixed-capacity pool of retained [MediaController]s that the
/// package itself owns and reassigns across media items, rather than each
/// item getting its own host-owned controller for as long as it has ever
/// been visible.
///
/// ### Why this exists
///
/// Two related defects motivate this class (see `MediaListPlayer` for the
/// widget-level version of the same problem this fixes):
///
///  - **A paused player is not a released player.** Pausing a player leaves
///    its native decoder session intact — on Android and iOS alike, a
///    prepared-but-paused player and a playing player both hold a hardware
///    decoder client. A feed that only *pauses* off-screen items therefore
///    accumulates one held decoder per item ever scrolled past, not per item
///    currently on screen, and hardware decoders are a small, process-wide,
///    finite resource. Exceeding that ceiling does not throw a visible
///    error — the extra players silently render black frames while
///    reporting a decoder-init failure only on the error stream.
///  - **The package could not previously own pooling by API shape.**
///    Widgets built around a host-supplied `MediaController` (see
///    `MediaListPlayer`) cannot pool: the controller's lifetime belongs to
///    whoever constructed it, not to the widget rendering it. Pooling
///    requires the inverse — the package creates and owns a small, bounded
///    set of controllers and decides which media each one currently shows.
///
/// This pool fixes both: capacity is hard-bounded at [maxSize], and once
/// that capacity is exhausted, [acquire] reassigns ("evicts") the
/// least-recently-used slot to the newly requested item instead of ever
/// exceeding the cap or leaving a stale item's decoder pinned. See
/// [acquire]'s doc comment for exactly what "reassign" does and does not do
/// to the underlying player.
///
/// ### Choosing [maxSize]
///
/// On-device measurement on a mid-range Android phone found a **hardware
/// decoder ceiling of 15** simultaneously-rendering players — the 16th
/// silently produced a black frame while the native layer correctly logged
/// a decoder-init failure. That number is a mid-range upper bound, not a
/// floor: a lower-end ("Go" class) Android device should be expected to
/// have a lower ceiling, and it was the binding platform in that same
/// measurement pass (iOS did not hit a ceiling within a much smaller sample
/// size). [defaultMaxSize] is deliberately far below that ceiling — see its
/// own doc comment for the reasoning — and [maxSize] exists precisely so an
/// app that has profiled its own target devices can raise or lower it.
///
/// ### What [acquire] does NOT do (out of scope for this pool)
///
/// This pool only bounds and reassigns concurrent decoder-holding slots. It
/// does not decide *when* an item should become active or prewarmed (that
/// is `MediaFeed`'s job, driven by visibility — see [pin] for the primitive
/// `MediaFeed` uses to protect the active item while it does so), and it
/// does not apply any live-stream-specific stop/release policy. The latter
/// is later, separate work.
class MediaPlayerPool extends ChangeNotifier {
  /// A conservative, single-digit default chosen to sit well below the
  /// measured mid-range Android decoder ceiling (15 concurrently-rendering
  /// players — see the class doc comment), while still being large enough
  /// for the two things a pool needs headroom for on day one:
  ///
  ///  1. **One slot for "current" plus one for "the item the user just
  ///     scrolled away from"** — so scrolling back a single step resumes
  ///     instantly from an already-loaded, already-buffered player instead
  ///     of reloading from scratch (this pool retains and swaps controller
  ///     instances specifically to make that cheap — see [acquire]).
  ///  2. **One spare slot** so acquiring the next item does not have to
  ///     evict the previous one before the new one starts loading, avoiding
  ///     a moment where fewer than 2 items are ready during an ordinary
  ///     single-step scroll.
  ///
  /// That leaves the remaining ~12 of the measured 15-player ceiling as
  /// headroom for a future prewarm window and for any other player this
  /// package's `MediaListPlayer`/`MediaPlayerWidget` may have live
  /// elsewhere in the same app — the decoder ceiling is a process-wide
  /// resource, not scoped to a single `MediaFeed`. Apps that have profiled
  /// their own minimum-supported device should pass an explicit [maxSize]
  /// rather than relying on this default, especially on the low end (a
  /// "Go" class Android device was not available to measure and should be
  /// assumed to have a materially lower ceiling than 15).
  static const int defaultMaxSize = 3;

  /// Hard ceiling on how many [MediaController]s (and therefore native
  /// decoder sessions) this pool holds at once. Must be at least 1.
  final int maxSize;

  final MediaControllerFactory? _controllerFactory;
  final String Function()? _playerIdFactory;

  static int _autoIdCounter = 0;

  final Map<String, _PoolSlot> _slotsByKey = <String, _PoolSlot>{};

  /// Least-recently-used order of live keys, oldest first. The head is the
  /// next unpinned slot [acquire] will reassign once the pool is at
  /// capacity — see [pin].
  final List<String> _lru = <String>[];

  /// Keys currently protected from LRU eviction — see [pin].
  final Set<String> _pinnedKeys = <String>{};

  /// Serializes [acquire]/[release]/[releaseAll] against each other so two
  /// calls racing (e.g. two feed items crossing the visibility threshold in
  /// the same frame) can never both decide to evict the same slot or
  /// otherwise interleave into an inconsistent pool state.
  Future<void> _mutex = Future<void>.value();

  bool _disposed = false;

  /// Creates a pool with a hard capacity of [maxSize] live controllers.
  ///
  /// [controllerFactory] and [playerIdFactory] are test/advanced-usage
  /// seams: by default the pool constructs controllers via
  /// [MediaController.create] with an internally-generated, collision-free
  /// player id. Supply [controllerFactory] to inject a controller built
  /// against a fake platform channel in tests, or [playerIdFactory] to
  /// control the id scheme (e.g. for log correlation) without changing how
  /// controllers are constructed.
  MediaPlayerPool({
    this.maxSize = defaultMaxSize,
    MediaControllerFactory? controllerFactory,
    String Function()? playerIdFactory,
  })  : assert(maxSize > 0, 'MediaPlayerPool.maxSize must be at least 1'),
        _controllerFactory = controllerFactory,
        _playerIdFactory = playerIdFactory;

  /// Number of live (controller-holding) slots right now. Never exceeds
  /// [maxSize].
  int get liveCount => _slotsByKey.length;

  /// Remaining capacity before the next [acquire] for a new key must evict.
  int get freeCapacity => maxSize - liveCount;

  /// Snapshot of every key currently holding a live slot.
  List<String> get activeKeys => List.unmodifiable(_slotsByKey.keys);

  /// Whether [key] currently holds a live slot.
  bool isActive(String key) => _slotsByKey.containsKey(key);

  /// The controller currently assigned to [key], or `null` if [key] holds
  /// no live slot (never acquired, or since evicted/released).
  MediaController? controllerFor(String key) => _slotsByKey[key]?.controller;

  /// Whether this pool has been disposed. A disposed pool holds no
  /// controllers and rejects further [acquire] calls.
  bool get isDisposed => _disposed;

  /// Marks [key] as most-recently-used without touching its controller or
  /// media. No-op if [key] does not currently hold a slot. Exposed for
  /// callers that want to protect a slot from imminent eviction (e.g. "the
  /// user just interacted with this item") without forcing a reload.
  void touch(String key) {
    if (_slotsByKey.containsKey(key)) {
      _touchLru(key);
    }
  }

  /// Marks [key] as protected from the LRU eviction [acquire] performs once
  /// the pool is at capacity, without affecting LRU order and without
  /// requiring [key] to currently hold a live slot — pinning takes effect
  /// immediately once a slot for [key] exists, and is otherwise inert.
  ///
  /// Exists for [MediaFeed]'s prewarm window (Stage 7c / F-03): the item the
  /// user is actually looking at must never be sacrificed to make room for
  /// a neighbour being prepared ahead of need — that would trade a visible
  /// stall for an invisible optimisation, which is strictly worse than not
  /// prewarming at all. `MediaFeed` pins the currently-visible item's key
  /// for exactly as long as it is visible and [unpin]s it the moment it
  /// stops being so, so a prewarm [acquire] for a neighbour can never
  /// select a pinned key as its eviction victim — see [acquire]'s "at
  /// capacity" branch.
  ///
  /// Pinning is *not* extra capacity — a pool whose every live slot is
  /// pinned simply cannot [acquire] a new key at all (see [acquire], which
  /// throws a [StateError] in that case rather than evicting a pinned
  /// slot). Callers that pin should keep the pinned set well below
  /// [maxSize], or expect [acquire] for anything else to fail while it does
  /// not.
  void pin(String key) {
    _pinnedKeys.add(key);
  }

  /// Reverses [pin]: [key] becomes an ordinary eviction candidate again, as
  /// if it had never been pinned. Safe to call for a key that was never
  /// pinned, or that holds no live slot (both are no-ops).
  void unpin(String key) {
    _pinnedKeys.remove(key);
  }

  /// Whether [key] is currently pinned — see [pin].
  bool isPinned(String key) => _pinnedKeys.contains(key);

  /// Returns a [MediaController] that is loaded with [item] and assigned to
  /// [key], creating or reassigning a pool slot as needed:
  ///
  ///  - If [key] already holds a live slot, that slot's controller is
  ///    returned as-is (no native calls) when it is already showing
  ///    [item] — re-acquiring the same key/item pair (e.g. a visibility
  ///    flicker) is free. If it is showing a *different* item, the
  ///    existing controller's source is swapped via [MediaController.load]
  ///    (and [MediaController.updateConfig] first, if [config] is given).
  ///  - Else, if the pool has free capacity (< [maxSize] live slots), a new
  ///    controller is created, initialized and loaded with [item].
  ///  - Else, the least-recently-used slot is **reassigned**: its
  ///    controller instance is retained (never disposed here) and its
  ///    media source is swapped to [item] via [MediaController.load]. This
  ///    is the fix this pool exists to provide — the old key's mapping is
  ///    removed immediately (its decoder session is returned to the pool
  ///    for the new key to use), never merely paused-and-forgotten the way
  ///    a plain visibility cap does. Retaining the instance and swapping
  ///    the source (rather than disposing and constructing a fresh
  ///    controller) avoids the native player re-initialization cost that a
  ///    dispose/recreate cycle would pay on every eviction.
  ///
  /// In every branch, loading goes through the ordinary
  /// [MediaController.load] path, so every existing load-time guarantee
  /// still applies unmodified: input validation (including the
  /// HTTPS-for-DRM rule) and the native fail-closed DRM setup both run
  /// exactly as they do for any other caller of `load()` — this pool adds
  /// no alternate, unvalidated path to native code.
  ///
  /// [config] is applied (via [MediaController.updateConfig], which also
  /// reconciles `secureSurface`) whenever a slot's source is actually
  /// swapped or a new slot is created; a same-item re-acquire does not
  /// reapply it, to avoid a redundant native round trip on every visibility
  /// flicker of an already-current item.
  Future<MediaController> acquire(
    String key,
    MediaItem item, {
    MediaConfig? config,
  }) {
    return _runExclusive(() => _acquireLocked(key, item, config));
  }

  Future<MediaController> _acquireLocked(
    String key,
    MediaItem item,
    MediaConfig? config,
  ) async {
    _throwIfDisposed();

    final existing = _slotsByKey[key];
    if (existing != null) {
      _touchLru(key);
      if (existing.itemId != item.id) {
        if (config != null) {
          await existing.controller.updateConfig(config);
        }
        await existing.controller.load(item);
        existing.itemId = item.id;
      }
      _throwIfDisposed();
      _notify();
      return existing.controller;
    }

    if (_slotsByKey.length < maxSize) {
      return _createFreshSlot(key, item, config);
    }

    // At capacity: reassign the least-recently-used UNPINNED slot — pinned
    // keys (see [pin]) are never chosen as an eviction victim, however long
    // they have sat unused. If every live slot is pinned there is no victim
    // to pick, so acquiring a new key is refused outright rather than
    // evicting a slot [pin] promised would not be evicted.
    final victimIndex = _lru.indexWhere((k) => !_pinnedKeys.contains(k));
    if (victimIndex == -1) {
      throw StateError(
        'MediaPlayerPool: cannot acquire a slot for "$key" — all $maxSize '
        'live slot(s) are pinned (see MediaPlayerPool.pin). Increase '
        'maxSize, or unpin a key, before requesting more concurrent slots '
        'than the pool can hold unpinned.',
      );
    }
    // The old key's mapping is dropped BEFORE the swap completes so a
    // concurrent acquire for the old key (racing in through the mutex
    // queue) sees it as absent and creates/evicts fresh, rather than
    // observing a slot that is simultaneously mid-reassignment to someone
    // else.
    final victimKey = _lru.removeAt(victimIndex);
    final victim = _slotsByKey.remove(victimKey);
    // Should be unreachable (every key in `_lru` has a matching slot), but
    // fall back to the ordinary create path rather than throwing if the two
    // ever disagree.
    if (victim == null) {
      return _createFreshSlot(key, item, config);
    }

    try {
      if (config != null) {
        await victim.controller.updateConfig(config);
      }
      await victim.controller.load(item);
    } catch (_) {
      // The victim was already removed from bookkeeping above, so nobody
      // else will ever release it if it is left dangling here — a partially
      // failed swap must dispose it rather than leak an untracked live
      // decoder holder. Capacity is regained: the next acquire for a new
      // key sees `_slotsByKey.length < maxSize` again and creates fresh.
      victim.controller.dispose();
      rethrow;
    }
    if (_disposed) {
      victim.controller.dispose();
      _throwIfDisposed();
    }
    victim.key = key;
    victim.itemId = item.id;
    _slotsByKey[key] = victim;
    _lru.add(key);
    _notify();
    return victim.controller;
  }

  /// Creates a brand-new controller, initializes and loads it with [item],
  /// and registers it under [key]. On any failure the just-created
  /// controller is disposed before the error propagates — it was never
  /// registered in [_slotsByKey], so nothing else would ever clean it up.
  Future<MediaController> _createFreshSlot(
    String key,
    MediaItem item,
    MediaConfig? config,
  ) async {
    final controller = _createController(config);
    try {
      await controller.initialize();
      await controller.load(item);
    } catch (_) {
      controller.dispose();
      rethrow;
    }
    if (_disposed) {
      controller.dispose();
      _throwIfDisposed();
    }
    _slotsByKey[key] = _PoolSlot(
      controller: controller,
      key: key,
      itemId: item.id,
    );
    _lru.add(key);
    _notify();
    return controller;
  }

  /// Fully releases the slot held by [key], if any: the underlying
  /// controller is disposed (returning its native decoder session, unlike
  /// pausing it — see the class doc comment) and [key] no longer maps to
  /// any controller. No-op if [key] holds no live slot.
  ///
  /// Use this when the pool no longer needs to hold *any* slot for [key] at
  /// all (e.g. the whole feed shrank its desired concurrency), as opposed
  /// to simply letting [acquire]'s LRU reassignment reclaim the slot
  /// on-demand for another key.
  Future<void> release(String key) {
    return _runExclusive(() async {
      final slot = _slotsByKey.remove(key);
      if (slot == null) return;
      _lru.remove(key);
      _pinnedKeys.remove(key);
      slot.controller.dispose();
      _notify();
    });
  }

  /// Releases every live slot (see [release]). Leaves the pool at zero live
  /// controllers but still usable — unlike [dispose], further [acquire]
  /// calls are still accepted afterwards.
  Future<void> releaseAll() {
    return _runExclusive(() async {
      for (final slot in _slotsByKey.values) {
        slot.controller.dispose();
      }
      _slotsByKey.clear();
      _lru.clear();
      _pinnedKeys.clear();
      _notify();
    });
  }

  MediaController _createController(MediaConfig? config) {
    final playerId = (_playerIdFactory ?? _defaultPlayerId)();
    final factory = _controllerFactory ?? _defaultControllerFactory;
    return factory(playerId: playerId, config: config);
  }

  static MediaController _defaultControllerFactory({
    required String playerId,
    MediaConfig? config,
  }) {
    return MediaController.create(playerId: playerId, config: config);
  }

  static String _defaultPlayerId() =>
      'media_feed_pool_${DateTime.now().millisecondsSinceEpoch}_${_autoIdCounter++}';

  void _touchLru(String key) {
    _lru.remove(key);
    _lru.add(key);
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('MediaPlayerPool has been disposed');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Runs [action] with exclusive access to the pool's mutable state,
  /// queued strictly after any already-pending [_runExclusive] call. The
  /// queue slot is always released (even if [action] throws), so a failed
  /// operation can never permanently wedge later calls.
  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final previous = _mutex;
    final completer = Completer<void>();
    _mutex = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// Disposes every live controller (releasing its native decoder session)
  /// and marks this pool unusable. Safe to call multiple times.
  ///
  /// Deliberately synchronous, like [MediaController.dispose] /
  /// [ChangeNotifier.dispose] — matches Flutter's `State.dispose()`
  /// contract, where a widget's dispose cannot itself be asynchronous. Any
  /// [acquire] concurrently in flight will observe [isDisposed] once its
  /// current native call completes and abort rather than returning a
  /// controller from a now-disposed pool.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final slot in _slotsByKey.values) {
      slot.controller.dispose();
    }
    _slotsByKey.clear();
    _lru.clear();
    _pinnedKeys.clear();
    super.dispose();
  }
}

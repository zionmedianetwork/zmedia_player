import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/media_config.dart';
import '../core/media_controller.dart';
import '../core/media_player_pool.dart';
import '../models/media_item.dart';
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
  });

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

  /// Whether becoming invisible should pause playback. The item's pool slot
  /// itself is not released on invisibility — see [MediaPlayerPool.acquire]
  /// — only actually reassigned once another item needs the capacity.
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

  const MediaFeedConfig({
    this.visibilityThreshold = 0.6,
    this.autoPlay = true,
    this.autoPause = true,
    this.muteWhenNotVisible = false,
    this.pauseOthersOnPlay = true,
    this.autoPlayDelay = const Duration(milliseconds: 300),
  });
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
  /// reasoning behind the default.
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
          controller.toggleMute();
        } else if (isVisible && controller.isMuted) {
          controller.toggleMute();
        }
      }
    }

    if (isVisible == wasVisible) return;
    if (isVisible) {
      unawaited(_activate(index));
    } else {
      _deactivate(index);
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
      unawaited(controller.play());
    }

    if (widget.config.pauseOthersOnPlay) {
      _pauseOthers(key);
    }
  }

  void _deactivate(int index) {
    final item = widget.itemAt(index);
    final key = _keyFor(index, item);
    final controller = _pool.controllerFor(key);
    if (controller != null &&
        !controller.isDisposed &&
        widget.config.autoPause &&
        controller.isPlaying) {
      controller.pause();
    }
  }

  void _pauseOthers(String activeKey) {
    for (final otherKey in _pool.activeKeys) {
      if (otherKey == activeKey) continue;
      final other = _pool.controllerFor(otherKey);
      if (other != null && !other.isDisposed && other.isPlaying) {
        other.pause();
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
      play: () => controller.play(),
      pause: () => controller.pause(),
      togglePlayPause: () => controller.togglePlayPause(),
      toggleMute: () => controller.toggleMute(),
      seekTo: (position) => controller.seekTo(position),
    );
  }
}

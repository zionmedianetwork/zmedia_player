import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../data/sample_media.dart';

/// Manual regression harness for [MediaFeed] — Stage 7b (pool), Stage 7c
/// (prewarm window) and Stage 7d (live release / activation debounce /
/// network-aware autoplay) of Phase 7. Sits alongside `feed_page.dart` (which
/// exercises [MediaListPlayer], the host-owned-controller widget) rather than
/// replacing it: this page proves the opposite ownership model actually
/// works end to end. [MediaFeed] never hands this page a [MediaController] —
/// only [MediaFeedItemState] snapshots and action callbacks — and the
/// [MediaPlayerPool] it scrolls through is bounded to [_maxPoolSize]
/// controllers no matter how many of the [_kItemCount] items have been
/// scrolled past.
///
/// ### Layout — status bar + settings sheet, not a growing header
///
/// Stage 7d's three additions (auto fling, activation-debounce control,
/// autoplay-policy control) were originally stacked as extra rows plus
/// explanatory paragraphs directly in this page's fixed header. On a narrow
/// phone (Note 9P-class, 720x1600 @2.0 -> 360x800 logical) that header grew
/// tall enough to push the entire feed below the fold — no item was ever
/// visible, so [MediaFeed]'s visibility-driven activation never fired and
/// none of Stage 7b-7d's behaviour could be exercised at all. This is the
/// same failure mode `measurement/scroll_bandwidth_page.dart` hit with its
/// `Wrap`-based action header; the fix here follows that file's pattern:
///
/// - The always-visible header is now a compact two-line [_StatusBar] (pool
///   count + Auto fling button, then a network-status line) — a fixed,
///   non-scrolling `Column` sibling above [MediaFeed]'s `Expanded`, same as
///   before, just without the segmented controls or prose that used to live
///   there.
/// - `maxPoolSize`, `prewarmWindow`, `activation debounce` and `autoplay
///   policy` — plus their explanatory text — moved into a
///   [_FeedSettingsSheet] opened via the tune icon in the [AppBar]. A modal
///   bottom sheet is reachable at *any* scroll position (it does not live
///   inside the feed's scrollable) and, unlike a fixed header row, can grow
///   past one screen's worth of content without stealing space from the feed
///   — it scrolls internally instead.
///
/// All four settings remain runtime-adjustable exactly as before; only their
/// location changed.
///
/// ### What to look for while scrolling
///
/// The status bar shows `pool: liveCount / maxSize` live (via an
/// [AnimatedBuilder] on the pool itself, which is a [ChangeNotifier]).
/// Scroll through more items than `maxSize` and that count must never climb
/// past it — unlike the pre-Stage-7b `MediaListPlayer` behaviour (F-01),
/// where every item ever scrolled past kept its own decoder session paused,
/// never released.
///
/// The `maxPoolSize` control (in the settings sheet) lets you change the
/// pool's capacity at runtime; because [MediaPlayerPool.maxSize] is fixed
/// for a pool's lifetime, changing it disposes the old pool (releasing every
/// controller it held) and swaps in a fresh one, remounting [MediaFeed] with
/// a new [Key] so it starts clean.
///
/// The `prewarm window` control changes [MediaFeedConfig.prewarmWindow]
/// live, with no pool rebuild needed (the underlying [MediaConfig]-level
/// guarantee — a prewarmed neighbour is loaded, never played — does not
/// depend on the pool's identity). Each item's badge distinguishes several
/// states: **active** (the visible item, green), **prewarmed** (loaded ahead
/// of need by the window, amber, never playing), **held (network)** (Stage
/// 7d / F-06 — autoplay was refused by the current
/// [MediaFeedConfig.autoPlayPolicy], violet) and **no slot** (not yet
/// loaded, grey).
///
/// ### Stage 7d additions
///
/// - **Live release (F-04).** Every 7th item (matching `_kSampleItems`'
///   length) is [SampleMedia.hlsLiveStream] — badged `LIVE` in red. Scroll
///   one out of view and back: unlike a VOD item (which stays `active` with
///   `playing=false`, merely paused), a live item drops to **no slot**
///   immediately — its pool slot was released outright, not paused — then
///   re-acquires a fresh slot (a genuine rejoin at the live edge) when
///   scrolled back into view. The event log's `RELEASED` lines (derived by
///   diffing `pool.activeKeys` between pool-change notifications) call out
///   every dropped key together with whether it was live, so a release is
///   visible without needing to cross-reference item indices by hand.
/// - **Activation debounce (F-05).** The `activation debounce` control (in
///   the settings sheet) changes [MediaFeedConfig.activationDebounce] at
///   runtime. Set it to 500ms or more and fling quickly through the feed
///   (the `Auto fling` button in the status bar, shared with
///   `scroll_bandwidth_page.dart`'s pattern) — the `pool: liveCount` counter
///   should barely move during the fling itself, only settling once the
///   fling stops, in contrast to `0 (off)`, where every item flown past can
///   briefly acquire a slot.
/// - **Network-aware autoplay (F-06).** The `autoplay policy` control (in
///   the settings sheet) switches [MediaFeedConfig.autoPlayPolicy] between
///   `None` (always autoplay — the default, unchanged from every release
///   before Stage 7d), `Conservative` ([conservativeAutoPlayPolicy] —
///   refuses on a metered connection or poor/offline/unknown quality) and
///   `Always hold` (refuses unconditionally, for a deterministic on-device
///   check that does not depend on actually being on a metered network). The
///   status bar shows the live [NetworkStatus] of the most recently
///   activated item's controller, and any item currently held back by the
///   policy shows the **held (network)** badge and a tappable play button
///   (its [MediaFeedItemState.play] callback stays available even when
///   autoplay was refused).
class MediaFeedPoolPage extends StatefulWidget {
  const MediaFeedPoolPage({super.key});

  @override
  State<MediaFeedPoolPage> createState() => _MediaFeedPoolPageState();
}

/// More items than any of the offered pool sizes, so scrolling genuinely
/// forces eviction/reassignment rather than every item fitting in the pool
/// at once.
const int _kItemCount = 20;

/// Index 0 is a live stream (see [SampleMedia.hlsLiveStream]) so it recurs
/// every [_kSampleItems.length] items across the [_kItemCount] feed --
/// enough to demonstrate F-04's release-on-invisibility without needing a
/// second, purpose-built page.
const List<MediaItem> _kSampleItems = [
  SampleMedia.hlsLiveStream,
  SampleMedia.bigBuckBunny,
  SampleMedia.elephantsDream,
  SampleMedia.forBiggerBlazes,
  SampleMedia.forBiggerEscapes,
  SampleMedia.forBiggerJoyrides,
  SampleMedia.sintel,
  SampleMedia.tearsOfSteel,
];

/// Stage 7d / F-06: which [MediaFeedAutoPlayPolicy] the settings sheet's
/// control currently applies.
enum _AutoPlayPolicyMode { none, conservative, alwaysHold }

class _MediaFeedPoolPageState extends State<MediaFeedPoolPage> {
  late MediaPlayerPool _pool;
  int _maxPoolSize = MediaPlayerPool.defaultMaxSize;

  /// Stage 7c: mirrors [MediaFeedConfig.prewarmWindow]'s own default (1).
  int _prewarmWindow = 1;

  /// Stage 7d / F-05: mirrors [MediaFeedConfig.activationDebounce]'s own
  /// default (500ms).
  int _activationDebounceMs = 500;

  /// Stage 7d / F-06: see [_AutoPlayPolicyMode].
  _AutoPlayPolicyMode _autoPlayPolicyMode = _AutoPlayPolicyMode.none;

  /// Bumped every time [_pool] is replaced, folded into [MediaFeed]'s key so
  /// changing the pool size forces a clean remount instead of MediaFeed
  /// trying to reconcile against a pool it no longer owns.
  int _feedGeneration = 0;

  final List<String> _eventLog = [];
  bool _pageDisposed = false;

  /// Stage 7d / F-04: keys this page has ever seen active, and whether the
  /// item behind that key is live -- diffed on every pool change so a
  /// dropped key can be logged as a release/eviction with its live-ness
  /// called out. Populated from [_itemAt], which every index passes through.
  final Map<String, bool> _keyIsLive = {};
  Set<String> _lastKnownActiveKeys = {};

  final ScrollController _scrollController = ScrollController();
  bool _autoFlinging = false;

  @override
  void initState() {
    super.initState();
    _pool = _createPool(_maxPoolSize);
  }

  @override
  void dispose() {
    _pageDisposed = true;
    _pool.removeListener(_onPoolChanged);
    _pool.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  MediaPlayerPool _createPool(int maxSize) {
    final pool = MediaPlayerPool(maxSize: maxSize);
    pool.addListener(_onPoolChanged);
    return pool;
  }

  void _onPoolChanged() {
    if (!mounted || _pageDisposed) return;
    final currentKeys = _pool.activeKeys.toSet();
    final dropped = _lastKnownActiveKeys.difference(currentKeys);
    for (final key in dropped) {
      final isLive = _keyIsLive[key] ?? false;
      _log(
        'RELEASED key=$key live=$isLive'
        '${isLive ? ' (F-04: torn down, not merely paused)' : ''}',
      );
    }
    _lastKnownActiveKeys = currentKeys;
    setState(() {});
    _log(
      'POOL liveCount=${_pool.liveCount}/${_pool.maxSize} '
      'activeKeys=${_pool.activeKeys}',
    );
  }

  void _log(String message) {
    final line = '[FEED-POOL] $message';
    debugPrint(line);
    if (!mounted || _pageDisposed) return;
    setState(() {
      _eventLog.insert(0, line);
      if (_eventLog.length > 60) _eventLog.removeLast();
    });
  }

  MediaItem _itemAt(int index) {
    final base = _kSampleItems[index % _kSampleItems.length];
    // Unique id per index -- MediaFeed keys pool slots by item.id by
    // default, so reusing one id across simultaneously-active indices would
    // make them share one underlying native player (see MediaFeed's class
    // doc comment on keyAt).
    final item = base.copyWith(id: 'feed_pool_item_$index');
    _keyIsLive[item.id] = item.isLive;
    return item;
  }

  MediaFeedAutoPlayPolicy? get _resolvedAutoPlayPolicy {
    switch (_autoPlayPolicyMode) {
      case _AutoPlayPolicyMode.none:
        return null;
      case _AutoPlayPolicyMode.conservative:
        return conservativeAutoPlayPolicy;
      case _AutoPlayPolicyMode.alwaysHold:
        return (status) => false;
    }
  }

  void _changePoolSize(int value) {
    if (value == _maxPoolSize) return;
    final oldPool = _pool;
    setState(() {
      _maxPoolSize = value;
      _pool = _createPool(value);
      _feedGeneration++;
      _lastKnownActiveKeys = {};
    });
    oldPool.removeListener(_onPoolChanged);
    oldPool.dispose();
    _log('CONFIG maxPoolSize=$value (pool rebuilt, feed remounted)');
  }

  void _changePrewarmWindow(int value) {
    if (value == _prewarmWindow) return;
    setState(() {
      _prewarmWindow = value;
    });
    _log(
      'CONFIG prewarmWindow=$value (wants ${1 + 2 * value} live slots for '
      'zero-contention prewarm; maxPoolSize is $_maxPoolSize)',
    );
  }

  void _changeActivationDebounce(int ms) {
    if (ms == _activationDebounceMs) return;
    setState(() {
      _activationDebounceMs = ms;
    });
    _log(
      'CONFIG activationDebounce=${ms}ms (Stage 7d / F-05 -- feed-local, '
      'independent of visibility_detector\'s own global updateInterval)',
    );
  }

  void _changeAutoPlayPolicyMode(_AutoPlayPolicyMode mode) {
    if (mode == _autoPlayPolicyMode) return;
    setState(() {
      _autoPlayPolicyMode = mode;
    });
    _log('CONFIG autoPlayPolicy=$mode (Stage 7d / F-06)');
  }

  Future<void> _toggleAutoFling() async {
    if (_autoFlinging) {
      setState(() => _autoFlinging = false);
      return;
    }
    setState(() => _autoFlinging = true);
    _log('FLING start -- exercises F-05\'s activation debounce end to end');
    while (_autoFlinging && mounted && !_pageDisposed) {
      if (!_scrollController.hasClients) break;
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 900),
        curve: Curves.linear,
      );
      if (!_autoFlinging || !mounted || _pageDisposed) break;
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.linear,
      );
    }
    if (mounted && !_pageDisposed) {
      setState(() => _autoFlinging = false);
    }
    _log('FLING stop');
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _FeedSettingsSheet(
        maxPoolSize: _maxPoolSize,
        onMaxPoolSizeChanged: _changePoolSize,
        prewarmWindow: _prewarmWindow,
        onPrewarmWindowChanged: _changePrewarmWindow,
        activationDebounceMs: _activationDebounceMs,
        onActivationDebounceChanged: _changeActivationDebounce,
        autoPlayPolicyMode: _autoPlayPolicyMode,
        onAutoPlayPolicyModeChanged: _changeAutoPlayPolicyMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed (MediaFeed pool + prewarm + live/debounce/'
            'network, 7b-7d)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Feed settings (pool size, prewarm, debounce, '
                'autoplay policy)',
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusBar(
              pool: _pool,
              autoFlinging: _autoFlinging,
              onToggleAutoFling: _toggleAutoFling,
              activeNetworkController: _pool.activeKeys.isNotEmpty
                  ? _pool.controllerFor(_pool.activeKeys.last)
                  : null,
            ),
            Expanded(
              child: MediaFeed(
                key: ValueKey('media-feed-gen-$_feedGeneration'),
                itemCount: _kItemCount,
                itemAt: _itemAt,
                pool: _pool,
                scrollController: _scrollController,
                config: MediaFeedConfig(
                  autoPlay: true,
                  autoPause: true,
                  pauseOthersOnPlay: true,
                  prewarmWindow: _prewarmWindow,
                  activationDebounce:
                      Duration(milliseconds: _activationDebounceMs),
                  autoPlayPolicy: _resolvedAutoPlayPolicy,
                ),
                itemBuilder: _buildItem,
              ),
            ),
            _EventLogPanel(eventLog: _eventLog),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, MediaFeedItemState state) {
    final theme = Theme.of(context);
    final statusText = state.autoPlayBlockedByPolicy
        ? 'held (network)'
        : (state.isPrewarmed
            ? 'prewarmed'
            : (state.isActive ? 'active' : 'no slot'));
    final statusColor = state.autoPlayBlockedByPolicy
        ? Colors.deepPurple.shade400
        : (state.isPrewarmed
            ? Colors.amber.shade700
            : (state.isActive ? Colors.green : Colors.black54));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black, child: state.videoSurface),
            Positioned(
              top: 8,
              left: 8,
              child: Row(
                children: [
                  _Badge(text: '#${state.index}'),
                  if (state.item.isLive) ...[
                    const SizedBox(width: 6),
                    const _Badge(text: 'LIVE', color: Colors.redAccent),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _Badge(text: statusText, color: statusColor),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${state.item.title}\n'
                        'active=${state.isActive} '
                        'prewarmed=${state.isPrewarmed} '
                        'playing=${state.isPlaying} '
                        'buffering=${state.isBuffering} '
                        'heldByPolicy=${state.autoPlayBlockedByPolicy}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    if (state.togglePlayPause != null)
                      IconButton(
                        icon: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: state.togglePlayPause,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, this.color = Colors.black54});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Fixed, non-scrolling header sibling above [MediaFeed]'s `Expanded` --
/// deliberately just two short lines (pool count + Auto fling, then network
/// status) so it never competes with the feed for viewport height. Every
/// runtime-adjustable setting lives in [_FeedSettingsSheet] instead -- see
/// [MediaFeedPoolPage]'s class doc comment for why.
class _StatusBar extends StatelessWidget {
  final MediaPlayerPool pool;
  final bool autoFlinging;
  final VoidCallback onToggleAutoFling;
  final MediaController? activeNetworkController;

  const _StatusBar({
    required this.pool,
    required this.autoFlinging,
    required this.onToggleAutoFling,
    required this.activeNetworkController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: pool,
                  builder: (context, _) {
                    return Text(
                      'pool: ${pool.liveCount} / ${pool.maxSize} live slots',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onToggleAutoFling,
                icon: Icon(autoFlinging ? Icons.stop : Icons.fast_forward),
                label: Text(autoFlinging ? 'Stop fling' : 'Auto fling'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          _NetworkStatusLine(controller: activeNetworkController),
        ],
      ),
    );
  }
}

/// Stage 7d / F-06: live [NetworkStatus] readout for whichever controller
/// this page currently considers "most recently active" (see
/// `_MediaFeedPoolPageState.build`'s `activeNetworkController` argument) --
/// context for the autoplay-policy control in [_FeedSettingsSheet].
///
/// `connectionType == none` (never `quality`/`isMetered` alone) is the
/// reliable "genuinely offline" signal on both platforms — see
/// `NetworkStatus.connectionType`'s dartdoc. It is emitted only by each
/// native `NetworkMonitor`'s canonical no-connection map, never for a
/// connected-but-unrecognized transport (that used to be a live bug on iOS;
/// see `NetworkMonitor.swift`'s `estimateBandwidth(from:)`, now fixed).
class _NetworkStatusLine extends StatelessWidget {
  final MediaController? controller;

  const _NetworkStatusLine({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = this.controller;
    if (controller == null || controller.isDisposed) {
      return Text(
        'network: (no active item yet)',
        style: theme.textTheme.labelSmall,
      );
    }
    return StreamBuilder<NetworkStatus>(
      stream: controller.player.networkStatusStream,
      initialData: controller.player.networkStatus,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null) {
          return Text('network: (unknown)', style: theme.textTheme.labelSmall);
        }
        return Text(
          'network: ${status.connectionType.name} / ${status.quality.name}'
          '${status.isMetered ? ' / metered' : ''}',
          style: theme.textTheme.labelSmall,
        );
      },
    );
  }
}

/// Modal bottom sheet holding every Stage 7b-7d runtime-adjustable setting
/// (`maxPoolSize`, `prewarmWindow`, `activationDebounce`, `autoPlayPolicy`)
/// plus their explanatory text. Opened from the [AppBar]'s tune icon, so it
/// is reachable at any scroll position without permanently occupying any of
/// the feed's viewport -- see [MediaFeedPoolPage]'s class doc comment.
///
/// Keeps a local copy of each value (initialized from the page's current
/// state when opened) so its `SegmentedButton`s reflect a change immediately
/// -- this sheet is a separate route/overlay from the page, so it does not
/// automatically rebuild when the page's own `setState` runs. Every change
/// is still forwarded to the page via the `on*Changed` callbacks, which
/// remain the single source of truth (rebuilding the pool, reconfiguring
/// [MediaFeed], etc.); this widget's local state exists purely so the
/// sheet's own UI stays in sync with itself while open.
class _FeedSettingsSheet extends StatefulWidget {
  final int maxPoolSize;
  final ValueChanged<int> onMaxPoolSizeChanged;
  final int prewarmWindow;
  final ValueChanged<int> onPrewarmWindowChanged;
  final int activationDebounceMs;
  final ValueChanged<int> onActivationDebounceChanged;
  final _AutoPlayPolicyMode autoPlayPolicyMode;
  final ValueChanged<_AutoPlayPolicyMode> onAutoPlayPolicyModeChanged;

  const _FeedSettingsSheet({
    required this.maxPoolSize,
    required this.onMaxPoolSizeChanged,
    required this.prewarmWindow,
    required this.onPrewarmWindowChanged,
    required this.activationDebounceMs,
    required this.onActivationDebounceChanged,
    required this.autoPlayPolicyMode,
    required this.onAutoPlayPolicyModeChanged,
  });

  @override
  State<_FeedSettingsSheet> createState() => _FeedSettingsSheetState();
}

class _FeedSettingsSheetState extends State<_FeedSettingsSheet> {
  late int _maxPoolSize = widget.maxPoolSize;
  late int _prewarmWindow = widget.prewarmWindow;
  late int _activationDebounceMs = widget.activationDebounceMs;
  late _AutoPlayPolicyMode _autoPlayPolicyMode = widget.autoPlayPolicyMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Feed settings',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                '$_kItemCount items (every ${_kSampleItems.length}th is '
                'LIVE), package-owned MediaPlayerPool -- no MediaController '
                'is ever handed to the page.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text('maxPoolSize', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 5, label: Text('5')),
                ],
                selected: {_maxPoolSize},
                onSelectionChanged: (selected) {
                  final value = selected.first;
                  setState(() => _maxPoolSize = value);
                  widget.onMaxPoolSizeChanged(value);
                },
              ),
              const SizedBox(height: 16),
              Text('prewarm window (±)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('0 (off)')),
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                ],
                selected: {_prewarmWindow},
                onSelectionChanged: (selected) {
                  final value = selected.first;
                  setState(() => _prewarmWindow = value);
                  widget.onPrewarmWindowChanged(value);
                },
              ),
              const SizedBox(height: 4),
              Text(
                'window $_prewarmWindow wants ${1 + 2 * _prewarmWindow} live '
                'slots (current + $_prewarmWindow ahead + $_prewarmWindow '
                'behind); maxPoolSize is $_maxPoolSize'
                '${_maxPoolSize < 1 + 2 * _prewarmWindow ? ' -- undersized: '
                    'some prewarm requests will be skipped, active item is '
                    'still protected' : ''}.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _maxPoolSize < 1 + 2 * _prewarmWindow
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('activation debounce (F-05)',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('0 (off)')),
                  ButtonSegment(value: 250, label: Text('250ms')),
                  ButtonSegment(value: 500, label: Text('500ms')),
                  ButtonSegment(value: 1000, label: Text('1000ms')),
                ],
                selected: {_activationDebounceMs},
                onSelectionChanged: (selected) {
                  final value = selected.first;
                  setState(() => _activationDebounceMs = value);
                  widget.onActivationDebounceChanged(value);
                },
              ),
              const SizedBox(height: 4),
              Text(
                'higher = a fling settles longer before acquiring a slot; '
                'close this sheet, use "Auto fling" and watch pool: '
                'liveCount stay flat during the fling itself.',
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 16),
              Text('autoplay policy (F-06)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SegmentedButton<_AutoPlayPolicyMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _AutoPlayPolicyMode.none,
                    label: Text('None'),
                  ),
                  ButtonSegment(
                    value: _AutoPlayPolicyMode.conservative,
                    label: Text('Conservative'),
                  ),
                  ButtonSegment(
                    value: _AutoPlayPolicyMode.alwaysHold,
                    label: Text('Always hold'),
                  ),
                ],
                selected: {_autoPlayPolicyMode},
                onSelectionChanged: (selected) {
                  final value = selected.first;
                  setState(() => _autoPlayPolicyMode = value);
                  widget.onAutoPlayPolicyModeChanged(value);
                },
              ),
              const SizedBox(height: 4),
              Text(
                'None = always autoplay (default). Conservative = refuse on '
                'metered/poor network. Always hold = refuse '
                'unconditionally -- items show "held (network)" and stay '
                'manually playable via their play button.',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventLogPanel extends StatelessWidget {
  final List<String> eventLog;

  const _EventLogPanel({required this.eventLog});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: 160,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event log (mirrors console [FEED-POOL] lines, newest first)',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: eventLog.isEmpty
                ? const Text('No events yet.')
                : ListView.builder(
                    itemCount: eventLog.length,
                    itemBuilder: (context, i) => Text(
                      eventLog[i],
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

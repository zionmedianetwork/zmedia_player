import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../../data/sample_media.dart';
import '../../widgets/measurement_log_panel.dart';

/// Stage 7a measurement #4 — bandwidth across a fast scroll through 50
/// items.
///
/// Directly tests the plan's stated risk: naive prefetching can make
/// network usage *worse*, and that has to be measured before Stage 7c
/// ships any cross-item prefetch. This page ships no prefetch of its own —
/// it is today's [MediaListPlayer] baseline, exactly as a host app would
/// use it now, so the operator has a "before" number to compare a future
/// prefetch design against.
///
/// ### Lifecycle model — deliberately NOT a pool
/// Each item is its own [StatefulWidget] ([_ScrollFeedItem]) that creates
/// its [MediaController] in `initState` and disposes it in `dispose`. That
/// is it — no custom windowing/pooling logic lives in this page. Standard
/// `ListView.builder` element recycling (items scrolled far enough outside
/// the viewport's cache extent are removed from the tree, and Flutter
/// calls `dispose()` on their State) is what bounds how many native player
/// instances stay alive at once. This is precisely how a host app is
/// forced to build a feed today, given F-02 (`MediaListPlayer` requires a
/// host-owned controller) — not a workaround invented for this harness.
/// Within whatever window stays mounted, [MediaListPlayer]'s own
/// `maxConcurrentPlayers` cap and off-screen-pause behavior (Phase 4)
/// apply exactly as they do in `feed_page.dart`.
///
/// ### In-app vs external
/// Item creation/disposal/play/pause events are logged with a `[SCROLL-BW]`
/// prefix for detail. The `[7A-MEASURE] start:scroll-bandwidth-50 ...` /
/// `end:scroll-bandwidth-50 ...` markers bracket only the fling itself, so
/// the operator's external bandwidth reading (Android Studio's Network
/// Profiler, or `adb shell cat /proc/net/dev` sampled before/after; iOS:
/// Instruments' Network template) lines up with the scroll, not with the
/// page's initial settle.
class ScrollBandwidthPage extends StatefulWidget {
  const ScrollBandwidthPage({super.key});

  @override
  State<ScrollBandwidthPage> createState() => _ScrollBandwidthPageState();
}

const int _kItemCount = 50;

const List<MediaItem> _kFixtures = [
  SampleMedia.bigBuckBunny,
  SampleMedia.elephantsDream,
  SampleMedia.forBiggerBlazes,
  SampleMedia.forBiggerEscapes,
  SampleMedia.forBiggerJoyrides,
  SampleMedia.sintel,
  SampleMedia.tearsOfSteel,
];

const Duration _autoFlingDuration = Duration(milliseconds: 2500);

class _ScrollBandwidthPageState extends State<ScrollBandwidthPage>
    with MeasurementLoggerMixin {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _createdIndices = {};
  final Set<int> _playingIndices = {};

  int _maxConcurrentPlayers = 2;
  bool _pauseOthersOnPlay = true;
  bool _flinging = false;

  @override
  void dispose() {
    loggerDisposed = true;
    _scrollController.dispose();
    super.dispose();
  }

  void _onItemCreated(int index) => _createdIndices.add(index);

  void _onItemDisposed(int index) {
    _createdIndices.remove(index);
    _playingIndices.remove(index);
  }

  void _onItemPlayingChanged(int index, bool playing) {
    if (playing) {
      _playingIndices.add(index);
    } else {
      _playingIndices.remove(index);
    }
    // Aggregate counters change often during a fast fling — rebuild is
    // cheap (just the header row) so no throttling here.
    if (mounted && !loggerDisposed) setState(() {});
  }

  Future<void> _autoFling({required bool toBottom}) async {
    if (_flinging || !_scrollController.hasClients) return;
    setState(() => _flinging = true);
    final target = toBottom
        ? _scrollController.position.maxScrollExtent
        : _scrollController.position.minScrollExtent;
    logMarker('start', 'scroll-bandwidth-50', {
      'mode': 'auto',
      'direction': toBottom ? 'down' : 'up',
      'items': _kItemCount,
      'durationMs': _autoFlingDuration.inMilliseconds,
    });
    try {
      await _scrollController.animateTo(
        target,
        duration: _autoFlingDuration,
        curve: Curves.easeInOut,
      );
    } finally {
      logMarker('end', 'scroll-bandwidth-50', {
        'mode': 'auto',
        'itemsCreated': _createdIndices.length,
        'itemsPlaying': _playingIndices.length,
      });
      safeSetState(() => _flinging = false);
    }
  }

  void _markManualStart() {
    logMarker('start', 'scroll-bandwidth-50', {
      'mode': 'manual',
      'items': _kItemCount,
    });
  }

  void _markManualEnd() {
    logMarker('end', 'scroll-bandwidth-50', {
      'mode': 'manual',
      'itemsCreated': _createdIndices.length,
      'itemsPlaying': _playingIndices.length,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = MediaListPlayerConfig(
      maxConcurrentPlayers: _maxConcurrentPlayers,
      pauseOthersOnPlay: _pauseOthersOnPlay,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('4. Scroll Bandwidth (50 items)')),
      // The "Auto fling"/"Mark start"/"Mark end" buttons are the primary
      // (repeatable, scriptable) way this measurement is taken — hand
      // swiping is only the fallback. They live in `bottomNavigationBar`,
      // a dedicated Scaffold slot the body's Column can never squeeze or
      // push off-screen, rather than as a Column sibling above the list:
      // a `Wrap`-based header with this many long-labeled buttons on a
      // narrow phone (~360dp logical width) wraps to one button per row
      // and previously ballooned to 400+dp tall — over half the screen —
      // starving the list below it down to a sliver and, on real devices
      // with system-bar insets, pushing the last button(s) past the
      // bottom edge entirely. Pinning them here makes them reachable at
      // *any* scroll position, matching the harness's own documentation.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.south),
                  label: const Text('Auto fling ↓'),
                  onPressed:
                      _flinging ? null : () => _autoFling(toBottom: true),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.north),
                  label: const Text('Auto fling ↑'),
                  onPressed:
                      _flinging ? null : () => _autoFling(toBottom: false),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Mark start'),
                  onPressed: _flinging ? null : _markManualStart,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flag),
                  label: const Text('Mark end'),
                  onPressed: _flinging ? null : _markManualEnd,
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                  Text(
                    'Mounted controllers: ${_createdIndices.length}   '
                    'Playing: ${_playingIndices.length}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  // A horizontally-scrolling single row rather than `Wrap`:
                  // this keeps the header a fixed, compact ~1-line height
                  // regardless of screen width or system font scale, instead
                  // of silently growing taller (and stealing height from the
                  // list below) whenever these controls don't fit on one
                  // line. See the `bottomNavigationBar` comment above for
                  // the same reasoning applied to the action buttons.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Max players:',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(width: 8),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1')),
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 3, label: Text('3')),
                          ],
                          selected: {_maxConcurrentPlayers},
                          onSelectionChanged: (s) =>
                              setState(() => _maxConcurrentPlayers = s.first),
                        ),
                        const SizedBox(width: 16),
                        Text('Pause others:',
                            style: theme.textTheme.bodySmall),
                        Switch(
                          value: _pauseOthersOnPlay,
                          onChanged: (v) =>
                              setState(() => _pauseOthersOnPlay = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _kItemCount + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: MeasurementIntroCard(
                        text: '$_kItemCount independent MediaListPlayers, '
                            'each in its own StatefulWidget that creates '
                            'its MediaController in initState and disposes '
                            'it in dispose — plain ListView.builder '
                            'recycling bounds how many stay mounted, not '
                            'any custom pool. "Auto fling" gives a '
                            'repeatable programmatic condition; "Mark '
                            'start/end" lets you bracket a real touch '
                            'fling instead. Read bandwidth externally '
                            'between the start/end markers.',
                      ),
                    );
                  }
                  final index = i - 1;
                  return _ScrollFeedItem(
                    key: ValueKey('scrollbw_item_$index'),
                    index: index,
                    item: _kFixtures[index % _kFixtures.length],
                    config: config,
                    onCreated: _onItemCreated,
                    onDisposed: _onItemDisposed,
                    onPlayingChanged: _onItemPlayingChanged,
                    onLog: log,
                  );
                },
              ),
            ),
            // No outer SizedBox height cap: MeasurementLogPanel's own title
            // Row (with its copy-to-clipboard IconButton) plus its `height`
            // param together want a little more than a tightly-fixed 160dp
            // box (Row ~40-48dp + `height`), which produced a small but
            // real `RenderFlex overflowed` once the event log had a few
            // entries. Letting the Column size this non-flex child
            // intrinsically avoids that mismatch entirely while still
            // capping it via `height`'s `maxHeight` on the scrollable log
            // itself, and it stays a fixed, non-scrolling, always-reachable
            // sibling below the feed exactly as before.
            Padding(
              padding: const EdgeInsets.all(8),
              child: MeasurementLogPanel(eventLog: eventLog, height: 140),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollFeedItem extends StatefulWidget {
  final int index;
  final MediaItem item;
  final MediaListPlayerConfig config;
  final void Function(int index) onCreated;
  final void Function(int index) onDisposed;
  final void Function(int index, bool playing) onPlayingChanged;
  final void Function(String line) onLog;

  const _ScrollFeedItem({
    super.key,
    required this.index,
    required this.item,
    required this.config,
    required this.onCreated,
    required this.onDisposed,
    required this.onPlayingChanged,
    required this.onLog,
  });

  @override
  State<_ScrollFeedItem> createState() => _ScrollFeedItemState();
}

class _ScrollFeedItemState extends State<_ScrollFeedItem> {
  late final MediaController _controller;
  VoidCallback? _listener;
  StreamSubscription<MediaPlayerException>? _errorSub;
  bool _lastPlaying = false;
  bool _itemDisposed = false;

  String get _pad => widget.index.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    final suffix = DateTime.now().microsecondsSinceEpoch;
    _controller = MediaController.create(
      playerId: 'scrollbw_${widget.index}_$suffix',
      config: const MediaConfig(respectSafeArea: true),
    );
    widget.onCreated(widget.index);
    // Deferred to a post-frame callback rather than logged synchronously
    // here: `widget.onLog` triggers `setState` on the ancestor
    // `_ScrollBandwidthPageState`, and this `initState` runs *during*
    // `ListView`'s own build of this item — marking an ancestor dirty
    // mid-build is an invalid framework re-entrancy (violates the
    // "descendants build after ancestors" invariant enforced by
    // `Element.markNeedsBuild`). That is silent in release builds (the
    // check is assertion-gated) but throws in debug/profile builds and
    // widget tests, and is exactly the kind of rebuild churn that gets
    // worse the faster items are created during a fling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemDisposed) return;
      widget.onLog('[SCROLL-BW] item=$_pad created playerId='
          '${_controller.playerId}');
    });
    _listener = _onControllerChanged;
    _controller.addListener(_listener!);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _controller.initialize();
      if (_itemDisposed) return;
      // Unlike measurements #1/#2, this page's "Playing"/"Mounted" counts
      // are already reactive (recomputed from `_controller.isPlaying` on
      // every listener callback, not decided once) so they self-correct
      // if native flips playback state away from `playing` on error. This
      // subscription exists purely for diagnostics — surfacing *why* an
      // item died (native error code) in the log, which the reactive
      // counts alone can't show.
      _errorSub = _controller.player.errorStream.listen((err) {
        if (_itemDisposed) return;
        final code = nativeErrorCodeOf(err);
        widget.onLog('[SCROLL-BW] item=$_pad playback_error '
            '${code != null ? 'nativeErrorCode=$code ' : ''}error=$err');
      });
      await _controller.load(widget.item);
    } catch (e) {
      if (!_itemDisposed) {
        widget.onLog('[SCROLL-BW] item=$_pad load_error error=$e');
      }
    }
  }

  void _onControllerChanged() {
    final playing = _controller.isPlaying;
    if (playing == _lastPlaying) return;
    _lastPlaying = playing;
    widget.onPlayingChanged(widget.index, playing);
    widget.onLog(
      '[SCROLL-BW] item=$_pad event=${playing ? 'play' : 'pause'}',
    );
  }

  @override
  void dispose() {
    _itemDisposed = true;
    if (_listener != null) _controller.removeListener(_listener!);
    _errorSub?.cancel();
    _errorSub = null;
    // Deferred for the same reason `initState`'s "created" log is deferred
    // (see that comment) -- logging synchronously here calls `setState` on
    // the ancestor page while the framework's `BuildOwner` has the element
    // tree locked for unmount/finalization (`ListView.builder` recycling
    // many items at once during a fast fling disposes several in the same
    // frame), which is invalid re-entrancy. Assertion-gated, so silent in
    // release builds, but it fails outright in debug/profile builds and
    // widget tests.
    final onLog = widget.onLog;
    final message = '[SCROLL-BW] item=$_pad disposed';
    WidgetsBinding.instance.addPostFrameCallback((_) => onLog(message));
    widget.onDisposed(widget.index);
    try {
      _controller.dispose();
    } catch (_) {
      // Best-effort teardown while the item is being recycled away.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            MediaListPlayer(
              controller: _controller,
              config: widget.config,
              aspectRatio: 16 / 9,
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${widget.index}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

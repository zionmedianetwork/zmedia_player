import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../data/sample_media.dart';

/// Manual regression harness for [MediaFeed] — Stage 7b (pool) and Stage 7c
/// (prewarm window) of Phase 7. Sits alongside `feed_page.dart` (which
/// exercises [MediaListPlayer], the host-owned-controller widget) rather than
/// replacing it: this page proves the opposite ownership model actually
/// works end to end. [MediaFeed] never hands this page a [MediaController] —
/// only [MediaFeedItemState] snapshots and action callbacks — and the
/// [MediaPlayerPool] it scrolls through is bounded to [_maxPoolSize]
/// controllers no matter how many of the [_kItemCount] items have been
/// scrolled past.
///
/// ### What to look for while scrolling
///
/// The pinned header shows `pool: liveCount / maxSize` live (via an
/// [AnimatedBuilder] on the pool itself, which is a [ChangeNotifier]).
/// Scroll through more items than `maxSize` and that count must never climb
/// past it — unlike the pre-Stage-7b `MediaListPlayer` behaviour (F-01),
/// where every item ever scrolled past kept its own decoder session paused,
/// never released.
///
/// The `maxPoolSize` segmented control lets you change the pool's capacity at
/// runtime; because [MediaPlayerPool.maxSize] is fixed for a pool's lifetime,
/// changing it disposes the old pool (releasing every controller it held)
/// and swaps in a fresh one, remounting [MediaFeed] with a new [Key] so it
/// starts clean.
///
/// The `prewarm window` segmented control changes
/// [MediaFeedConfig.prewarmWindow] live, with no pool rebuild needed (the
/// underlying [MediaConfig]-level guarantee — a prewarmed neighbour is
/// loaded, never played — does not depend on the pool's identity). Each
/// item's badge distinguishes three states: **active** (the visible item,
/// green), **prewarmed** (loaded ahead of need by the window, amber, never
/// playing) and **no slot** (not yet loaded, grey) — this is exactly the gap
/// Stage 7c closes: before it, a neighbouring item had no slot at all until
/// it became visible itself, and item #13+ in this feed would render black
/// on the first scroll to it (see Stage 7b's device notes). Raise the window
/// above what `maxPoolSize` comfortably holds (`1 + 2 * window` slots) to see
/// the graceful degradation described in [MediaFeedConfig.prewarmWindow]'s
/// doc comment: the active item (pinned) is never evicted, and any prewarm
/// request that cannot fit is simply skipped and logged.
///
/// Every pool-visible transition (slot acquired, item became active) is
/// logged with the `[FEED-POOL]` prefix, mirroring `feed_page.dart`'s
/// `[FEED]` log so the two pages read the same way side by side.
class MediaFeedPoolPage extends StatefulWidget {
  const MediaFeedPoolPage({super.key});

  @override
  State<MediaFeedPoolPage> createState() => _MediaFeedPoolPageState();
}

/// More items than any of the offered pool sizes, so scrolling genuinely
/// forces eviction/reassignment rather than every item fitting in the pool
/// at once.
const int _kItemCount = 20;

const List<MediaItem> _kSampleItems = [
  SampleMedia.bigBuckBunny,
  SampleMedia.elephantsDream,
  SampleMedia.forBiggerBlazes,
  SampleMedia.forBiggerEscapes,
  SampleMedia.forBiggerJoyrides,
  SampleMedia.sintel,
  SampleMedia.tearsOfSteel,
];

class _MediaFeedPoolPageState extends State<MediaFeedPoolPage> {
  late MediaPlayerPool _pool;
  int _maxPoolSize = MediaPlayerPool.defaultMaxSize;

  /// Stage 7c: mirrors [MediaFeedConfig.prewarmWindow]'s own default (1).
  int _prewarmWindow = 1;

  /// Bumped every time [_pool] is replaced, folded into [MediaFeed]'s key so
  /// changing the pool size forces a clean remount instead of MediaFeed
  /// trying to reconcile against a pool it no longer owns.
  int _feedGeneration = 0;

  final List<String> _eventLog = [];
  bool _pageDisposed = false;

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
    super.dispose();
  }

  MediaPlayerPool _createPool(int maxSize) {
    final pool = MediaPlayerPool(maxSize: maxSize);
    pool.addListener(_onPoolChanged);
    return pool;
  }

  void _onPoolChanged() {
    if (!mounted || _pageDisposed) return;
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
    return base.copyWith(id: 'feed_pool_item_$index');
  }

  void _changePoolSize(int value) {
    if (value == _maxPoolSize) return;
    final oldPool = _pool;
    setState(() {
      _maxPoolSize = value;
      _pool = _createPool(value);
      _feedGeneration++;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('Feed (MediaFeed pool + prewarm, 7b/7c)')),
      body: SafeArea(
        child: Column(
          children: [
            _PoolHeader(
              pool: _pool,
              maxPoolSize: _maxPoolSize,
              onMaxPoolSizeChanged: _changePoolSize,
              prewarmWindow: _prewarmWindow,
              onPrewarmWindowChanged: _changePrewarmWindow,
            ),
            Expanded(
              child: MediaFeed(
                key: ValueKey('media-feed-gen-$_feedGeneration'),
                itemCount: _kItemCount,
                itemAt: _itemAt,
                pool: _pool,
                config: MediaFeedConfig(
                  autoPlay: true,
                  autoPause: true,
                  pauseOthersOnPlay: true,
                  prewarmWindow: _prewarmWindow,
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
              child: _Badge(text: '#${state.index}'),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _Badge(
                // Three states, per Stage 7c: an item is either the visible
                // "active" one (playing or ready to), "prewarmed" (a pool
                // slot was loaded ahead of need but this item was never
                // played -- see MediaFeedItemState.isPrewarmed), or holds no
                // slot at all yet.
                text: state.isPrewarmed
                    ? 'prewarmed'
                    : (state.isActive ? 'active' : 'no slot'),
                color: state.isPrewarmed
                    ? Colors.amber.shade700
                    : (state.isActive ? Colors.green : Colors.black54),
              ),
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
                        'buffering=${state.isBuffering}',
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

class _PoolHeader extends StatelessWidget {
  final MediaPlayerPool pool;
  final int maxPoolSize;
  final ValueChanged<int> onMaxPoolSizeChanged;
  final int prewarmWindow;
  final ValueChanged<int> onPrewarmWindowChanged;

  const _PoolHeader({
    required this.pool,
    required this.maxPoolSize,
    required this.onMaxPoolSizeChanged,
    required this.prewarmWindow,
    required this.onPrewarmWindowChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
        children: [
          Text(
            '$_kItemCount items, package-owned MediaPlayerPool -- no '
            'MediaController is ever handed to this page.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: pool,
            builder: (context, _) {
              return Text(
                'pool: ${pool.liveCount} / ${pool.maxSize} live slots',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('maxPoolSize:', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 5, label: Text('5')),
                ],
                selected: {maxPoolSize},
                onSelectionChanged: (selected) =>
                    onMaxPoolSizeChanged(selected.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('prewarm window (±):', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('0 (off)')),
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                ],
                selected: {prewarmWindow},
                onSelectionChanged: (selected) =>
                    onPrewarmWindowChanged(selected.first),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'window $prewarmWindow wants ${1 + 2 * prewarmWindow} live slots '
            '(current + $prewarmWindow ahead + $prewarmWindow behind); '
            'maxPoolSize is $maxPoolSize'
            '${maxPoolSize < 1 + 2 * prewarmWindow ? ' -- undersized: some '
                'prewarm requests will be skipped, active item is still '
                'protected' : ''}.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: maxPoolSize < 1 + 2 * prewarmWindow
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
        ],
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../data/sample_media.dart';

/// Manual regression harness for [MediaListPlayer] — the widget this package
/// advertises for use inside scrolling feeds, but which (before this page
/// existed) was used **nowhere** in this example app. That gap is the direct
/// reason B-09 shipped broken: its scroll-away pause was implemented with a
/// `NotificationListener<ScrollNotification>` placed *below* the enclosing
/// `Scrollable` in the widget tree, so the notification could structurally
/// never bubble up to it and the pause-on-scroll-away behavior was silent
/// dead code. The fix (see `lib/src/widgets/media_list_player.dart`) swapped
/// that for the `visibility_detector` package's compositor-callback-based
/// detection, added a [MediaListPlayerConfig.maxConcurrentPlayers] cap on
/// the shared playback coordinator, and made `wantKeepAlive` on the
/// underlying [MediaPlayerWidget] configurable (`false` for list usage, so a
/// scrolled-away item's native decoder/platform view is actually released
/// instead of being kept alive forever). None of that is exercisable without
/// a real scrolling feed of [MediaListPlayer]s — this page is that feed.
///
/// ### Controller lifecycle — deliberately eager
///
/// All [_kItemCount] [MediaController]s are created, `initialize()`d and
/// `load()`ed **up front**, concurrently, in [_loadAll] — not lazily as the
/// list scrolls. Two reasons:
///
/// 1. It is the simplest correct approach: [MediaListPlayer] is handed a
///    controller it does not own, so lazy creation would require this page
///    to track "which indices currently have a live controller" as a
///    separate piece of state synchronized with scroll position — more
///    surface area for the exact kind of lifecycle bug this page exists to
///    catch.
/// 2. It is itself a useful stress case: creating 12 native player
///    instances (and therefore, on both ExoPlayer and AVPlayer, 12
///    concurrent decoder/session objects during `load()`) up front is a
///    harder load than any real feed would normally impose in one frame,
///    and is exactly the kind of load [MediaListPlayerConfig.maxConcurrentPlayers]
///    exists to bound *once items become visible/playing* (the cap does not
///    limit merely-loaded-but-invisible controllers — see its doc comment).
///
/// Every controller is unconditionally disposed in [dispose] regardless of
/// scroll position or load state, mirroring the existing pattern in
/// `multi_player_page.dart`: `removeListener` first, then `dispose()`
/// (idempotent — guarded by `_isDisposed` — so it is safe even if a
/// controller never finished loading or is already invisible). A
/// `_pageDisposed` flag is checked before every `setState`/`await`
/// continuation in the background load loop so a load step that completes
/// after the page is popped can never touch a disposed controller or call
/// `setState` on an unmounted state.
///
/// ### Reading the results — the `[FEED]` log
///
/// Every meaningful event is printed to the console with the `[FEED]`
/// prefix and mirrored (newest-first) in the on-screen log panel at the
/// bottom of this page, so it is readable in a release build without
/// attaching tooling:
///
/// ```
/// [FEED] BOOT creating and loading 12 controllers up front (concurrent, stress case)
/// [FEED] item=03 playerId=feed_3_... event=loaded title=Bee
/// [FEED] item=03 playerId=feed_3_... event=visible
/// [FEED] item=03 playerId=feed_3_... event=play state=playing visible=true
/// [FEED] item=03 playerId=feed_3_... event=pause state=paused visible=false
/// [FEED] item=03 playerId=feed_3_... event=invisible
/// [FEED] CONFIG maxConcurrentPlayers=1
/// [FEED] CONFIG pauseOthersOnPlay=false
/// ```
///
/// `event=play`/`event=pause` lines are edge-triggered (fired once per
/// not-playing→playing or playing→not-playing transition, not on every
/// state tick) and always include the item's `visible` flag *at the moment
/// of the transition* — this is what lets you tell apart, from the log
/// alone, an ordinary scroll-away pause (`event=pause ... visible=false`,
/// preceded by that same item's own `event=invisible`) from a
/// `maxConcurrentPlayers` cap eviction or `pauseOthersOnPlay` pause (`event=pause
/// ... visible=true` — the item never left the screen, so nothing but the
/// shared coordinator could have paused it).
///
/// See the class-level knobs (`maxConcurrentPlayers` segmented control,
/// `pauseOthersOnPlay` switch) in the pinned header, and the operator script
/// delivered alongside this page for the exact scroll/toggle sequence that
/// verifies all three Phase 4 behaviors.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

/// Number of feed items. 10-12 is enough to exercise `maxConcurrentPlayers`
/// values of 1-3 while still requiring real scrolling to reach every item.
const int _kItemCount = 12;

/// Short sample clips only (4-10s) — see `SampleMedia` doc comment: the
/// 10-minute `forBiggerFun`/`bbbFull` clip is deliberately excluded here
/// since loading 12 concurrent copies of it up front would make the initial
/// load step slow for no benefit to what this page is testing.
const List<MediaItem> _kSampleItems = [
  SampleMedia.bigBuckBunny,
  SampleMedia.elephantsDream,
  SampleMedia.forBiggerBlazes,
  SampleMedia.forBiggerEscapes,
  SampleMedia.forBiggerJoyrides,
  SampleMedia.sintel,
  SampleMedia.tearsOfSteel,
];

/// Per-item bookkeeping. Not a widget — just the state this page needs to
/// track per [MediaController] alongside the controller itself.
class _FeedEntry {
  final int index;
  final MediaItem item;
  final MediaController controller;

  /// Mirrors [MediaListPlayer.onVisible]/`onInvisible` so the item card and
  /// the `[FEED]` log can report visibility independently of the
  /// controller's own playback state.
  final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  /// Listener registered on [controller] for edge-triggered play/pause
  /// logging; stored so [FeedPage.dispose] can remove it before disposing.
  VoidCallback? listener;

  /// Last `isPlaying` value logged, so play/pause logging only fires on the
  /// not-playing<->playing edge, not on every state notification.
  bool lastLoggedPlaying = false;

  _FeedEntry(
      {required this.index, required this.item, required this.controller});
}

class _FeedPageState extends State<FeedPage> {
  late final List<_FeedEntry> _entries;
  late final Listenable _mergedControllers;

  bool _loading = true;
  int _loadedCount = 0;

  /// Set synchronously at the top of [dispose], before any teardown, so any
  /// in-flight step of [_loadAll]/[_loadEntry] can check it and bail out
  /// instead of calling `setState` or touching a controller that is about
  /// to be (or already has been) disposed.
  bool _pageDisposed = false;

  // ---- Knobs under test -----------------------------------------------
  // Defaults mirror MediaListPlayerConfig's own defaults so the page starts
  // in the same configuration a consuming app would get out of the box.
  int _maxConcurrentPlayers = 2;
  bool _pauseOthersOnPlay = true;

  final List<String> _eventLog = [];

  @override
  void initState() {
    super.initState();
    final suffix = DateTime.now().microsecondsSinceEpoch;
    _entries = List.generate(_kItemCount, (i) {
      final item = _kSampleItems[i % _kSampleItems.length];
      final controller = MediaController.create(
        playerId: 'feed_${i}_$suffix',
        config: const MediaConfig(respectSafeArea: true),
      );
      return _FeedEntry(index: i, item: item, controller: controller);
    });
    _mergedControllers =
        Listenable.merge(_entries.map((e) => e.controller).toList());
    for (final entry in _entries) {
      entry.listener = () => _onControllerChanged(entry);
      entry.controller.addListener(entry.listener!);
    }
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _pageDisposed = true;
    for (final entry in _entries) {
      if (entry.listener != null) {
        entry.controller.removeListener(entry.listener!);
      }
      try {
        entry.controller.dispose();
      } catch (e) {
        debugPrint('[FEED] item=${_pad(entry.index)} dispose error: $e');
      }
      entry.visible.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // [FEED] logging
  // ---------------------------------------------------------------------

  String _pad(int i) => i.toString().padLeft(2, '0');

  void _log(String message) {
    final line = '[FEED] $message';
    debugPrint(line);
    if (!mounted || _pageDisposed) return;
    setState(() {
      _eventLog.insert(0, line);
      if (_eventLog.length > 60) _eventLog.removeLast();
    });
  }

  void _onControllerChanged(_FeedEntry entry) {
    final isPlayingNow = entry.controller.isPlaying;
    if (isPlayingNow == entry.lastLoggedPlaying) return;
    entry.lastLoggedPlaying = isPlayingNow;
    _log(
      'item=${_pad(entry.index)} playerId=${entry.controller.playerId} '
      'event=${isPlayingNow ? 'play' : 'pause'} '
      'state=${entry.controller.state.state.name} '
      'visible=${entry.visible.value}',
    );
  }

  void _onItemVisible(_FeedEntry entry) {
    entry.visible.value = true;
    _log(
      'item=${_pad(entry.index)} playerId=${entry.controller.playerId} '
      'event=visible',
    );
  }

  void _onItemInvisible(_FeedEntry entry) {
    entry.visible.value = false;
    _log(
      'item=${_pad(entry.index)} playerId=${entry.controller.playerId} '
      'event=invisible',
    );
  }

  // ---------------------------------------------------------------------
  // Eager, concurrent controller loading (see class doc comment for why).
  // ---------------------------------------------------------------------

  Future<void> _loadAll() async {
    _log(
      'BOOT creating and loading ${_entries.length} controllers up front '
      '(concurrent, deliberate stress case)',
    );
    await Future.wait(_entries.map(_loadEntry));
    if (_pageDisposed || !mounted) return;
    setState(() => _loading = false);
    _log(
      'BOOT all ${_entries.length} controllers initialized and loaded -- '
      'feed is ready to scroll',
    );
  }

  Future<void> _loadEntry(_FeedEntry entry) async {
    try {
      await entry.controller.initialize();
      if (_pageDisposed) return;
      await entry.controller.load(entry.item);
      if (_pageDisposed) return;
      _loadedCount++;
      _log(
        'item=${_pad(entry.index)} playerId=${entry.controller.playerId} '
        'event=loaded title=${entry.item.title}',
      );
      if (mounted && !_pageDisposed) setState(() {});
    } catch (e) {
      _log(
        'item=${_pad(entry.index)} playerId=${entry.controller.playerId} '
        'event=load_error error=$e',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Knobs
  // ---------------------------------------------------------------------

  void _setMaxConcurrentPlayers(int value) {
    setState(() => _maxConcurrentPlayers = value);
    _log(
      'CONFIG maxConcurrentPlayers=${value <= 0 ? 'disabled' : value} '
      '(applies to future visibility-threshold crossings only -- items '
      'already counted as live are not retroactively re-evaluated until '
      'they next become visible or invisible)',
    );
  }

  void _setPauseOthersOnPlay(bool value) {
    setState(() => _pauseOthersOnPlay = value);
    _log('CONFIG pauseOthersOnPlay=$value');
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed (MediaListPlayer)')),
      body: SafeArea(
        child: Column(
          children: [
            _FeedHeader(
              mergedControllers: _mergedControllers,
              entries: _entries,
              maxConcurrentPlayers: _maxConcurrentPlayers,
              pauseOthersOnPlay: _pauseOthersOnPlay,
              onMaxConcurrentPlayersChanged: _setMaxConcurrentPlayers,
              onPauseOthersOnPlayChanged: _setPauseOthersOnPlay,
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            'Loading $_loadedCount / ${_entries.length} '
                            'controllers...',
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _entries.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) return const _IntroCard();
                        final entry = _entries[i - 1];
                        return _FeedItemCard(
                          entry: entry,
                          maxConcurrentPlayers: _maxConcurrentPlayers,
                          pauseOthersOnPlay: _pauseOthersOnPlay,
                          onVisible: () => _onItemVisible(entry),
                          onInvisible: () => _onItemInvisible(entry),
                        );
                      },
                    ),
            ),
            _EventLogPanel(eventLog: _eventLog),
          ],
        ),
      ),
    );
  }
}

/// Pinned (never scrolls with the feed) header: live playing count plus the
/// two knobs under test, with their current values always visible.
class _FeedHeader extends StatelessWidget {
  final Listenable mergedControllers;
  final List<_FeedEntry> entries;
  final int maxConcurrentPlayers;
  final bool pauseOthersOnPlay;
  final ValueChanged<int> onMaxConcurrentPlayersChanged;
  final ValueChanged<bool> onPauseOthersOnPlayChanged;

  const _FeedHeader({
    required this.mergedControllers,
    required this.entries,
    required this.maxConcurrentPlayers,
    required this.pauseOthersOnPlay,
    required this.onMaxConcurrentPlayersChanged,
    required this.onPauseOthersOnPlayChanged,
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
          AnimatedBuilder(
            animation: mergedControllers,
            builder: (context, _) {
              final playing =
                  entries.where((e) => e.controller.isPlaying).length;
              return Text(
                'Playing: $playing / ${entries.length}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('maxConcurrentPlayers:', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 0, label: Text('Off')),
                ],
                selected: {maxConcurrentPlayers},
                onSelectionChanged: (selected) =>
                    onMaxConcurrentPlayersChanged(selected.first),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('pauseOthersOnPlay:', style: theme.textTheme.bodySmall),
              Switch(
                value: pauseOthersOnPlay,
                onChanged: onPauseOthersOnPlayChanged,
              ),
              Text(
                pauseOthersOnPlay ? 'on' : 'off',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$_kItemCount independent MediaListPlayers, each with its own '
          'MediaController, created and loaded up front (see the class doc '
          'comment in feed_page.dart for why). Scroll to move items in and '
          'out of view: each should auto-play when it crosses the '
          'visibility threshold and auto-pause when it leaves. The header '
          'above stays pinned and shows how many controllers currently '
          'report isPlaying, plus the two knobs under test -- '
          'maxConcurrentPlayers (caps how many items may be simultaneously '
          'live) and pauseOthersOnPlay (starting one item pauses every '
          'other currently-playing one). Every play/pause/visibility '
          'transition is logged below with the "[FEED]" prefix.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  final _FeedEntry entry;
  final int maxConcurrentPlayers;
  final bool pauseOthersOnPlay;
  final VoidCallback onVisible;
  final VoidCallback onInvisible;

  const _FeedItemCard({
    required this.entry,
    required this.maxConcurrentPlayers,
    required this.pauseOthersOnPlay,
    required this.onVisible,
    required this.onInvisible,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                MediaListPlayer(
                  // Keyed by playerId (stable across this page's rebuilds)
                  // so toggling the knobs above never recreates this
                  // widget's State -- only its `config` field changes,
                  // which _MediaListPlayerState reads fresh via `widget`.
                  key: ValueKey(
                    'feed_list_player_${entry.controller.playerId}',
                  ),
                  controller: entry.controller,
                  config: MediaListPlayerConfig(
                    maxConcurrentPlayers: maxConcurrentPlayers,
                    pauseOthersOnPlay: pauseOthersOnPlay,
                  ),
                  aspectRatio: 16 / 9,
                  onVisible: onVisible,
                  onInvisible: onInvisible,
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
                      '#${entry.index}',
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
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: Listenable.merge([entry.controller, entry.visible]),
            builder: (context, _) {
              return Text(
                'item=${entry.index}  ${entry.item.title}\n'
                'playerId=${entry.controller.playerId}\n'
                'state=${entry.controller.state.state.name}  '
                'isPlaying=${entry.controller.isPlaying}  '
                'visible=${entry.visible.value}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Fixed-height (never scrolls away, does not grow with content) event log
/// panel mirroring console `[FEED]` lines, newest-first.
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
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event log (mirrors console [FEED] lines, newest first)',
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

import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../../data/sample_media.dart';
import '../../widgets/measurement_log_panel.dart';

/// Stage 7a measurement #2 — memory: prepared-but-paused vs playing.
///
/// This is the number `MediaListPlayer._evictExcess`'s F-01 finding turns
/// on: `pause()` never disposes a player, so `maxConcurrentPlayers` bounds
/// how many items *play*, not how many hold decoder/buffer/socket
/// resources. If a paused player is nearly as expensive as a playing one,
/// pooling (Stage 7b) is mandatory rather than an optimisation.
///
/// The page spawns N players in one of two conditions and leaves them
/// alive so the operator can read memory externally:
/// - **Playing**: loaded and `play()`ed.
/// - **Prepared-but-paused**: loaded, allowed to settle to a ready state,
///   then explicitly `pause()`d — genuinely prepared and buffered, not
///   merely "never started".
///
/// ### This measurement's result depends on "genuinely alive"
/// Whether a spawn's `load()`/`pause()`/`play()` calls *returned* without
/// throwing says nothing about whether the player is still alive by the
/// time the operator actually reads memory a few seconds later — the same
/// class of defect the decoder-ceiling page (#1) had, and the one this
/// page is most exposed to: a memory reading that silently includes one or
/// more dead players corrupts exactly the number this measurement exists
/// to produce. So every entry keeps its `errorStream` subscription open
/// for the whole life of the batch (not just spawn time), tracks a
/// revisable alive/dead [_Outcome], and the on-screen "alive" count is the
/// reconciled count, not the raw spawn count — a dead entry is called out
/// distinctly (dimmed tile, error banner, native error code) rather than
/// folded silently into "N players".
///
/// ### In-app vs external
/// This page samples whole-process memory itself via `dart:io`'s
/// `ProcessInfo.currentRss` — the one memory API that is both portable
/// (identical on Android and iOS) and reaches native allocations, since it
/// reports the entire process's resident set rather than just the
/// Dart/Flutter heap. That reading is shown live on screen (updated on a
/// 1s timer), sampled once at page load with zero players as the
/// [_baselineRssBytes] baseline, and — critically — sampled again and
/// stamped as `rssMb=<mb>` into every `[7A-MEASURE]` marker this page
/// emits, so a reading is anchored to a known condition (e.g.
/// `[7A-MEASURE] end:memory-paused-vs-playing condition=playing
/// requested=8 succeeded=8 failed=0 rssMb=NNN`) rather than whatever the
/// operator happened to see when they looked. That is what makes this
/// measurement finally runnable on iOS from a log stream alone: capture
/// `[7A-MEASURE]` lines with `idevicesyslog` and the memory reading comes
/// with them, with no need to also be looking at the device — unlike
/// `xcrun devicectl device info processes`, which reports only PID and
/// executable path with no memory figure, the only other on-iOS routes
/// (Xcode's Debug Navigator, Instruments' Allocations template) require
/// watching the device directly.
///
/// In-app RSS is whole-process, so unlike `adb shell dumpsys meminfo` it
/// does not break out separate "Native Heap" / "Graphics" lines — it is
/// the equivalent of `dumpsys`'s single TOTAL RSS figure, which is exactly
/// what it should be compared against to validate the method (see the
/// operator card below). External tooling remains available as an
/// Android-only cross-check, but in-app RSS is now the primary,
/// cross-platform reading. Wait a few seconds after the `end:` marker
/// before trusting either reading, so any native buffering triggered by
/// `play()` has stabilized, and check the on-screen alive/dead count
/// hasn't changed in that window.
class MemoryPausedPlayingPage extends StatefulWidget {
  const MemoryPausedPlayingPage({super.key});

  @override
  State<MemoryPausedPlayingPage> createState() =>
      _MemoryPausedPlayingPageState();
}

const List<MediaItem> _kFixtures = [
  SampleMedia.bigBuckBunny,
  SampleMedia.elephantsDream,
  SampleMedia.forBiggerBlazes,
  SampleMedia.forBiggerEscapes,
  SampleMedia.forBiggerJoyrides,
  SampleMedia.sintel,
  SampleMedia.tearsOfSteel,
];

/// Per-entry liveness, tracked so a spawn that returned successfully can
/// still be revised to dead if an error arrives later — see the class doc
/// above.
enum _Outcome { alive, dead }

class _MemoryEntry {
  final int index;
  final MediaController controller;
  _Outcome outcome = _Outcome.alive;
  String? error;
  String? nativeErrorCode;
  StreamSubscription<MediaPlayerException>? errorSub;

  _MemoryEntry({required this.index, required this.controller});
}

class _MemoryPausedPlayingPageState extends State<MemoryPausedPlayingPage>
    with MeasurementLoggerMixin {
  List<_MemoryEntry> _spawned = [];
  int _count = 8;
  bool _busy = false;
  String? _currentCondition;

  /// Sampled once, at page load, with zero players alive — the reference
  /// point every delta/per-player figure in this page is measured against.
  int? _baselineRssBytes;

  /// Refreshed by [_rssTimer] every second, and eagerly re-sampled right
  /// after a batch settles (so the on-screen figure doesn't lag the marker
  /// that was just logged by up to a second).
  int _currentRssBytes = 0;

  Timer? _rssTimer;

  int get _aliveCount =>
      _spawned.where((e) => e.outcome == _Outcome.alive).length;
  int get _deadCount =>
      _spawned.where((e) => e.outcome == _Outcome.dead).length;

  /// The actual measurement: growth over the zero-player baseline. Not
  /// clamped to >=0 — a negative reading (e.g. after GC settles) is itself
  /// informative rather than something to hide.
  int get _deltaRssBytes => _currentRssBytes - (_baselineRssBytes ?? 0);

  /// Whole-process resident set size, in bytes. Portable across Android and
  /// iOS (unlike `adb shell dumpsys meminfo`, which has no iOS
  /// equivalent), and reaches native decoder/buffer allocations because it
  /// is the entire process, not just the Dart/Flutter heap.
  int _sampleRssBytes() => ProcessInfo.currentRss;

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    final baseline = _sampleRssBytes();
    _baselineRssBytes = baseline;
    _currentRssBytes = baseline;
    logMarker('mark', 'memory-paused-vs-playing', {
      'note': 'baseline',
      'n': 0,
      'rssMb': _mb(baseline),
    });
    _rssTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || loggerDisposed) return;
      setState(() => _currentRssBytes = _sampleRssBytes());
    });
  }

  @override
  void dispose() {
    loggerDisposed = true;
    _rssTimer?.cancel();
    _rssTimer = null;
    for (final entry in _spawned) {
      _teardown(entry);
    }
    super.dispose();
  }

  void _teardown(_MemoryEntry entry) {
    entry.errorSub?.cancel();
    entry.errorSub = null;
    try {
      entry.controller.dispose();
    } catch (_) {
      // Best-effort teardown on page exit / batch replacement.
    }
  }

  /// Reconciles [entry] to dead the moment a real error is observed —
  /// however long after it was spawned. Idempotent: the first error wins.
  /// Deliberately does NOT dispose the controller — disposing it would
  /// itself change the very memory condition being measured; instead the
  /// entry is surfaced as dead so the operator can see the reconciled
  /// alive count is lower than the raw spawn count and re-run the batch if
  /// this affects the reading.
  void _onEntryError(_MemoryEntry entry, MediaPlayerException err) {
    if (entry.outcome == _Outcome.dead) return;
    entry.outcome = _Outcome.dead;
    entry.error = err.toString();
    entry.nativeErrorCode = nativeErrorCodeOf(err);

    logMarker('mark', 'memory-paused-vs-playing', {
      'note': 'player-died',
      'n': entry.index,
      if (entry.nativeErrorCode != null)
        'nativeErrorCode': entry.nativeErrorCode,
      'rssMb': _mb(_sampleRssBytes()),
      'error': entry.error,
    });

    safeSetState(() {});
  }

  Future<void> _disposeAll({bool logTeardown = false}) async {
    if (_spawned.isEmpty) return;
    if (logTeardown) {
      logMarker('mark', 'memory-paused-vs-playing', {
        'note': 'teardown-previous-batch',
        'n': _spawned.length,
        'rssMb': _mb(_sampleRssBytes()),
      });
    }
    final toDispose = _spawned;
    _spawned = [];
    for (final entry in toDispose) {
      _teardown(entry);
    }
  }

  Future<void> _spawnBatch({required bool playing}) async {
    if (_busy) return;
    setState(() => _busy = true);

    await _disposeAll(logTeardown: true);

    final condition = playing ? 'playing' : 'prepared-paused';
    logMarker(
      'start',
      'memory-paused-vs-playing',
      {
        'condition': condition,
        'n': _count,
        'rssMb': _mb(_sampleRssBytes()),
      },
    );

    var failures = 0;
    for (var i = 0; i < _count; i++) {
      final n = i + 1;
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final item = _kFixtures[i % _kFixtures.length];
      final controller = MediaController.create(
        playerId: 'mem_${playing ? 'play' : 'pause'}_${n}_$suffix',
        config: const MediaConfig(respectSafeArea: true),
      );
      final entry = _MemoryEntry(index: n, controller: controller);
      try {
        await controller.initialize();
        // Kept open for the entry's entire lifetime (not cancelled after
        // this spawn loop finishes) — a decoder/renderer error that
        // arrives while the operator is reading memory a few seconds
        // later must still flip this entry to dead. Tracked in `_spawned`
        // immediately, before any further awaits, so a batch replacement
        // or page dispose mid-spawn still tears this down instead of
        // leaking it.
        entry.errorSub = controller.player.errorStream.listen((err) {
          _onEntryError(entry, err);
        });
        _spawned.add(entry);
        await controller.load(item);
        // Let native settle to a ready/prepared state before deciding
        // play vs pause, so "prepared-but-paused" is genuinely prepared
        // and buffered, not merely "load() was called and nothing else".
        await Future.delayed(const Duration(milliseconds: 600));
        if (playing) {
          await controller.play();
        } else {
          await controller.pause();
        }
      } catch (e) {
        failures++;
        log('[7A-MEASURE] mark:memory-paused-vs-playing '
            'note=spawn-failed n=$n rssMb=${_mb(_sampleRssBytes())} '
            'error=$e');
        _spawned.remove(entry);
        _teardown(entry);
      }
    }

    final endRssBytes = _sampleRssBytes();
    logMarker('end', 'memory-paused-vs-playing', {
      'condition': condition,
      'requested': _count,
      'succeeded': _spawned.length,
      'failed': failures,
      'rssMb': _mb(endRssBytes),
    });

    safeSetState(() {
      _busy = false;
      _currentCondition = condition;
      // Refresh eagerly rather than waiting up to 1s for `_rssTimer`, so
      // the on-screen figure matches the `end:` marker just logged above.
      _currentRssBytes = endRssBytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aliveCount = _aliveCount;
    final deadCount = _deadCount;
    return Scaffold(
      appBar: AppBar(title: const Text('2. Memory: Paused vs Playing')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MeasurementIntroCard(
              text: 'Pick a player count, then press "Spawn PLAYING" or '
                  '"Spawn PREPARED+PAUSED" — either fully tears down the '
                  'previous batch first, so only one condition is ever '
                  'live at once. Wait a few seconds after the batch '
                  'settles, then read the memory card below (or the '
                  'rssMb= field on the matching `[7A-MEASURE]` marker, if '
                  'reading a log stream instead of the screen). Each entry '
                  'keeps watching for a late playback error the whole time '
                  'it stays alive — if the "Dead" count moves while '
                  'you\'re reading memory, discard that reading and re-run '
                  'the batch, since a dead player corrupts the number. Run '
                  'both conditions at the same count and compare.',
            ),
            const SizedBox(height: 12),
            MeasurementOperatorCard(
              title: 'Operator steps (memory)',
              text: 'In-app RSS (the card below, and the rssMb= field on '
                  'every `[7A-MEASURE]` marker this page emits) is the '
                  'primary, cross-platform reading — it is whole-process '
                  "resident set size (dart:io's ProcessInfo.currentRss), "
                  'so unlike `dumpsys` it does not break out separate '
                  '"Native Heap" / "Graphics" lines, only a single TOTAL '
                  '-equivalent figure. On iOS, capture the marker lines '
                  'with `idevicesyslog` — `xcrun devicectl device info '
                  'processes` reports only PID and executable path, no '
                  'memory, and Xcode\'s Debug Navigator / Instruments '
                  'Allocations require watching the device directly.\n'
                  'Android: cross-check the in-app number against `adb '
                  'shell dumpsys meminfo '
                  'com.zionmedianetwork.zmedia_player_example` (TOTAL '
                  'RSS / TOTAL PSS) at the same moment — if they track '
                  'each other, the in-app method is trustworthy on iOS '
                  'too. Take one reading per condition, at the same '
                  'player count, a few seconds after this page\'s `end:` '
                  'marker, and only if the Alive/Dead split is still '
                  'stable at that point.',
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Memory (RSS)', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Baseline (0 players): ${_mb(_baselineRssBytes ?? 0)} '
                      'MB\n'
                      'Current: ${_mb(_currentRssBytes)} MB   '
                      'Delta: ${_deltaRssBytes >= 0 ? '+' : ''}'
                      '${_mb(_deltaRssBytes)} MB'
                      '${aliveCount > 0 ? '   Per player: ${_mb((_deltaRssBytes / aliveCount).round())} MB (n=$aliveCount alive)' : ''}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Player count: $_count',
                        style: theme.textTheme.titleSmall),
                    Slider(
                      value: _count.toDouble(),
                      min: 1,
                      max: 15,
                      divisions: 14,
                      label: '$_count',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _count = v.round()),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Spawn PLAYING'),
                          onPressed:
                              _busy ? null : () => _spawnBatch(playing: true),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.pause),
                          label: const Text('Spawn PREPARED+PAUSED'),
                          onPressed:
                              _busy ? null : () => _spawnBatch(playing: false),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Dispose all'),
                          onPressed: (_busy || _spawned.isEmpty)
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  await _disposeAll(logTeardown: true);
                                  safeSetState(() {
                                    _busy = false;
                                    _currentCondition = null;
                                    // Refresh eagerly rather than waiting
                                    // up to 1s for `_rssTimer`.
                                    _currentRssBytes = _sampleRssBytes();
                                  });
                                },
                        ),
                      ],
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_currentCondition != null && !_busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Current batch: ${_spawned.length} spawned, '
                          '$aliveCount alive, $deadCount dead, '
                          'condition=$_currentCondition — read memory now.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color:
                                deadCount > 0 ? theme.colorScheme.error : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_spawned.isNotEmpty) ...[
              Text('Live players', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                itemCount: _spawned.length,
                itemBuilder: (context, i) {
                  final entry = _spawned[i];
                  final dead = entry.outcome == _Outcome.dead;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: MediaPlayerWidget(
                            controller: entry.controller,
                            showControls: false,
                            boxFit: BoxFit.cover,
                            backgroundColor: Colors.black,
                          ),
                        ),
                        if (dead)
                          Positioned.fill(
                            child: Container(
                              color: Colors.red.withValues(alpha: 0.35),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.error_outline,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Text(
                            '${entry.index}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(blurRadius: 2, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            if (deadCount > 0) ...[
              Text('Dead players', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                color: theme.colorScheme.errorContainer.withValues(
                  alpha: 0.3,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in _spawned)
                        if (entry.outcome == _Outcome.dead)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              'n=${entry.index}'
                              '${entry.nativeErrorCode != null ? ' [${entry.nativeErrorCode}]' : ''}'
                              ': ${entry.error}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            MeasurementLogPanel(eventLog: eventLog),
          ],
        ),
      ),
    );
  }
}

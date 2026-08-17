import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:zmedia_player/zmedia_player.dart';

import '../../data/sample_media.dart';
import '../../widgets/measurement_log_panel.dart';

/// Stage 7a measurement #3 — time-to-first-frame, with and without
/// prewarming.
///
/// Measured **entirely in-app** — no external tooling needed for this one.
/// This is the measurement that justifies (or kills) the ±1 prewarm window
/// default. It deliberately covers HLS and DASH, not just progressive
/// MP4 — the multi-round-trip manifest/segment case is the one that
/// matters for a prewarm window, and a progressive MP4-only measurement
/// would hide exactly that cost.
///
/// ### What "cold" and "prewarm" mean here
/// - **Cold** (`load-and-play`): `load()` immediately followed by `play()`,
///   with no time for the player to prepare first — the common case when
///   an item becomes visible in a feed and starts playing right away.
/// - **Prewarm** (`load-then-play`): `load()`, then wait for the player to
///   report [PlayerState.ready] (i.e. actually prepared/buffered), then a
///   short fixed dwell (simulating the time a user spends scrolling before
///   an item is actually acted on), and only then `play()`. The clock for
///   this condition starts at the `play()` call, not at `load()` — it
///   measures the *marginal* cost once prewarming has already happened,
///   which is the number a prewarm-window design decision needs.
///
/// ### What "first frame" means here
/// There is no direct "first frame rendered" callback in the public API.
/// The proxy used is the first transition to [PlayerState.playing] after
/// the timed `play()` call — native only reports `playing` once playback
/// is actually underway. This is documented as an approximation, not a
/// literal decoder frame-ready callback.
///
/// This page never reports success on a synchronous call returning — a run
/// only counts as a result once the player actually transitions to
/// [PlayerState.playing], so it does not share the decoder-ceiling page's
/// original defect. It does listen to `errorStream` too, though: without
/// that, a real decoder/network failure that arrives before `playing` is
/// ever reached would just burn the full timeout and get reported as an
/// opaque "timeout waiting for playing state" instead of the actual native
/// error code.
class TimeToFirstFramePage extends StatefulWidget {
  const TimeToFirstFramePage({super.key});

  @override
  State<TimeToFirstFramePage> createState() => _TimeToFirstFramePageState();
}

class _Fixture {
  final String label;
  final MediaItem item;
  const _Fixture(this.label, this.item);
}

const List<_Fixture> _kFixtures = [
  _Fixture('mp4', SampleMedia.bigBuckBunny),
  _Fixture('hls', SampleMedia.hlsStream),
  _Fixture('dash', SampleMedia.dashStream),
];

/// How long a run may take (load + prepare + play) before it's recorded as
/// a timeout rather than hanging forever.
const Duration _runTimeout = Duration(seconds: 30);

/// Simulated "user is still scrolling" dwell between the prewarmed player
/// reaching ready and the timed `play()` call.
const Duration _prewarmDwell = Duration(seconds: 1);

class _TtffResult {
  final String fixture;
  final String condition; // 'cold' | 'prewarm'
  final int? ttffMs;
  final String? error;
  final DateTime timestamp;

  _TtffResult({
    required this.fixture,
    required this.condition,
    this.ttffMs,
    this.error,
    required this.timestamp,
  });

  String get asLine => 'fixture=$fixture condition=$condition '
          'ttffMs=${ttffMs ?? '-'} ${error != null ? 'error=$error' : ''}'
      .trim();
}

class _TimeToFirstFramePageState extends State<TimeToFirstFramePage>
    with MeasurementLoggerMixin {
  final List<_TtffResult> _results = [];
  bool _running = false;
  String? _runningLabel;
  MediaController? _previewController;

  @override
  void dispose() {
    loggerDisposed = true;
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _runOne(_Fixture fixture, {required bool prewarm}) async {
    if (_running) return;
    final condition = prewarm ? 'prewarm' : 'cold';
    setState(() {
      _running = true;
      _runningLabel = '${fixture.label}/$condition';
    });

    logMarker('start', 'ttff', {
      'fixture': fixture.label,
      'condition': condition,
    });

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final controller = MediaController.create(
      playerId: 'ttff_${fixture.label}_${condition}_$suffix',
      config: const MediaConfig(respectSafeArea: true),
    );

    safeSetState(() {
      _previewController?.dispose();
      _previewController = controller;
    });

    int? ttffMs;
    String? error;
    DateTime? t0;

    final playingCompleter = Completer<void>();
    void playingListener() {
      if (controller.state.state == PlayerState.playing &&
          !playingCompleter.isCompleted) {
        playingCompleter.complete();
      }
    }

    // Without this, a load/decoder failure that arrives before `playing`
    // is ever reached just burns the full `_runTimeout` and gets reported
    // as a generic "timeout waiting for playing state" — technically
    // honest (this page never claims success without an actual state
    // transition) but useless for diagnosing *why*. Failing fast on a real
    // error and surfacing its native error code applies the same
    // "surface why a player died" fix the other measurement pages needed.
    StreamSubscription<MediaPlayerException>? errorSub;

    try {
      await controller.initialize();
      controller.addListener(playingListener);
      errorSub = controller.player.errorStream.listen((err) {
        if (!playingCompleter.isCompleted) {
          playingCompleter.completeError(err);
        }
      });

      if (prewarm) {
        await controller.load(fixture.item);

        final readyCompleter = Completer<void>();
        void readyListener() {
          final s = controller.state.state;
          if ((s == PlayerState.ready || s == PlayerState.paused) &&
              !readyCompleter.isCompleted) {
            readyCompleter.complete();
          }
        }

        controller.addListener(readyListener);
        try {
          await readyCompleter.future.timeout(_runTimeout);
        } on TimeoutException {
          log('[7A-MEASURE] mark:ttff note=ready-timeout '
              'fixture=${fixture.label}');
        } finally {
          controller.removeListener(readyListener);
        }

        await Future.delayed(_prewarmDwell);
        t0 = DateTime.now();
        await controller.play();
      } else {
        t0 = DateTime.now();
        await controller.load(fixture.item);
        await controller.play();
      }

      try {
        await playingCompleter.future.timeout(_runTimeout);
        ttffMs = DateTime.now().difference(t0).inMilliseconds;
      } on TimeoutException {
        error = 'timeout waiting for playing state';
      } on MediaPlayerException catch (e) {
        final code = nativeErrorCodeOf(e);
        error = 'playback error before first frame'
            '${code != null ? ' [$code]' : ''}: $e';
      }
    } catch (e) {
      error = e.toString();
    } finally {
      controller.removeListener(playingListener);
      await errorSub?.cancel();
    }

    logMarker('end', 'ttff', {
      'fixture': fixture.label,
      'condition': condition,
      'ttffMs': ttffMs ?? '-',
      if (error != null) 'error': error,
    });

    final result = _TtffResult(
      fixture: fixture.label,
      condition: condition,
      ttffMs: ttffMs,
      error: error,
      timestamp: DateTime.now(),
    );

    try {
      controller.dispose();
    } catch (_) {
      // Already broken.
    }

    safeSetState(() {
      _results.insert(0, result);
      if (identical(_previewController, controller)) {
        _previewController = null;
      }
      _running = false;
      _runningLabel = null;
    });
  }

  Future<void> _runAll() async {
    for (final fixture in _kFixtures) {
      if (loggerDisposed) return;
      await _runOne(fixture, prewarm: false);
      if (loggerDisposed) return;
      await _runOne(fixture, prewarm: true);
    }
  }

  Future<void> _copyResults() async {
    final buffer = StringBuffer('fixture\tcondition\tttffMs\terror\n');
    for (final r in _results.reversed) {
      buffer.writeln(
        '${r.fixture}\t${r.condition}\t${r.ttffMs ?? '-'}\t${r.error ?? ''}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Results table copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('3. Time-to-First-Frame')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MeasurementIntroCard(
              text: 'Measured entirely in-app — no external tooling '
                  'needed. Cold = load()+play() immediately. Prewarm = '
                  'load(), wait for ready, dwell 1s (simulated scroll '
                  'time), THEN play() — the clock starts at that play() '
                  'call, isolating the marginal cost once already '
                  'prepared. Run each fixture a few times; native/CDN '
                  'variance is real, so look at the spread, not one '
                  'sample.',
            ),
            const SizedBox(height: 16),
            if (_previewController != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: Colors.black,
                    child: MediaPlayerWidget(
                      controller: _previewController!,
                      showControls: false,
                      boxFit: BoxFit.contain,
                      backgroundColor: Colors.black,
                    ),
                  ),
                ),
              ),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_running)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Running: $_runningLabel'),
                          ],
                        ),
                      ),
                    for (final fixture in _kFixtures)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                fixture.label.toUpperCase(),
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  OutlinedButton(
                                    onPressed: _running
                                        ? null
                                        : () =>
                                            _runOne(fixture, prewarm: false),
                                    child: const Text('Run COLD'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _running
                                        ? null
                                        : () => _runOne(fixture, prewarm: true),
                                    child: const Text('Run PREWARM'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.playlist_play),
                      label: const Text(
                        'Run all fixtures (cold then prewarm, in order)',
                      ),
                      onPressed: _running ? null : _runAll,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Results (newest first)',
                      style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_all, size: 18),
                  tooltip: 'Copy results table to clipboard',
                  onPressed: _results.isEmpty ? null : _copyResults,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_results.isEmpty)
              const Text('No runs yet.')
            else
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in _results)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            r.asLine,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            MeasurementLogPanel(eventLog: eventLog),
          ],
        ),
      ),
    );
  }
}

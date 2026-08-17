import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../../data/sample_media.dart';
import '../../widgets/measurement_log_panel.dart';

/// Stage 7a measurement #1 — hardware decoder ceiling per platform.
///
/// Instantiates players **one at a time**, on a button press, each loading
/// and playing a fresh copy of the same short MP4 fixture with its own
/// [MediaController]/native player instance. A running success/failure
/// count is kept on screen; the operator watches `adb shell dumpsys
/// media.resource_manager` (Android) or Instruments (iOS) externally to see
/// actual codec allocation, since the point of this page is to find where
/// the *hardware* gives out, not where this package's own bookkeeping does.
///
/// ### Per-player outcome is revisable, not a one-shot tally
/// Field observation (Note 9P / Android 11 / MediaTek, release build):
/// players 1–15 rendered video, player 16 allocated a codec client but
/// rendered solid black, and 17–20 got no codec at all — yet this page used
/// to report `Succeeded: 20`. The reason: decoder exhaustion does not fail
/// `load()`/`play()`, it fails the *renderer*, asynchronously, and often
/// well after this page's own settle window had already closed and the
/// next attempt was spawning. So a spawn's outcome ([_Outcome]) is tracked
/// per player and stays revisable for the player's entire lifetime — the
/// `errorStream` subscription is never cancelled early. A player counted as
/// [_Outcome.succeeded] moves to [_Outcome.failed] the instant a real error
/// arrives, however late, and the failing tile carries the native error
/// code (e.g. `ERROR_CODE_DECODER_INIT_FAILED`) so the operator can see
/// why.
///
/// ### Guardrails (per the Stage 7a spec)
/// - Every spawn attempt is wrapped so a failure is caught and reported
///   inline rather than crashing the app — this is the whole point of the
///   measurement, so a crash on attempt N would destroy the very data
///   point (N-1) the operator came here to read.
/// - A hard cap of [_hardCapAttempts] total attempts prevents driving the
///   device into a hard crash even if every individual spawn silently
///   "succeeds" without the native side actually reporting a decoder
///   failure.
///
/// ### In-app vs external
/// - **In-app**: attempt count, per-attempt outcome (revised live as
///   errors arrive), and any error text/category/native error code
///   surfaced through [MediaPlayer.errorStream] or a thrown exception from
///   `initialize`/`load`/`play`.
/// - **External**: actual codec/session counts. This page cannot see
///   `MediaCodec`/`AVAssetReader` internals — only the operator's `dumpsys`
///   or Instruments reading can. `[7A-MEASURE] start:decoder-ceiling n=<n>`
///   / `end:decoder-ceiling n=<n> ...` markers bracket each attempt so the
///   two can be lined up; a `mark:decoder-ceiling
///   note=reconciled-succeeded-to-failed` line appears whenever a later
///   error flips an earlier "succeeded" reading.
class DecoderCeilingPage extends StatefulWidget {
  const DecoderCeilingPage({super.key});

  @override
  State<DecoderCeilingPage> createState() => _DecoderCeilingPageState();
}

/// Hard ceiling on total spawn attempts regardless of outcome — never
/// drive the device into a hard crash chasing a number.
const int _hardCapAttempts = 20;

/// How long to wait after `play()` before provisionally counting a spawn as
/// "succeeded" (no async error arrived via errorStream in that window).
/// This is a heuristic, not proof the decoder is healthy — the error
/// subscription stays open past this window (see [_Outcome]) precisely
/// because a real device can report the failure later than this.
const Duration _settleWindow = Duration(milliseconds: 1800);

/// Per-player outcome, tracked so it can be revised at any time during the
/// player's life rather than decided once and forgotten. See the class doc
/// above for the field defect this directly fixes.
enum _Outcome { pending, succeeded, failed }

class _SpawnRecord {
  final int index;
  final MediaController controller;
  _Outcome outcome = _Outcome.pending;
  String? error;
  String? nativeErrorCode;
  StreamSubscription<MediaPlayerException>? errorSub;

  _SpawnRecord({required this.index, required this.controller});
}

class _DecoderCeilingPageState extends State<DecoderCeilingPage>
    with MeasurementLoggerMixin {
  /// Every spawn, in attempt order, regardless of outcome. Deliberately one
  /// list rather than separate succeeded/failed lists: a record's outcome
  /// can change after it was already displayed, and filtering a single
  /// source of truth at build time (see [_succeeded]/[_failed]) means a
  /// reconciliation can never be lost by a remove-from-one/add-to-the-
  /// other step.
  final List<_SpawnRecord> _records = [];
  int _attempts = 0;
  bool _spawning = false;

  List<_SpawnRecord> get _succeeded =>
      _records.where((r) => r.outcome == _Outcome.succeeded).toList();
  List<_SpawnRecord> get _failed =>
      _records.where((r) => r.outcome == _Outcome.failed).toList();

  @override
  void initState() {
    super.initState();
    logMarker('start', 'decoder-ceiling-session');
  }

  @override
  void dispose() {
    loggerDisposed = true;
    for (final record in _records) {
      _teardown(record);
    }
    super.dispose();
  }

  void _teardown(_SpawnRecord record) {
    record.errorSub?.cancel();
    record.errorSub = null;
    try {
      record.controller.dispose();
    } catch (_) {
      // Best-effort teardown; nothing to react to on a page that is
      // already going away (or a player that is already broken).
    }
  }

  bool get _atCap => _attempts >= _hardCapAttempts;

  /// Reconciles [record] to [_Outcome.failed] the moment a real error is
  /// observed — whether that happens before the settle window elapses (the
  /// "never even provisionally succeeded" case) or long after this spawn
  /// was already shown on screen as succeeded (the Note 9P/MediaTek field
  /// case). Idempotent: the first error wins, and the subscription is torn
  /// down immediately after so a since-broken player can't keep emitting
  /// into a record that's already resolved.
  void _onPlayerError(_SpawnRecord record, MediaPlayerException err) {
    if (record.outcome == _Outcome.failed) return;
    final wasSucceeded = record.outcome == _Outcome.succeeded;
    record.outcome = _Outcome.failed;
    record.error = err.toString();
    record.nativeErrorCode = nativeErrorCodeOf(err);

    logMarker('mark', 'decoder-ceiling', {
      'n': record.index,
      'note': wasSucceeded ? 'reconciled-succeeded-to-failed' : 'failed',
      if (record.nativeErrorCode != null)
        'nativeErrorCode': record.nativeErrorCode,
      'error': record.error,
    });

    _teardown(record);
    safeSetState(() {});
  }

  Future<void> _spawnNext() async {
    if (_atCap || _spawning) return;
    setState(() => _spawning = true);

    final n = _attempts + 1;
    logMarker('start', 'decoder-ceiling', {'n': n});

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final controller = MediaController.create(
      playerId: 'decoder_ceiling_${n}_$suffix',
      config: const MediaConfig(respectSafeArea: true),
    );
    final record = _SpawnRecord(index: n, controller: controller);
    // Tracked from creation, not just once a spawn provisionally succeeds,
    // so a page dispose mid-spawn still tears this controller/subscription
    // down instead of leaking them.
    _records.add(record);

    try {
      await controller.initialize();
      // H-01: real native load failures (decoder allocation, DRM, network)
      // are commonly reported *asynchronously* after load()/play() have
      // already returned successfully. This subscription is deliberately
      // NOT cancelled after the settle window below — it stays open for
      // the record's entire lifetime, because the field defect this fix
      // addresses is exactly a decoder-exhaustion error arriving after a
      // fixed settle window had already closed.
      record.errorSub = controller.player.errorStream.listen((err) {
        _onPlayerError(record, err);
      });
      await controller.load(SampleMedia.bigBuckBunny);
      await controller.play();
      await Future.delayed(_settleWindow);
    } catch (e) {
      if (e is MediaPlayerException) {
        _onPlayerError(record, e);
      } else if (record.outcome != _Outcome.failed) {
        record.outcome = _Outcome.failed;
        record.error = e.toString();
        _teardown(record);
      }
    }

    _attempts = n;
    if (record.outcome == _Outcome.pending) {
      // No error observed within the settle window — count it
      // provisionally as succeeded. This is a heuristic, not proof of
      // health: the operator's external `dumpsys` reading is
      // authoritative, and _onPlayerError above will still flip this
      // record to failed if a late error arrives.
      record.outcome = _Outcome.succeeded;
    }

    logMarker('end', 'decoder-ceiling', {
      'n': n,
      'outcome': record.outcome.name,
      if (record.nativeErrorCode != null)
        'nativeErrorCode': record.nativeErrorCode,
      if (record.error != null) 'error': record.error,
    });

    if (_atCap) {
      logMarker('end', 'decoder-ceiling-session', {
        'attempts': _attempts,
        'succeeded': _succeeded.length,
        'failed': _failed.length,
        'reason': 'hard-cap-reached',
      });
    }

    safeSetState(() => _spawning = false);
  }

  Future<void> _reset() async {
    logMarker('mark', 'decoder-ceiling-session', {'note': 'reset'});
    final toDispose = [..._records];
    setState(() {
      _records.clear();
      _attempts = 0;
    });
    for (final record in toDispose) {
      _teardown(record);
    }
    logMarker('start', 'decoder-ceiling-session');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final succeeded = _succeeded;
    final failed = _failed;
    return Scaffold(
      appBar: AppBar(title: const Text('1. Decoder Ceiling')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MeasurementIntroCard(
              text: 'Press "Spawn next player" repeatedly. Each press '
                  'creates one new MediaController + native player, loads '
                  'the same short MP4, and plays it. A failure is caught '
                  'and reported here instead of crashing — including a '
                  'renderer failure that arrives *after* a player was '
                  'already shown as succeeded: that reconciliation happens '
                  'live, so watch for a tile moving from the live grid into '
                  '"Failed attempts" even without pressing anything. Hard '
                  'cap: $_hardCapAttempts total attempts.',
            ),
            const SizedBox(height: 12),
            const MeasurementOperatorCard(
              text: 'Android: run `adb shell dumpsys media.resource_manager '
                  '| grep -c \'Name: OMX\'` before starting, then after '
                  'every few spawns, to watch the codec-client count climb. '
                  '`adb shell dumpsys media.codec` returns nothing on some '
                  'devices (e.g. MediaTek); media.resource_manager is the '
                  'service that actually tracks and names codec clients. '
                  'iOS: use Instruments\' "VM Tracker" or the Media '
                  'template while spawning. Note the exact `n=` value at '
                  'which the external reading shows the ceiling, and '
                  'cross-check it against this page\'s own Failed count '
                  'once any tile reconciles — the two should agree.',
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attempts: $_attempts / $_hardCapAttempts   '
                      'Succeeded: ${succeeded.length}   '
                      'Failed: ${failed.length}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          icon: _spawning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: const Text('Spawn next player'),
                          onPressed: (_atCap || _spawning) ? null : _spawnNext,
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Dispose all / Reset'),
                          onPressed: _spawning ? null : _reset,
                        ),
                      ],
                    ),
                    if (_atCap)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Hard cap reached — press Reset to spawn more.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (succeeded.isNotEmpty) ...[
              Text('Live players (succeeded)',
                  style: theme.textTheme.titleSmall),
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
                itemCount: succeeded.length,
                itemBuilder: (context, i) {
                  final record = succeeded[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: MediaPlayerWidget(
                            controller: record.controller,
                            showControls: false,
                            boxFit: BoxFit.cover,
                            backgroundColor: Colors.black,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Text(
                            '${record.index}',
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
            if (failed.isNotEmpty) ...[
              Text('Failed attempts', style: theme.textTheme.titleSmall),
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
                      for (final record in failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'n=${record.index}'
                            '${record.nativeErrorCode != null ? ' [${record.nativeErrorCode}]' : ''}'
                            ': ${record.error}',
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

// Regression tests for issue #124 ("the live stall watchdog the docs ship
// cannot fire"), pinning the LiveStallWatchdog example from
// `docs/api-reference/live-streaming.md` ("Stall watchdog for live streams")
// as an executable artifact rather than an aspirational snippet.
//
// The class below this comment is a VERBATIM copy of that documented example
// (minus its two import lines, which this file supplies in its own header).
// If you edit one, edit the other.
//
// ---------------------------------------------------------------------------
// What was wrong, and why nothing caught it
// ---------------------------------------------------------------------------
// The previous version of the documented watchdog could not fire at all for a
// real stall, on either platform:
//
//   * Its first guard was `if (controller.state.state != PlayerState.playing)
//     { _reset(); return; }`. A rebuffer is reported as
//     `PlayerState.buffering` on BOTH platforms (Kotlin
//     `Player.STATE_BUFFERING -> "buffering"`; Swift
//     `.waitingToPlayAtSpecifiedRate` and `AVPlayerItemPlaybackStalled` ->
//     `"buffering"`), so the moment either platform noticed the stall the
//     watchdog took the `_reset()` branch — which also zeroed its escalation
//     level, discarding everything it had accumulated.
//   * It judged liveness solely from `liveEdgeOffset`, on the documented
//     premise that a frozen playhead grows that value "without bound, on both
//     platforms". That is true on Android only. On iOS both
//     `notifyPositionChanged` call sites in `MediaPlayerManager.swift`, and
//     the `liveEdgeOffsetMs` computation itself, live inside
//     `addPeriodicTimeObserver(forInterval: 0.5s)`'s block, and that observer
//     only fires while time is progressing. During a hard stall on iOS the
//     offset is never sampled: it freezes at its last value instead of
//     growing.
//   * It short-circuited on `if (controller.isAtLiveEdge) return false;`,
//     which is a no-op for any threshold >= the 15s
//     `defaultLiveEdgeTolerance` and actively suppresses real escalations for
//     the tighter threshold a low-latency stream wants.
//
// **Mocking is exactly how this survived.** Every test in this package mocks
// the MethodChannel, and the existing issue-#88 coverage
// (`test/core/media_player_live_edge_test.dart`, "a frozen playhead shows a
// growing offset and leaves the live edge") simulates a frozen playhead by
// emitting a stream of `onPositionChanged` events carrying a CONSTANT
// `position` and a GROWING `liveEdgeOffset`. That sequence is faithful to
// Android and is a sequence no real iOS device will ever produce — on iOS a
// frozen playhead produces no events at all. A mock can emit any wire
// sequence, including impossible ones, so a test suite built entirely on
// mocks can only ever check the claims someone thought to encode. These tests
// encode the iOS sequence (silence) explicitly for that reason.
//
// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------
// Native events are injected through
// `TestDefaultBinaryMessenger.handlePlatformMessage`, matching
// `test/core/media_player_events_test.dart` and
// `test/core/media_player_live_edge_test.dart`. Time is driven by `fakeAsync`
// so the 2s sampler and the ~500ms native tick are deterministic and the
// suite stays fast.
//
// `loadTimeout: null` on every controller here: the Dart-side load watchdog
// would otherwise synthesize a `PlayerState.error` at 30s of elapsed fake
// time in exactly the scenario these tests construct (buffering, position not
// advancing), which is a different mechanism from the one under test.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ===========================================================================
// VERBATIM COPY of the `LiveStallWatchdog` example in
// docs/api-reference/live-streaming.md — do not "improve" it here without
// making the same edit there.
// ===========================================================================

/// Escalating stall watchdog that is correct for VOD, live-without-DVR and
/// live-with-DVR alike, on both Android and iOS, because it branches on what
/// the player reports rather than on the app's own config — and because it
/// carries three independent stall signals rather than trusting any one of
/// them to cover every platform.
class LiveStallWatchdog {
  LiveStallWatchdog(
    this.controller, {
    required this.onEscalate,
    this.samplingInterval = const Duration(seconds: 2),
    this.liveEdgeStallThreshold = const Duration(seconds: 45),
  });

  final MediaController controller;
  final void Function(int level) onEscalate;

  /// How often the sampler runs. Every "how many samples" constant below is
  /// expressed in multiples of this.
  final Duration samplingInterval;

  /// Signal 1: escalate once the playhead has fallen this far behind the
  /// live edge.
  ///
  /// Calibrate this against **Android**, where a standard (non-low-latency)
  /// HLS/DASH stream sits 15-30s behind the edge when perfectly healthy. On
  /// iOS `liveEdgeOffset` is pinned under a second during live playback
  /// (issue #120), so this branch effectively never fires there and signals
  /// 2 and 3 carry that platform. Tighten it freely for low-latency streams:
  /// nothing here is clamped to `PlaybackState.defaultLiveEdgeTolerance`.
  final Duration liveEdgeStallThreshold;

  /// Signal 2: how many consecutive samples `position` may repeat, on an
  /// absolute basis, before we call it a stall. 6 x 2s = 12s of no progress.
  static const _absoluteStallSamples = 6;

  /// Signal 3: how many consecutive samples may pass with no native
  /// `onPositionChanged` at all. 3 x 2s = 6s, comfortably longer than the
  /// ~500ms tick both platforms emit while playing.
  static const _silentSamples = 3;

  Timer? _timer;
  StreamSubscription<Duration>? _positionEvents;
  Duration? _lastPosition;
  int _repeats = 0;
  int _silentStreak = 0;
  bool _sawPositionEvent = false;
  int _level = 0;

  void start() {
    stop();
    // Subscribe to the RAW native tick, not to MediaController's change
    // notifications: the controller throttles position-only updates to one
    // per 500ms and drops the rest, and "did an event arrive at all" is
    // exactly the question a throttle can silently answer wrong.
    _positionEvents = controller.player.positionStream.listen((_) {
      _sawPositionEvent = true;
    });
    _timer = Timer.periodic(samplingInterval, (_) => _sample());
  }

  void _sample() {
    // Judge liveness only while the host still INTENDS to play. `buffering`
    // must count: a rebuffer is reported as PlayerState.buffering on both
    // platforms, so treating only `playing` as live would disarm the
    // watchdog at the exact moment a stall starts — and reset the escalation
    // level with it. A user pause, an idle/completed player and a reported
    // error are genuinely not stalls.
    final state = controller.state.state;
    final intendsToPlay =
        state == PlayerState.playing || state == PlayerState.buffering;
    if (!intendsToPlay) {
      _reset();
      return;
    }

    // Signal 3's bookkeeping. This streak is cleared here, by an event
    // actually having arrived, and nowhere else — deliberately not by the
    // "not stalled" path below. Folding it into a general reset would clear
    // it on every healthy-looking sample, and a staleness counter that is
    // zeroed every time it fails to reach its own threshold can never reach
    // it.
    final sawEvent = _sawPositionEvent;
    _sawPositionEvent = false;
    if (sawEvent) {
      _silentStreak = 0;
    } else {
      _silentStreak++;
    }

    // Signal 3 is checked first: it is the only one that can fire once the
    // platform has stopped talking, and when it fires the other two are
    // reading values frozen at their last sample by definition.
    final stalled = _silentStreak >= _silentSamples ||
        (controller.positionBasis == PositionBasis.liveWindow
            ? _liveWindowStalled()
            : _absoluteStalled());

    if (!stalled) {
      // Only the escalation level unwinds here. `_repeats`/`_lastPosition`
      // are owned by _absoluteStalled(), and `_silentStreak` by the block
      // above.
      _level = 0;
      return;
    }

    _level++;
    onEscalate(_level);
  }

  /// Signal 1. On a sliding window `position` is expected to be constant, so
  /// judge on the distance from the live edge instead.
  bool _liveWindowStalled() {
    final offset = controller.liveEdgeOffset;

    // The platform cannot answer yet (playlist just loaded, or an older
    // cached native build). Fall back to the position-repeat heuristic
    // rather than guessing — it is weak on this basis, so it is only ever
    // reached when there is genuinely nothing better.
    if (offset == null) return _absoluteStalled();

    // There is deliberately NO `if (controller.isAtLiveEdge) return false;`
    // short-circuit here, and adding one back would be a regression.
    // `isAtLiveEdge` is `offset <= PlaybackState.defaultLiveEdgeTolerance`
    // (15s), so for any threshold >= 15s the comparison below already
    // subsumes it — and for a threshold tightened below 15s, which
    // low-latency streams want, it would silently suppress every real
    // escalation in the band between the threshold and 15s.
    return offset > liveEdgeStallThreshold;
  }

  /// Signal 2. On an absolute basis (VOD, and live-without-DVR on iOS), a
  /// position that stops advancing really is a stall.
  bool _absoluteStalled() {
    final position = controller.position;
    if (position == _lastPosition) {
      _repeats++;
    } else {
      _lastPosition = position;
      _repeats = 0;
    }
    return _repeats >= _absoluteStallSamples;
  }

  /// Full reset: only for "the host is not trying to play" and [stop]. See
  /// _sample() for why the not-stalled path deliberately does less.
  void _reset() {
    _lastPosition = controller.position;
    _repeats = 0;
    _silentStreak = 0;
    _level = 0;
  }

  /// Stops sampling and releases the position subscription. Safe to call
  /// repeatedly, and safe to [start] again afterwards.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _positionEvents?.cancel();
    _positionEvents = null;
    _sawPositionEvent = false;
    _reset();
  }

  void dispose() => stop();
}
// ===========================================================================
// End of verbatim copy.
// ===========================================================================

const _channel = MethodChannel('zmedia_player');

const _liveItem = MediaItem(
  id: 'live',
  title: 'Live',
  url: 'https://cdn.example.com/live.m3u8',
  isLive: true,
);

const _vodItem = MediaItem(
  id: 'vod',
  title: 'VOD',
  url: 'https://cdn.example.com/movie.mp4',
);

/// Fires a native->Dart event at the plugin's channel and lets the async
/// handler settle inside [async]'s zone.
void _inject(FakeAsync async, String method, Map<String, dynamic> arguments) {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_channel.name, data, (ByteData? reply) {});
  async.flushMicrotasks();
}

void _injectState(FakeAsync async, String playerId, String state) {
  _inject(async, 'onStateChanged', {
    'playerId': playerId,
    'state': state,
  });
}

void _injectPosition(
  FakeAsync async,
  String playerId, {
  required int positionMs,
  required String basis,
  int? liveEdgeOffsetMs,
}) {
  _inject(async, 'onPositionChanged', {
    'playerId': playerId,
    'position': positionMs,
    'positionBasis': basis,
    if (liveEdgeOffsetMs != null) 'liveEdgeOffset': liveEdgeOffsetMs,
  });
}

/// Builds a controller wired to the mocked channel, already carrying [item].
MediaController _controllerFor(
  FakeAsync async,
  String playerId,
  MediaItem item, {
  MediaConfig config = const MediaConfig(loadTimeout: null),
}) {
  final controller = MediaController.create(playerId: playerId, config: config);
  controller.player.initialize();
  async.flushMicrotasks();
  controller.load(item);
  async.flushMicrotasks();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('iOS hard stall (the regression lock)', () {
    test(
        'silence while the player reports buffering escalates, even though '
        'liveEdgeOffset never grows', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(async, 'wd_ios_hard', _liveItem);
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
        )..start();

        // Healthy live playback first, so the watchdog has a clean baseline
        // and we know the escalation below is not an artifact of never having
        // seen an event.
        _injectState(async, 'wd_ios_hard', 'playing');
        for (var i = 0; i < 8; i++) {
          _injectPosition(
            async,
            'wd_ios_hard',
            positionMs: 120000,
            basis: 'liveWindow',
            liveEdgeOffsetMs: 400 + i, // iOS: pinned under a second.
          );
          async.elapse(const Duration(milliseconds: 500));
        }
        expect(escalations, isEmpty,
            reason: 'healthy iOS live playback must not escalate');

        // The stall. iOS reports `buffering` (via
        // `.waitingToPlayAtSpecifiedRate` / `AVPlayerItemPlaybackStalled`) and
        // then emits NOTHING: `addPeriodicTimeObserver` stops firing, so no
        // position, no positionBasis and no liveEdgeOffset. The last known
        // offset stays at ~400ms forever.
        _injectState(async, 'wd_ios_hard', 'buffering');
        async.elapse(const Duration(seconds: 10));

        expect(escalations, isNotEmpty,
            reason: 'event staleness is the ONLY signal available for an iOS '
                'hard stall — the offset is frozen, not growing, and the '
                'state is buffering rather than playing');
        expect(escalations.first, 1);
        expect(controller.liveEdgeOffset!.inSeconds, 0,
            reason: 'the frozen offset is still well inside the 15s '
                'tolerance — nothing about it says "stalled"');
        expect(controller.isAtLiveEdge, isTrue,
            reason: 'and isAtLiveEdge still reads true, which is exactly why '
                'the watchdog must not consult it');

        watchdog.stop();
        controller.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('Android rebuffer', () {
    test('a growing offset while buffering escalates', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(
            async, 'wd_android_rebuffer', _liveItem,
            config: const MediaConfig(
                loadTimeout: null, hlsConfig: HlsConfig(enableDvr: true)));
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
        )..start();

        _injectState(async, 'wd_android_rebuffer', 'playing');
        for (var i = 0; i < 8; i++) {
          _injectPosition(
            async,
            'wd_android_rebuffer',
            positionMs: 120000,
            basis: 'liveWindow',
            liveEdgeOffsetMs: 18000 + (i.isEven ? 400 : -400),
          );
          async.elapse(const Duration(milliseconds: 500));
        }
        expect(escalations, isEmpty,
            reason: 'a stable ~18s offset is healthy Android live playback');

        // Android keeps emitting position events through a rebuffer
        // (`playWhenReady && STATE_BUFFERING`), with a constant window-relative
        // position and a growing offset.
        _injectState(async, 'wd_android_rebuffer', 'buffering');
        // 500ms of wall time lost per 500ms tick: the playhead is frozen and
        // the edge keeps moving, so the offset grows 1:1 with elapsed time.
        for (var i = 1; i <= 80; i++) {
          _injectPosition(
            async,
            'wd_android_rebuffer',
            positionMs: 120000,
            basis: 'liveWindow',
            liveEdgeOffsetMs: 18000 + i * 500,
          );
          async.elapse(const Duration(milliseconds: 500));
        }

        expect(escalations, isNotEmpty,
            reason: 'the offset passed the 45s threshold while the player was '
                'reporting buffering — the state guard must not disarm here');
        expect(escalations.first, 1);
        expect(controller.liveEdgeOffset!,
            greaterThan(const Duration(seconds: 45)));

        watchdog.stop();
        controller.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('Healthy live edge', () {
    test(
        'a constant position with the offset oscillating 15-30s never '
        'escalates', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(async, 'wd_healthy', _liveItem,
            config: const MediaConfig(
                loadTimeout: null, hlsConfig: HlsConfig(enableDvr: true)));
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
        )..start();

        _injectState(async, 'wd_healthy', 'playing');

        // 120 ticks x 500ms = 60s of fake time, 30 sampler runs.
        const offsets = <int>[15200, 22000, 29800, 18400, 26100];
        for (var i = 0; i < 120; i++) {
          _injectPosition(
            async,
            'wd_healthy',
            // The whole point: on a sliding window the playhead and the
            // window start advance together, so this never changes.
            positionMs: 300000,
            basis: 'liveWindow',
            liveEdgeOffsetMs: offsets[i % offsets.length],
          );
          async.elapse(const Duration(milliseconds: 500));
        }

        expect(escalations, isEmpty,
            reason: 'a constant position at a bounded offset is healthy live '
                'playback, and the naive position-sampling watchdog this '
                'example replaces escalated ~30 times here');

        watchdog.stop();
        controller.dispose();
        async.flushMicrotasks();
      });
    });

    test('VOD advancing normally never escalates', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(async, 'wd_vod', _vodItem);
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
        )..start();

        _injectState(async, 'wd_vod', 'playing');
        for (var i = 1; i <= 60; i++) {
          _injectPosition(
            async,
            'wd_vod',
            positionMs: i * 500,
            basis: 'absolute',
          );
          async.elapse(const Duration(milliseconds: 500));
        }

        expect(escalations, isEmpty);

        watchdog.stop();
        controller.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('Low-latency threshold', () {
    test(
        'an offset held between a tightened threshold and the 15s tolerance '
        'still escalates', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(async, 'wd_lowlatency', _liveItem,
            config: const MediaConfig(
                loadTimeout: null, hlsConfig: HlsConfig(enableDvr: true)));
        // LL-HLS: 4s is a real stall for this stream, and 4s < the 15s
        // `defaultLiveEdgeTolerance`. The example's docs explicitly invite
        // this, which is why the `isAtLiveEdge` short-circuit had to go.
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
          liveEdgeStallThreshold: const Duration(seconds: 4),
        )..start();

        _injectState(async, 'wd_lowlatency', 'playing');
        for (var i = 0; i < 40; i++) {
          _injectPosition(
            async,
            'wd_lowlatency',
            positionMs: 90000,
            basis: 'liveWindow',
            // Squarely in the dead band: past the 4s threshold, inside the
            // 15s tolerance, so `isAtLiveEdge` is true the whole time.
            liveEdgeOffsetMs: 9000 + (i.isEven ? 50 : -50),
          );
          async.elapse(const Duration(milliseconds: 500));
        }

        expect(controller.isAtLiveEdge, isTrue,
            reason: 'the premise of the test: a 9s offset is "at the live '
                'edge" by the 15s default tolerance');
        expect(escalations, isNotEmpty,
            reason: 'but it is 5s past the threshold this caller configured, '
                'and a short-circuit on isAtLiveEdge would swallow it');
        expect(escalations.first, 1);

        watchdog.stop();
        controller.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('User pause', () {
    test('a paused player emitting nothing never escalates', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(async, 'wd_paused', _liveItem);
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
        )..start();

        _injectState(async, 'wd_paused', 'playing');
        for (var i = 0; i < 8; i++) {
          _injectPosition(
            async,
            'wd_paused',
            positionMs: 60000,
            basis: 'liveWindow',
            liveEdgeOffsetMs: 6000,
          );
          async.elapse(const Duration(milliseconds: 500));
        }

        // The viewer pauses. Both platforms go silent; neither is stalled.
        _injectState(async, 'wd_paused', 'paused');
        async.elapse(const Duration(minutes: 2));

        expect(escalations, isEmpty,
            reason: 'silence while paused is silence, not a stall — the '
                'staleness signal is gated on the host still intending to '
                'play');

        watchdog.stop();
        controller.dispose();
        async.flushMicrotasks();
      });
    });

    test('an idle player emitting nothing never escalates', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(async, 'wd_idle', _liveItem);
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
        )..start();

        _injectState(async, 'wd_idle', 'idle');
        async.elapse(const Duration(minutes: 2));

        expect(escalations, isEmpty);

        watchdog.stop();
        controller.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('Lifecycle', () {
    test('stop() cancels both the sampler and the position subscription', () {
      fakeAsync((async) {
        final escalations = <int>[];
        final controller = _controllerFor(async, 'wd_stop', _liveItem);
        final watchdog = LiveStallWatchdog(
          controller,
          onEscalate: escalations.add,
        )..start();

        _injectState(async, 'wd_stop', 'buffering');
        watchdog.stop();

        // Nothing may fire after stop(), however long we wait or how many
        // events arrive.
        async.elapse(const Duration(minutes: 5));
        _injectPosition(async, 'wd_stop',
            positionMs: 1000, basis: 'liveWindow', liveEdgeOffsetMs: 600000);
        async.elapse(const Duration(minutes: 5));

        expect(escalations, isEmpty);

        // And it is safe to restart.
        watchdog.start();
        async.elapse(const Duration(seconds: 10));
        expect(escalations, isNotEmpty,
            reason: 'start() after stop() must re-arm both the sampler and '
                'the position subscription');

        watchdog.dispose();
        controller.dispose();
        async.flushMicrotasks();
      });
    });
  });
}

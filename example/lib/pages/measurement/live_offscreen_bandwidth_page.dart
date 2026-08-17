import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../../data/sample_media.dart';
import '../../widgets/measurement_log_panel.dart';

/// Stage 7a measurement #5 — does an off-screen *paused* live stream keep
/// consuming bandwidth?
///
/// F-04's concern, stated plainly in the plan: live is not VOD. Pausing an
/// off-screen live stream does not stop drift, does not release the
/// session, and does not reliably stop bandwidth the way pausing a VOD
/// item does. This page creates the condition — a live [MediaListPlayer]
/// that gets auto-paused by scrolling it off-screen (today's actual Phase
/// 4 behavior, unmodified) — and holds it there so the operator can watch
/// bandwidth externally. The outcome decides whether Stage 7d's live
/// policy must be stop-and-release-with-rejoin rather than plain pause.
///
/// ### Layout
/// The live player sits at the top of a scroll view above a large empty
/// spacer. Scrolling down moves the player below the visibility threshold,
/// which triggers [MediaListPlayer]'s existing off-screen `pause()` — the
/// same mechanism `feed_page.dart` exercises for VOD, applied here to a
/// stream with `isLive: true`.
///
/// ### In-app vs external
/// In-app: live `state`/`isPlaying` readout, and `[7A-MEASURE]
/// start:live-offscreen-pause` / `mark:live-offscreen-pause
/// note=scrolled-offscreen` / `end:live-offscreen-pause holdSeconds=N`
/// markers bracketing the hold window. External: actual bytes-on-the-wire
/// during that window, via Android Studio's Network Profiler / `adb shell
/// cat /proc/net/dev` sampled before and after, or Instruments' Network
/// template on iOS.
///
/// A near-zero bandwidth reading proves F-04's "held-but-still-pulling-
/// data" concern only if the player is actually still alive; a player that
/// silently died (network drop, DRM, decoder) would produce the exact same
/// near-zero reading for an unrelated reason. This page therefore keeps an
/// `errorStream` subscription open for its whole lifetime and surfaces any
/// error — with native error code where available — both in the event log
/// and directly on the readout card, so that ambiguity can't hide inside a
/// clean-looking result.
class LiveOffscreenBandwidthPage extends StatefulWidget {
  const LiveOffscreenBandwidthPage({super.key});

  @override
  State<LiveOffscreenBandwidthPage> createState() =>
      _LiveOffscreenBandwidthPageState();
}

class _LiveOffscreenBandwidthPageState extends State<LiveOffscreenBandwidthPage>
    with MeasurementLoggerMixin {
  late final MediaController _controller;
  StreamSubscription<MediaPlayerException>? _errorSub;
  bool _visible = true;
  bool _holding = false;
  DateTime? _invisibleSince;
  Timer? _tickTimer;
  String? _lastError;
  String? _lastErrorCode;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'live_offscreen_${DateTime.now().microsecondsSinceEpoch}',
      config: const MediaConfig(respectSafeArea: true),
    );
    unawaited(_init());
  }

  Future<void> _init() async {
    logMarker('start', 'live-offscreen-pause');
    try {
      await _controller.initialize();
      // A near-zero bandwidth reading during the hold window would look
      // exactly like the "release confirms F-04" result this measurement
      // is designed to catch — unless the player actually died (network
      // drop, DRM, decoder) partway through and simply stopped pulling
      // data for an unrelated reason. This subscription stays open for
      // the whole page lifetime so that possibility is ruled out, not
      // silently mistaken for the real result.
      _errorSub = _controller.player.errorStream.listen((err) {
        _lastError = err.toString();
        _lastErrorCode = nativeErrorCodeOf(err);
        logMarker('mark', 'live-offscreen-pause', {
          'note': 'player-error',
          if (_lastErrorCode != null) 'nativeErrorCode': _lastErrorCode,
          'error': _lastError,
        });
        safeSetState(() {});
      });
      await _controller.load(SampleMedia.hlsLiveStream);
      await _controller.play();
      log('[LIVE-BW] loaded + playing playerId=${_controller.playerId}');
    } catch (e) {
      log('[LIVE-BW] INIT ERROR: $e');
    }
    safeSetState(() {});
  }

  void _onVisible() {
    // `VisibilityDetector` callbacks are scheduled from a compositor
    // frame callback and are not synchronously tied to element lifecycle
    // -- one scheduled just before unmount can still fire after `dispose()`
    // has already run. Bail out immediately rather than touching any
    // field below (see `_onInvisible` for why that matters more there).
    if (loggerDisposed) return;
    _visible = true;
    _invisibleSince = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    if (_holding) {
      _holding = false;
    }
    log('[LIVE-BW] event=visible state=${_controller.state.state.name} '
        'isPlaying=${_controller.isPlaying}');
    safeSetState(() {});
  }

  void _onInvisible() {
    // Same lingering-callback-after-dispose race as `_onVisible` above --
    // critical here specifically because, unlike `_onVisible`, this method
    // unconditionally creates a new `Timer.periodic`. Without this guard,
    // a callback that fires after `dispose()` already ran (and already
    // cancelled whatever `_tickTimer` existed at that point) creates a
    // fresh timer that nothing will ever cancel -- a real leak, and
    // exactly the kind of thing `flutter_test`'s "Timer still pending
    // after dispose" invariant check catches.
    if (loggerDisposed) return;
    _visible = false;
    _invisibleSince = DateTime.now();
    logMarker('mark', 'live-offscreen-pause', {
      'note': 'scrolled-offscreen',
      'stateAfterAutoPause': _controller.state.state.name,
      'isPlaying': _controller.isPlaying,
    });
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (loggerDisposed || !mounted) return;
      setState(() {});
    });
    safeSetState(() {});
  }

  int get _secondsInvisible {
    final since = _invisibleSince;
    if (since == null) return 0;
    return DateTime.now().difference(since).inSeconds;
  }

  void _startHold() {
    if (_visible) {
      log('[LIVE-BW] cannot start hold: player is still visible — scroll '
          'it off-screen first');
      return;
    }
    setState(() => _holding = true);
    logMarker('mark', 'live-offscreen-pause', {'note': 'hold-started'});
  }

  void _endHold() {
    final held = _secondsInvisible;
    logMarker('end', 'live-offscreen-pause', {
      'holdSeconds': held,
      'stateNow': _controller.state.state.name,
      'isPlaying': _controller.isPlaying,
    });
    setState(() => _holding = false);
  }

  Future<void> _forcePause() async {
    await _controller.pause();
    log('[LIVE-BW] MANUAL pause() -> state=${_controller.state.state.name}');
    safeSetState(() {});
  }

  Future<void> _forcePlay() async {
    await _controller.play();
    log('[LIVE-BW] MANUAL play() -> state=${_controller.state.state.name}');
    safeSetState(() {});
  }

  @override
  void dispose() {
    loggerDisposed = true;
    _tickTimer?.cancel();
    _errorSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('5. Live Off-Screen Bandwidth')),
      // Pinned rather than inline in the scroll body: "Start hold" is only
      // ever pressed once the player above has been scrolled off-screen,
      // which (with the two 400dp spacers further down) can push these
      // buttons uncomfortably close to — or, on a real device with
      // different safe-area insets/font scale than tested here, past — the
      // bottom edge if they scroll with the rest of the content. Matches
      // the same pinned-bottom-bar convention applied to measurement 4's
      // action buttons for the same reachability guarantee.
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
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Start hold'),
                  onPressed: (_visible || _holding) ? null : _startHold,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('End hold'),
                  onPressed: _holding ? _endHold : null,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.pause),
                  label: const Text('Force pause'),
                  onPressed: _forcePause,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Force play'),
                  onPressed: _forcePlay,
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: MeasurementIntroCard(
                text: 'The live player below auto-plays on load. Scroll '
                    'down past the spacer to move it off-screen — '
                    'MediaListPlayer\'s existing off-screen-pause fires '
                    'automatically (same mechanism feed_page.dart '
                    'exercises for VOD), currently reporting '
                    'visible=$_visible. Once it fires, press "Start hold", '
                    'wait (default guidance: 60s), read bandwidth '
                    'externally, then press "End hold". Compare against a '
                    'baseline reading taken while nothing is playing at '
                    'all.',
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MediaListPlayer(
                  controller: _controller,
                  config: const MediaListPlayerConfig(
                    // Single item on this page — no coordination with other
                    // MediaListPlayers needed.
                    pauseOthersOnPlay: false,
                  ),
                  aspectRatio: 16 / 9,
                  onVisible: _onVisible,
                  onInvisible: _onInvisible,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'visible=$_visible   '
                            'state=${_controller.state.state.name}   '
                            'isPlaying=${_controller.isPlaying}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (!_visible)
                            Text(
                              'Off-screen for: ${_secondsInvisible}s',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (_lastError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Player error observed'
                                '${_lastErrorCode != null ? ' [$_lastErrorCode]' : ''} '
                                '— any bandwidth reading taken after this '
                                'point is unreliable: $_lastError',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const MeasurementOperatorCard(
              text: 'Take a baseline bandwidth reading with nothing '
                  'playing first. Then: play (visible) -> scroll off-screen '
                  '-> "Start hold" -> wait ~60s -> read bandwidth '
                  '(`adb shell cat /proc/net/dev`, Network Profiler, or '
                  'Instruments) -> "End hold". Compare the held reading '
                  'against the baseline: any sustained non-zero delta means '
                  'a paused-but-not-released live session is still pulling '
                  'data, which is exactly what F-04 needs decided.',
            ),
            const SizedBox(height: 400),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Keep scrolling — this spacer exists so the player above '
                'can actually leave the visibility threshold.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 400),
            Padding(
              padding: const EdgeInsets.all(12),
              child: MeasurementLogPanel(eventLog: eventLog),
            ),
          ],
        ),
      ),
    );
  }
}

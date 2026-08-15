import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';

/// Manual regression harness for two Phase 1 fixes that only manifest with
/// **two or more concurrently live players**. No other example page creates
/// more than one [MediaController] at a time, which is exactly why these
/// bugs shipped unnoticed — this page exists to close that gap.
///
/// ### B-02 — cross-instance notification observers (iOS)
/// Before the fix, `MediaPlayerManager.swift` registered
/// `AVPlayerItemDidPlayToEndTime` / `AVPlayerItemFailedToPlayToEndTime` with
/// `object: nil` and a handler that took no `Notification` argument, so it
/// could not filter by item. One player's item finishing marked *every*
/// live player `completed`, and one item's failure surfaced as an error on
/// unrelated players. The fix filters on
/// `notification.object as? AVPlayerItem === avPlayer?.currentItem`.
///
/// ### H-07 — Now Playing / remote command ownership (iOS)
/// Before the fix, every `NotificationHandler` registered targets on the
/// process-wide `MPRemoteCommandCenter.shared()` and
/// `MPNowPlayingInfoCenter.default()`, so commands double-fired, and
/// disposing any player called `removeTarget(nil)` and cleared
/// `nowPlayingInfo` — killing the lock screen for a still-playing sibling.
/// The fix adds explicit last-writer-wins ownership with handoff on
/// dispose.
///
/// ### How to read the results
/// Every meaningful state change for both players (and every scripted
/// step) is printed to the console with the `[MP-TEST]` prefix. Grep for
/// that prefix on the device console:
///
/// ```
/// [MP-TEST] A id=player_... state=playing isPlaying=true
/// [MP-TEST] B id=player_... state=idle isPlaying=false
/// [MP-TEST] STEP 3: waiting for A to reach completed (timeout 45s)
/// [MP-TEST] VERDICT B-02: PASS (A=completed, B=ready)
/// [MP-TEST] VERDICT H-07-DART: B controller alive=true state=ready. ...
/// ```
///
/// On page load, a scripted scenario runs unattended (see `_runScenario`):
/// it first plays A to completion and asserts B is unaffected (B-02).
/// **It then stops short of disposing anything.** A is restarted (seek to
/// zero + play) since its clip already completed, B is started playing,
/// and lock-screen notifications are initialized for A then B — B last, so
/// B is the expected owner of the shared Now Playing session under
/// last-writer-wins. Once both A and B are confirmed playing, the script
/// prints operator instructions and **stops** — it never disposes either
/// player automatically. This is deliberate: auto-disposing A (as an
/// earlier version of this harness did) permanently killed the only live
/// sibling B could hand ownership to, making the `.handedOff(to:)` path
/// impossible to exercise in the same run as the `.notOwner` path.
///
/// From that steady state (A and B both alive and playing, B is the
/// expected owner) the operator picks **one** of two checks by hand:
///
/// - **Check 1 (`.notOwner`)** — press "Dispose A" (the non-owner), then
///   confirm on the lock screen that player **B**'s Now Playing info and
///   transport controls still work.
/// - **Check 2 (`.handedOff(to:)`)** — press "Dispose OWNER (B)", then
///   confirm on the lock screen that ownership handed off to player **A**
///   and its transport controls now work.
///
/// Dart has no public API to introspect `MPNowPlayingInfoCenter` /
/// `MPRemoteCommandCenter` ownership, so the `VERDICT H-07-DART*` lines
/// printed here are informational only — **the authoritative H-07 check is
/// always the lock screen**. Both checks are only meaningful while the
/// *surviving* player is genuinely playing at the moment of disposal; a
/// loud warning is logged if that invariant does not hold. Because A's
/// clip is short (~10s), it is auto-restarted (seek to zero + play)
/// whenever it completes on its own after STEP 5, so it keeps playing
/// while the operator decides which check to run — see `_armAutoLoopA`.
///
/// Since a check disposes one of the two players, only one check can be
/// performed per scripted run. The "Reset / re-run scenario" button fully
/// tears down both players and notification services, recreates them with
/// fresh player IDs, and re-runs the scripted setup, so the operator can
/// perform Check 1, reset, then perform Check 2 without relaunching the
/// app.
///
/// Manual buttons (Play A, Play B, Pause, Dispose A, Dispose B, Dispose
/// OWNER (B), Reset / re-run scenario) are also provided so the operator
/// can drive further lock-screen checks by hand.
class MultiPlayerPage extends StatefulWidget {
  const MultiPlayerPage({super.key});

  @override
  State<MultiPlayerPage> createState() => _MultiPlayerPageState();
}

class _MultiPlayerPageState extends State<MultiPlayerPage> {
  // Not `final`: `_resetScenario` tears these down and rebuilds fresh
  // instances (with fresh player IDs) so the operator can re-run the
  // scripted scenario without relaunching the app.
  late MediaController _controllerA;
  late MediaController _controllerB;
  late NotificationService _notifA;
  late NotificationService _notifB;

  StreamSubscription<NotificationActionEvent>? _actionSubA;
  StreamSubscription<NotificationActionEvent>? _actionSubB;

  PlayerState? _lastLoggedA;
  PlayerState? _lastLoggedB;

  bool _aDisposed = false;
  bool _bDisposed = false;
  bool _notificationsInitialized = false;
  bool _scenarioRunning = true;
  bool _resetInProgress = false;
  String? _scenarioError;

  // Guards the "keep A playing" auto-restart installed after the B-02
  // check (see `_armAutoLoopA`/`_onACompletionGuard`). Cleared up-front
  // (synchronously, before any `await`) whenever A is about to be
  // disposed or torn down for a reset, so a completion event that fires
  // concurrently with disposal can never race a `play()`/`seekTo()` call
  // against a disposed controller.
  bool _aAutoLoopEnabled = false;
  bool _aRestartInFlight = false;

  final List<String> _eventLog = [];

  @override
  void initState() {
    super.initState();
    _createFreshPlayers();
    unawaited(_runScenario());
  }

  /// Creates brand-new controllers/notification services with fresh,
  /// unique player IDs and wires up the logging listeners. Used both on
  /// initial page load and by `_resetScenario` after tearing the old ones
  /// down.
  void _createFreshPlayers() {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    _controllerA = MediaController.create(
      playerId: 'multi_test_a_$suffix',
      config: const MediaConfig(respectSafeArea: true),
    );
    _controllerB = MediaController.create(
      playerId: 'multi_test_b_$suffix',
      config: const MediaConfig(respectSafeArea: true),
    );
    _notifA = NotificationService(_notificationConfig('A'));
    _notifB = NotificationService(_notificationConfig('B'));

    _controllerA.addListener(_onAChanged);
    _controllerB.addListener(_onBChanged);
  }

  NotificationConfig _notificationConfig(String label) {
    return NotificationConfig(
      enabled: true,
      channelId: 'zmedia_multi_test_$label',
      channelName: 'ZMedia Multi Test $label',
      channelDescription: 'Multi-player regression harness ($label)',
      showPlayPause: true,
      showNext: false,
      showPrevious: false,
      showStop: false,
      showSeekForward: false,
      showSeekBackward: false,
      showWhenPaused: true,
      priority: NotificationPriority.high,
    );
  }

  // ---------------------------------------------------------------------
  // [MP-TEST] logging
  // ---------------------------------------------------------------------

  /// Prints a single `[MP-TEST]` line and mirrors it into the on-screen log.
  void _log(String message) {
    final line = '[MP-TEST] $message';
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      _eventLog.insert(0, message);
      if (_eventLog.length > 40) _eventLog.removeLast();
    });
  }

  /// Prints the exact required state line for [label]'s controller:
  /// `[MP-TEST] <label> id=<playerId> state=<state> isPlaying=<bool>`
  void _logSnapshot(String label, MediaController controller) {
    _log(
      '$label id=${controller.playerId} '
      'state=${controller.state.state.name} '
      'isPlaying=${controller.isPlaying}',
    );
  }

  void _onAChanged() {
    final current = _controllerA.state.state;
    if (_lastLoggedA == current) return;
    _lastLoggedA = current;
    _logSnapshot('A', _controllerA);
  }

  void _onBChanged() {
    final current = _controllerB.state.state;
    if (_lastLoggedB == current) return;
    _lastLoggedB = current;
    _logSnapshot('B', _controllerB);
  }

  /// Waits until [controller] reaches [target] or [timeout] elapses.
  /// Returns true if the target state was observed in time.
  Future<bool> _waitForState(
    MediaController controller,
    PlayerState target,
    Duration timeout,
  ) async {
    if (controller.state.state == target) return true;
    final completer = Completer<bool>();
    void listener() {
      if (controller.state.state == target && !completer.isCompleted) {
        completer.complete(true);
      }
    }

    controller.addListener(listener);
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      controller.removeListener(listener);
    }
  }

  // ---------------------------------------------------------------------
  // "Keep A playing" -- A's clip is short (~10s), and after the scripted
  // setup finishes the operator needs a window of unknown length to
  // decide which dispose check to run. Rather than switch A onto a
  // playlist/repeat-mode API (which would risk changing how/whether A
  // ever reports `completed`, and STEP 3/4 above depend on that exact
  // transition for the B-02 verdict), this arms a plain state listener
  // *after* the B-02 verdict is already recorded: if A reaches
  // `completed` again, it is transparently seeked back to zero and
  // replayed. This keeps A "playing" for as long as the operator needs
  // without touching the already-verified B-02 logic above.
  // ---------------------------------------------------------------------

  /// Seeks [controller] (always `_controllerA` in practice) back to zero
  /// and plays it, waiting up to 10s for `playing` to be observed. Logs
  /// the outcome under [reason] and returns whether A was confirmed
  /// playing.
  Future<bool> _restartA({required String reason}) async {
    if (_aDisposed) {
      _log('$reason: A is disposed, cannot restart');
      return false;
    }
    _log('$reason: seeking A to Duration.zero, then playing');
    await _controllerA.seekTo(Duration.zero);
    await _controllerA.play();
    final playingInTime = await _waitForState(
      _controllerA,
      PlayerState.playing,
      const Duration(seconds: 10),
    );
    _logSnapshot('A', _controllerA);
    if (_aDisposed) {
      // Disposed while the restart was in flight -- do not draw any
      // conclusion from the (now meaningless) state above.
      _log('$reason: A was disposed while restarting, ignoring result');
      return false;
    }
    if (!playingInTime || !_controllerA.isPlaying) {
      _log(
        '$reason WARNING: A did NOT reach playing state in time '
        '(state=${_controllerA.state.state.name}, '
        'isPlaying=${_controllerA.isPlaying}).',
      );
      return false;
    }
    _log('$reason: confirmed -- A is playing.');
    return true;
  }

  /// Arms the auto-restart guard on `_controllerA`: whenever A reaches
  /// `completed` from here on, it is transparently restarted so it keeps
  /// playing while the operator decides which dispose check to run.
  void _armAutoLoopA() {
    _aAutoLoopEnabled = true;
    _controllerA.addListener(_onACompletionGuard);
    _log(
      'A auto-loop: armed -- if A completes again it will be '
      'automatically seeked to 0 and replayed so it stays available for '
      'the operator dispose checks',
    );
  }

  /// Disarms the auto-restart guard. Called synchronously (no `await`
  /// before it) at the top of anything that disposes or tears down A, so
  /// a completion event racing with disposal can never fire a
  /// `play()`/`seekTo()` against an already-disposed controller.
  void _disarmAutoLoopA() {
    if (!_aAutoLoopEnabled) return;
    _aAutoLoopEnabled = false;
    _controllerA.removeListener(_onACompletionGuard);
  }

  void _onACompletionGuard() {
    if (!_aAutoLoopEnabled || _aDisposed || _aRestartInFlight) return;
    if (_controllerA.state.state != PlayerState.completed) return;
    _aRestartInFlight = true;
    _log(
      'A auto-loop: A completed again -- automatically restarting to '
      'keep it playing',
    );
    unawaited(
      _restartA(reason: 'A auto-loop').whenComplete(() {
        _aRestartInFlight = false;
      }),
    );
  }

  // ---------------------------------------------------------------------
  // Notification action routing (H-07 manual check enabler)
  //
  // Without subscribing to `actionStream`, lock-screen / Control Center
  // taps are delivered to Dart by the native side and then silently
  // dropped -- the notification can look fully correct (title, artwork,
  // enabled buttons) while doing nothing at all when tapped. Subscribing
  // here, per player, is what makes it possible to tell "the native H-07
  // fix forwarded the action and Dart acted on it" apart from "the action
  // never arrived in the first place".
  // ---------------------------------------------------------------------

  void _subscribeActions() {
    _actionSubA?.cancel();
    _actionSubB?.cancel();
    // actionEventStream (not the deprecated actionStream) is required so
    // "seekTo" (lock-screen / Control Center scrub bar) events carry their
    // target position.
    _actionSubA = _notifA.actionEventStream.listen((event) {
      _handleAction('A', event);
    });
    _actionSubB = _notifB.actionEventStream.listen((event) {
      _handleAction('B', event);
    });
    _log('STEP 6: subscribed to actionEventStream for both A and B');
  }

  /// Routes a lock-screen/Control Center action received for player
  /// [label] ('A' or 'B') to that player's controller only, logging the
  /// exact outcome so the console can be grepped for
  /// `[MP-TEST] ACTION <label>: ...`.
  Future<void> _handleAction(String label, NotificationActionEvent event) async {
    final disposed = label == 'A' ? _aDisposed : _bDisposed;
    final controller = label == 'A' ? _controllerA : _controllerB;
    final action = event.action;

    if (disposed) {
      _log(
        'ACTION $label: received=$action -> $label already disposed, '
        'ignoring',
      );
      return;
    }

    switch (action) {
      case 'play':
        _log('ACTION $label: received=play -> calling $label.play()');
        await controller.play();
        break;
      case 'pause':
        _log('ACTION $label: received=pause -> calling $label.pause()');
        await controller.pause();
        break;
      case 'next':
        _log(
          'ACTION $label: received=next -> calling $label.skipToNext()',
        );
        await controller.skipToNext();
        break;
      case 'previous':
        _log(
          'ACTION $label: received=previous -> calling '
          '$label.skipToPrevious()',
        );
        await controller.skipToPrevious();
        break;
      case 'stop':
        _log('ACTION $label: received=stop -> calling $label.stop()');
        await controller.stop();
        break;
      case 'seekForward':
        _log(
          'ACTION $label: received=seekForward -> calling '
          '$label.seekForward()',
        );
        await controller.seekForward();
        break;
      case 'seekBackward':
        _log(
          'ACTION $label: received=seekBackward -> calling '
          '$label.seekBackward()',
        );
        await controller.seekBackward();
        break;
      case NotificationActions.seekTo:
        final position = event.position;
        if (position == null) {
          _log(
            'ACTION $label: received=seekTo with no position -> ignoring',
          );
          break;
        }
        _log(
          'ACTION $label: received=seekTo($position) -> calling '
          '$label.seekTo($position)',
        );
        await controller.seekTo(position);
        break;
      default:
        _log('ACTION $label: received=$action -> unhandled, ignoring');
    }
    _logSnapshot(label, controller);
  }

  // ---------------------------------------------------------------------
  // Scripted scenario
  // ---------------------------------------------------------------------

  Future<void> _runScenario() async {
    try {
      _log('STEP 1: initializing + loading A and B (both left paused)');
      await _controllerA.initialize();
      await _controllerB.initialize();
      // A: short ~10s clip so completion happens quickly (B-02 needs it).
      await _controllerA.load(SampleMedia.bigBuckBunny);
      // B: a visibly different clip so A/B are distinguishable on screen.
      await _controllerB.load(SampleMedia.elephantsDream);
      _logSnapshot('A', _controllerA);
      _logSnapshot('B', _controllerB);

      _log('STEP 2: playing A only; B must remain not-playing');
      await _controllerA.play();
      // Give the native side a moment to report the transition.
      await Future.delayed(const Duration(milliseconds: 800));
      _logSnapshot('A', _controllerA);
      _logSnapshot('B', _controllerB);
      if (_controllerB.isPlaying) {
        _log(
          'STEP 2 WARNING: B is playing but only A.play() was called',
        );
      }

      _log('STEP 3: waiting for A to reach completed (timeout 45s)');
      final completedInTime = await _waitForState(
        _controllerA,
        PlayerState.completed,
        const Duration(seconds: 45),
      );
      if (!completedInTime) {
        _log(
          'STEP 3: TIMEOUT waiting for A to complete '
          '(observed state=${_controllerA.state.state.name})',
        );
      } else {
        _log('STEP 3: A reached completed');
      }

      _log('STEP 4: checking B-02 (cross-instance completion isolation)');
      _logSnapshot('A', _controllerA);
      _logSnapshot('B', _controllerB);
      final aState = _controllerA.state.state;
      final bState = _controllerB.state.state;
      final b02Pass =
          aState == PlayerState.completed && bState != PlayerState.completed;
      _log(
        'VERDICT B-02: ${b02Pass ? 'PASS' : 'FAIL'} '
        '(A=${aState.name}, B=${bState.name})',
      );

      _log(
        'STEP 5: restarting A -- its clip already completed above, and a '
        'bare play() may not restart a completed item, so seek to 0 first',
      );
      final aRestarted = await _restartA(reason: 'STEP 5');
      if (aRestarted) {
        // Only arm the "keep it playing" guard once we've actually seen A
        // reach playing again; arming it unconditionally could otherwise
        // mask a genuine STEP 5 failure by silently retrying forever.
        _armAutoLoopA();
      } else {
        _log(
          'STEP 5 WARNING: A did NOT restart successfully. Both dispose '
          'checks below require A to be playing -- do not trust their '
          'results until this is fixed (try "Play A" manually, or press '
          '"Reset / re-run scenario").',
        );
      }

      _log('STEP 6: starting B playing');
      await _controllerB.play();
      final bPlayingInTime = await _waitForState(
        _controllerB,
        PlayerState.playing,
        const Duration(seconds: 10),
      );
      _logSnapshot('A', _controllerA);
      _logSnapshot('B', _controllerB);
      if (!bPlayingInTime || !_controllerB.isPlaying) {
        _log(
          'STEP 6 WARNING: B did NOT reach playing state in time '
          '(state=${_controllerB.state.state.name}, '
          'isPlaying=${_controllerB.isPlaying}). The H-07 checks below will '
          'NOT be meaningful as scripted.',
        );
      } else {
        _log('STEP 6: confirmed -- B is playing.');
      }

      _log(
        'STEP 7: exercising H-07 (Now Playing / remote command ownership) '
        '-- initializing notifications for A then B (B LAST, so B is the '
        'expected owner of the shared Now Playing session under '
        'last-writer-wins)',
      );
      await _notifA.initialize(_controllerA.playerId,
          mediaPlayer: _controllerA.player);
      await _notifB.initialize(_controllerB.playerId,
          mediaPlayer: _controllerB.player);
      if (mounted) setState(() => _notificationsInitialized = true);
      _subscribeActions();

      final itemA = _controllerA.currentItem;
      final itemB = _controllerB.currentItem;
      if (itemA != null) {
        await _notifA.show(
          mediaItem: itemA,
          state: _controllerA.state,
          playerId: _controllerA.playerId,
        );
      }
      if (itemB != null) {
        await _notifB.show(
          mediaItem: itemB,
          state: _controllerB.state,
          playerId: _controllerB.playerId,
        );
      }
      _log(
        'STEP 7: notifications initialized + shown for A then B. EXPECTED '
        'OWNER of the shared Now Playing session: B (initialized + shown '
        'last).',
      );

      _log(
        'STEP 8: confirming BOTH A and B are playing before handing '
        'control to the operator -- EITHER dispose check below is only '
        'meaningful if both are playing right now',
      );
      _logSnapshot('A', _controllerA);
      _logSnapshot('B', _controllerB);
      final aStateNow = _controllerA.state.state;
      final bStateNow = _controllerB.state.state;
      final aPlayingNow =
          aStateNow == PlayerState.playing && _controllerA.isPlaying;
      final bPlayingNow =
          bStateNow == PlayerState.playing && _controllerB.isPlaying;
      if (!aPlayingNow) {
        final detail = aStateNow == PlayerState.completed
            ? 'A has COMPLETED again -- this is a real, valid state, not '
                'an error, but neither dispose check below is meaningful '
                'until A is playing (it should auto-restart shortly; if '
                'it does not, press "Play A" or "Reset / re-run scenario").'
            : 'Neither dispose check below is meaningful until this is '
                'fixed.';
        _log(
          'STEP 8 WARNING: A is NOT playing right now (state='
          '${aStateNow.name}, isPlaying=${_controllerA.isPlaying}). '
          '$detail',
        );
      }
      if (!bPlayingNow) {
        _log(
          'STEP 8 WARNING: B is NOT playing right now (state='
          '${bStateNow.name}, isPlaying=${_controllerB.isPlaying}). '
          'Neither dispose check below is meaningful until this is fixed.',
        );
      }
      if (aPlayingNow && bPlayingNow) {
        _log('STEP 8: confirmed -- A and B are both playing.');
      }

      _log(
        'STEP 9: scripted setup complete. NO automatic dispose will '
        'happen -- choose ONE of the two checks below by pressing the '
        'corresponding button, then lock the phone and inspect the '
        'SURVIVING player\'s lock-screen controls:\n'
        '  CHECK 1 (.notOwner): press "Dispose A" -> then check B\'s '
        'lock-screen controls.\n'
        '  CHECK 2 (.handedOff(to:)): press "Dispose OWNER (B)" -> then '
        'check A\'s lock-screen controls.\n'
        'A will keep auto-restarting (seek to 0 + play) whenever its '
        'short clip completes, so it should still be playing whenever '
        'you press a button -- but the log will say plainly if it is not. '
        'After running one check, press "Reset / re-run scenario" to '
        'tear down both players and re-run this setup from STEP 1 so you '
        'can perform the other check.',
      );
    } catch (e, st) {
      _log('SCENARIO ERROR: $e');
      debugPrint('$st');
      if (mounted) setState(() => _scenarioError = e.toString());
    } finally {
      if (mounted) setState(() => _scenarioRunning = false);
    }
  }

  // ---------------------------------------------------------------------
  // Manual actions
  // ---------------------------------------------------------------------

  Future<void> _playA() async {
    if (_aDisposed) return;
    _log('MANUAL: play A');
    await _controllerA.play();
    _logSnapshot('A', _controllerA);
  }

  Future<void> _playB() async {
    if (_bDisposed) return;
    _log('MANUAL: play B');
    await _controllerB.play();
    _logSnapshot('B', _controllerB);
  }

  Future<void> _pauseBoth() async {
    _log('MANUAL: pause (both A and B, whichever are alive/playing)');
    if (!_aDisposed) await _controllerA.pause();
    if (!_bDisposed) await _controllerB.pause();
    if (!_aDisposed) _logSnapshot('A', _controllerA);
    if (!_bDisposed) _logSnapshot('B', _controllerB);
  }

  /// CHECK 1: disposes A -- the expected *non-owner* of the shared Now
  /// Playing session -- while B is meant to still be alive and playing.
  /// This exercises the native `.notOwner` path (a non-owner is disposed;
  /// the owner, B, must be unaffected). If B is not alive and playing
  /// when this is pressed, the result is not meaningful -- a loud warning
  /// is logged instead of silently proceeding as if it were.
  Future<void> _disposeA() async {
    if (_aDisposed) return;
    // Synchronous, before any `await`: prevents a concurrent completion
    // event from racing a play()/seekTo() call against A mid-disposal.
    _disarmAutoLoopA();

    final aState = _controllerA.state.state;
    final aPlayingNow = aState == PlayerState.playing && _controllerA.isPlaying;
    final bAlive = !_bDisposed && !_controllerB.isDisposed;
    final bState = bAlive ? _controllerB.state.state : null;
    final bPlayingNow =
        bAlive && bState == PlayerState.playing && _controllerB.isPlaying;

    _log(
      'MANUAL: Dispose A pressed -- disposing A (expected NON-owner) to '
      'exercise the .notOwner path; the owner, B, must be unaffected',
    );
    _logSnapshot('A', _controllerA);
    if (bAlive) _logSnapshot('B', _controllerB);

    if (aState == PlayerState.completed) {
      _log(
        'MANUAL NOTE: A has COMPLETED again right now (state='
        '${aState.name}). This is a real, valid state, not an error -- '
        'A does not need to be playing for Check 1 (only B does), but '
        'this is noted plainly so no conclusion is drawn from A\'s state.',
      );
    } else if (!aPlayingNow) {
      _log(
        'MANUAL NOTE: A is not currently playing (state=${aState.name}). '
        'This does not block Check 1 -- only B\'s state below does.',
      );
    }

    if (!bAlive) {
      _log(
        'MANUAL WARNING: B is already disposed -- there is no surviving '
        'player left to check on the lock screen. This dispose will NOT '
        'be a meaningful Check 1. Press "Reset / re-run scenario" and '
        'try again.',
      );
    } else if (!bPlayingNow) {
      _log(
        'MANUAL WARNING: B is NOT playing right now (state='
        '${bState!.name}, isPlaying=${_controllerB.isPlaying}). The '
        'lock-screen result after this dispose will not be meaningful -- '
        'press "Play B" first, then retry "Dispose A".',
      );
    } else {
      _log(
        'MANUAL: confirmed B is playing -- disposing A (non-owner) now '
        'should leave B\'s Now Playing session unaffected via .notOwner.',
      );
    }

    await _actionSubA?.cancel();
    _actionSubA = null;
    try {
      _notifA.dispose();
    } catch (e) {
      _log('A notification dispose error: $e');
    }
    try {
      _controllerA.removeListener(_onAChanged);
      _controllerA.dispose();
    } catch (e) {
      _log('A controller dispose error: $e');
    }
    _aDisposed = true;
    if (mounted) setState(() {});

    _log(
      'VERDICT H-07-DART: B controller alive=$bAlive '
      'state=${bAlive ? _controllerB.state.state.name : 'n/a (disposed)'} '
      'isPlaying=${bAlive && _controllerB.isPlaying}. Dart cannot '
      'introspect MPNowPlayingInfoCenter / MPRemoteCommandCenter '
      'ownership directly -- confirm on the LOCK SCREEN / Control Center '
      'that B still shows Now Playing info and its play/pause control '
      'still works after A (the non-owner) was disposed.'
      '${bPlayingNow ? '' : ' WARNING: B was not confirmed playing '
          'before this dispose -- this result is not meaningful.'}',
    );
  }

  Future<void> _disposeB() async {
    if (_bDisposed) return;
    _log('MANUAL: disposing B');
    await _actionSubB?.cancel();
    _actionSubB = null;
    try {
      _notifB.dispose();
    } catch (e) {
      _log('B notification dispose error: $e');
    }
    try {
      _controllerB.removeListener(_onBChanged);
      _controllerB.dispose();
    } catch (e) {
      _log('B controller dispose error: $e');
    }
    _bDisposed = true;
    if (mounted) setState(() {});
    _log('B disposed. Check lock screen: does A still show controls?');
  }

  /// Harder H-07 variant: disposes B -- the expected *owner* of the shared
  /// Now Playing session (it was initialized/shown last in the scripted
  /// run) -- while A is meant to still be alive and playing. This forces
  /// the native `.handedOff(to:)` promotion path (ownership must move to
  /// A) rather than the `.notOwner` path that disposing A exercises. If A
  /// is not alive and playing when this is pressed, the result is not
  /// meaningful -- a loud warning is logged instead of silently proceeding
  /// as if it were.
  Future<void> _disposeOwnerB() async {
    if (_bDisposed) {
      _log('MANUAL: Dispose OWNER (B) pressed but B is already disposed');
      return;
    }

    final aAlive = !_aDisposed && !_controllerA.isDisposed;
    final aState = aAlive ? _controllerA.state.state : null;
    final aPlaying =
        aAlive && aState == PlayerState.playing && _controllerA.isPlaying;

    _log(
      'MANUAL: Dispose OWNER (B) pressed -- disposing B (expected owner) '
      'to force the .handedOff(to:) path instead of .notOwner',
    );
    if (aAlive) _logSnapshot('A', _controllerA);
    _logSnapshot('B', _controllerB);

    if (!aAlive) {
      _log(
        'MANUAL WARNING: A is disposed -- there is no live sibling to hand '
        'off to. This dispose will not exercise .handedOff(to:) '
        'meaningfully. Press "Reset / re-run scenario" and try Check 2 '
        'again without pressing "Dispose A" first.',
      );
    } else if (aState == PlayerState.completed) {
      _log(
        'MANUAL WARNING: A has COMPLETED again right now (state='
        '${aState?.name}) -- this is a real, valid state, not an error, '
        'but it means A is NOT playing at this exact moment. The '
        'auto-loop guard should restart it within a few hundred '
        'milliseconds; wait for the next "A ... state=playing" log line '
        'and retry, rather than drawing a conclusion from this attempt.',
      );
    } else if (!aPlaying) {
      _log(
        'MANUAL WARNING: A is alive but NOT playing (state='
        '${aState?.name}, isPlaying='
        '${_controllerA.isPlaying}). The lock-screen result after this '
        'dispose will not be meaningful -- press "Play A" first, then '
        'retry "Dispose OWNER (B)".',
      );
    } else {
      _log(
        'MANUAL: confirmed A is playing -- disposing B (owner) now should '
        'hand off Now Playing ownership to A via .handedOff(to:).',
      );
    }

    await _actionSubB?.cancel();
    _actionSubB = null;
    try {
      _notifB.dispose();
    } catch (e) {
      _log('B notification dispose error: $e');
    }
    try {
      _controllerB.removeListener(_onBChanged);
      _controllerB.dispose();
    } catch (e) {
      _log('B controller dispose error: $e');
    }
    _bDisposed = true;
    if (mounted) setState(() {});

    _log(
      'VERDICT H-07-DART-HANDOFF: B (owner) disposed with A alive=$aAlive '
      'playing=$aPlaying. Dart cannot introspect '
      'MPNowPlayingInfoCenter / MPRemoteCommandCenter ownership directly '
      '-- confirm on the LOCK SCREEN / Control Center that A now shows Now '
      'Playing info and its play/pause control still works '
      '${aPlaying ? '(this exercises .handedOff(to:))' : '(NOT meaningful -- A was not confirmed alive+playing above)'}.',
    );
  }

  /// Fully tears down both players and their notification services and
  /// recreates them from scratch (fresh, unique player IDs), then re-runs
  /// the scripted setup (STEP 1-9) so the operator can perform Check 1,
  /// reset, then perform Check 2 without relaunching the app.
  ///
  /// Teardown order mirrors `dispose()`/the individual `_disposeX`
  /// methods: cancel `actionStream` subscriptions first (so no action can
  /// arrive for a controller mid-teardown), disarm the A auto-loop guard
  /// synchronously, then dispose whichever of A/B are still alive. Every
  /// dispose is skipped for an already-disposed controller so this can
  /// never double-dispose regardless of which checks were run beforehand.
  Future<void> _resetScenario() async {
    if (_resetInProgress) return;
    if (mounted) setState(() => _resetInProgress = true);
    _log(
      'RESET: tearing down both players and notification services for a '
      'fresh scripted run',
    );

    // Synchronous, before any `await`: guarantees no in-flight completion
    // event can race a play()/seekTo() call against A mid-teardown.
    _disarmAutoLoopA();

    await _actionSubA?.cancel();
    _actionSubA = null;
    await _actionSubB?.cancel();
    _actionSubB = null;

    if (!_aDisposed) {
      _controllerA.removeListener(_onAChanged);
      try {
        _notifA.dispose();
      } catch (e) {
        _log('RESET: A notification dispose error: $e');
      }
      try {
        _controllerA.dispose();
      } catch (e) {
        _log('RESET: A controller dispose error: $e');
      }
    }
    if (!_bDisposed) {
      _controllerB.removeListener(_onBChanged);
      try {
        _notifB.dispose();
      } catch (e) {
        _log('RESET: B notification dispose error: $e');
      }
      try {
        _controllerB.dispose();
      } catch (e) {
        _log('RESET: B controller dispose error: $e');
      }
    }

    _createFreshPlayers();
    _lastLoggedA = null;
    _lastLoggedB = null;
    _aDisposed = false;
    _bDisposed = false;
    _aRestartInFlight = false;
    _notificationsInitialized = false;
    _scenarioError = null;
    _scenarioRunning = true;
    if (mounted) setState(() {});

    _log('RESET: complete -- re-running scripted scenario from STEP 1');
    await _runScenario();

    if (mounted) setState(() => _resetInProgress = false);
  }

  @override
  void dispose() {
    _disarmAutoLoopA();
    _actionSubA?.cancel();
    _actionSubB?.cancel();
    if (!_aDisposed) {
      _controllerA.removeListener(_onAChanged);
      try {
        _notifA.dispose();
      } catch (_) {}
      _controllerA.dispose();
    }
    if (!_bDisposed) {
      _controllerB.removeListener(_onBChanged);
      try {
        _notifB.dispose();
      } catch (_) {}
      _controllerB.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-Player (B-02 / H-07)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IntroCard(),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PlayerColumn(
                      label: 'A',
                      controller: _controllerA,
                      disposed: _aDisposed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PlayerColumn(
                      label: 'B',
                      controller: _controllerB,
                      disposed: _bDisposed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_scenarioRunning)
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Running scripted B-02 / H-07 scenario...'),
                  ],
                ),
              if (_scenarioError != null)
                Text(
                  'Scenario error: $_scenarioError',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              const SizedBox(height: 8),
              Text(
                'Manual controls',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: (_aDisposed || _resetInProgress) ? null : _playA,
                    child: const Text('Play A'),
                  ),
                  FilledButton(
                    onPressed: (_bDisposed || _resetInProgress) ? null : _playB,
                    child: const Text('Play B'),
                  ),
                  OutlinedButton(
                    onPressed: _resetInProgress ? null : _pauseBoth,
                    child: const Text('Pause'),
                  ),
                  OutlinedButton(
                    onPressed:
                        (_aDisposed || _resetInProgress) ? null : _disposeA,
                    child: const Text('Dispose A'),
                  ),
                  OutlinedButton(
                    onPressed:
                        (_bDisposed || _resetInProgress) ? null : _disposeB,
                    child: const Text('Dispose B'),
                  ),
                  OutlinedButton(
                    onPressed: (_bDisposed || _resetInProgress)
                        ? null
                        : _disposeOwnerB,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepOrange,
                    ),
                    child: const Text('Dispose OWNER (B)'),
                  ),
                  OutlinedButton(
                    onPressed: _resetInProgress ? null : _resetScenario,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                    ),
                    child: Text(
                      _resetInProgress
                          ? 'Resetting...'
                          : 'Reset / re-run scenario',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ManualCheckCaption(
                  notificationsInitialized: _notificationsInitialized),
              const SizedBox(height: 16),
              Text(
                'Event log (mirrors console [MP-TEST] lines, newest first)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 260),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _eventLog.isEmpty
                    ? const Text('No events yet.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _eventLog.length,
                        itemBuilder: (context, index) => Text(
                          _eventLog[index],
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Two independent MediaControllers (A, B) run concurrently to '
        'reproduce B-02 (cross-instance completion/error notifications) '
        'and H-07 (Now Playing / remote command ownership). A scripted '
        'scenario runs automatically on load: it plays A to completion '
        '(B-02), restarts A, starts B playing, and initializes '
        'notifications for A then B (B last = expected owner) -- then '
        'STOPS. Nothing is auto-disposed. From that steady state, choose '
        'ONE check by hand: "Dispose A" exercises .notOwner (check B\'s '
        'lock screen); "Dispose OWNER (B)" exercises .handedOff(to:) '
        '(check A\'s lock screen). Press "Reset / re-run scenario" '
        'afterwards to tear down both players and re-run the setup so '
        'you can perform the other check. Every state change and step is '
        'printed to the console -- and mirrored in the event log below -- '
        'with the "[MP-TEST]" prefix.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  final String label;
  final MediaController controller;
  final bool disposed;

  const _PlayerColumn({
    required this.label,
    required this.controller,
    required this.disposed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Player $label',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: ColoredBox(
            color: Colors.black,
            child: disposed
                ? const Center(
                    child: Text(
                      'disposed',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : MediaPlayerWidget(
                    controller: controller,
                    showControls: false,
                    boxFit: BoxFit.contain,
                    backgroundColor: Colors.black,
                  ),
          ),
        ),
        const SizedBox(height: 4),
        if (!disposed)
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Text(
                '${controller.state.state.name} '
                '(playing=${controller.isPlaying})\n'
                'id=${controller.playerId}',
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          )
        else
          Text('id=${controller.playerId} (disposed)',
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ManualCheckCaption extends StatelessWidget {
  final bool notificationsInitialized;

  const _ManualCheckCaption({required this.notificationsInitialized});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(
              alpha: 0.35,
            ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'MANUAL CHECKS REQUIRED FOR H-07: Dart cannot read '
        'MPNowPlayingInfoCenter / MPRemoteCommandCenter ownership, so no '
        'automated PASS/FAIL is printed for it -- both checks below are '
        'only meaningful while the SURVIVING player is actually playing '
        '(the on-screen "[MP-TEST]" log states this explicitly for each '
        'step; if it logs a WARNING, ignore whatever the lock screen shows '
        'and re-run the check). The scripted scenario STOPS once both A '
        'and B are confirmed playing and notifications are initialized -- '
        'it never disposes anything automatically. Pick ONE check below, '
        'then press "Reset / re-run scenario" to set up for the other.\n\n'
        'CHECK 1 -- .notOwner path: '
        '${notificationsInitialized ? '' : 'Wait for the scripted scenario to initialize notifications (STEP 7) and confirm both are playing (STEP 8), then '}'
        'press "Dispose A" (with B confirmed playing beforehand -- STEP 8 '
        'or the log line just above the "Dispose A" press confirms this). '
        'LOCK THE PHONE and, from the lock screen / Control Center, press '
        'play then pause on player B\'s transport controls.\n\n'
        'CHECK 2 -- .handedOff(to:) path: press "Dispose OWNER (B)" while '
        'A is confirmed alive AND playing (STEP 8 confirms this, and A '
        'auto-restarts if its short clip completes again while you '
        'decide -- watch for a WARNING in the log if it has not yet come '
        'back to "playing"). This disposes B -- the session\'s owner -- '
        'and ownership must hand off to A. LOCK THE PHONE and check A\'s '
        'transport controls instead of B\'s.\n\n'
        'For EITHER check, confirm BOTH of the following on the surviving '
        'player: (1) its playback actually starts and stops on screen, '
        'and (2) a "[MP-TEST] ACTION <label>: received=play -> calling '
        '<label>.play()" line (and the matching pause line) appears in '
        'the console log below. Seeing the Now Playing info alone is NOT '
        'sufficient -- this page only reacts to lock-screen taps because '
        'it explicitly subscribes to each player\'s '
        'NotificationService.actionStream; without that subscription the '
        'controls look correct but silently do nothing, which is the '
        'exact failure mode this check exists to catch.\n\n'
        'After completing a check, press "Reset / re-run scenario" -- it '
        'tears down BOTH players and notification services, recreates '
        'them with fresh IDs, and re-runs the scripted setup from STEP 1 '
        'so you can perform the other check in the same session.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
      ),
    );
  }
}

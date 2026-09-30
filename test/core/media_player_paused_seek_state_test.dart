import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Issue #137 - `ready` after playback has started is `paused`.
///
/// Android used to report `ready` when a paused seek/rebuffer returned to
/// STATE_READY with playWhenReady == false. Native is fixed; Dart keeps a
/// backstop (`_itemStarted`) for an older cached native build. The native
/// mapping is pinned in test/native_contract/ready_after_start_paused_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> state(String id, String s, {String? pauseReason}) async {
    const codec = StandardMethodCodec();
    final data = codec.encodeMethodCall(MethodCall('onStateChanged', {
      'playerId': id,
      'state': s,
      'isBuffering': s == 'buffering',
      'bufferPercentage': 0.0,
      if (pauseReason != null) 'pauseReason': pauseReason,
    }));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('zmedia_player', data, (_) {});
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('zmedia_player'), (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  test('first ready after load (never played) stays ready', () async {
    final p = MediaPlayer(playerId: 'r137-initial');
    await p.initialize();
    await state('r137-initial', 'buffering');
    await state('r137-initial', 'ready');
    expect(p.currentState.state, PlayerState.ready);
    await p.dispose();
  });

  test(
      'iOS load sequence (buffering, paused w/o reason, buffering, ready) '
      'ends ready', () async {
    final p = MediaPlayer(playerId: 'r137-ios-load');
    await p.initialize();
    await state('r137-ios-load', 'buffering');
    await state('r137-ios-load', 'paused');
    await state('r137-ios-load', 'buffering');
    await state('r137-ios-load', 'ready');
    expect(p.currentState.state, PlayerState.ready);
    await p.dispose();
  });

  test('paused -> buffering -> ready (older native) surfaces paused', () async {
    final p = MediaPlayer(playerId: 'r137-paused-seek');
    await p.initialize();
    await state('r137-paused-seek', 'playing');
    await state('r137-paused-seek', 'paused', pauseReason: 'user');
    await state('r137-paused-seek', 'buffering');
    expect(p.currentState.state, PlayerState.buffering);
    await state('r137-paused-seek', 'ready');
    expect(p.currentState.state, PlayerState.paused);
    await p.dispose();
  });

  test(
      'a re-reported paused without pauseReason emits nothing on '
      'pauseReasonStream', () async {
    final p = MediaPlayer(playerId: 'r137-reason');
    await p.initialize();
    final reasons = <PlayerPauseReason>[];
    final sub = p.pauseReasonStream.listen(reasons.add);
    await state('r137-reason', 'playing');
    await state('r137-reason', 'paused', pauseReason: 'user');
    await state('r137-reason', 'buffering');
    await state('r137-reason', 'paused'); // native re-report, no reason
    expect(p.currentState.state, PlayerState.paused);
    expect(reasons, [PlayerPauseReason.user]);
    await sub.cancel();
    await p.dispose();
  });

  test('stop() resets: the next ready is a fresh load', () async {
    final p = MediaPlayer(playerId: 'r137-stop');
    await p.initialize();
    await state('r137-stop', 'playing');
    await p.stop();
    await state('r137-stop', 'ready');
    expect(p.currentState.state, PlayerState.ready);
    await p.dispose();
  });

  test('ready after playing then completed-seek still resolves to paused',
      () async {
    final p = MediaPlayer(playerId: 'r137-completed');
    await p.initialize();
    await state('r137-completed', 'playing');
    await state('r137-completed', 'completed');
    await p.seekTo(Duration.zero);
    await state('r137-completed', 'ready');
    expect(p.currentState.state, PlayerState.paused);
    await p.dispose();
  });
}

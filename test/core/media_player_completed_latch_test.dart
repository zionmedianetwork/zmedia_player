import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Issue #132 — `PlayerState.completed` persists after a natural end.
///
/// Both natives emit a quiescent event right after `completed` (Android:
/// `onIsPlayingChanged(false)` -> "paused"; iOS: `timeControlStatus`
/// `.paused`). Dart latches `completed` against `paused`/`idle` until a host
/// command or another native state. The native suppressions themselves are
/// pinned textually in test/native_contract/completed_persists_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  Future<void> injectEvent(String method, Map<String, dynamic> args) async {
    const codec = StandardMethodCodec();
    final data = codec.encodeMethodCall(MethodCall(method, args));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('zmedia_player', data, (_) {});
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> state(String id, String s) => injectEvent('onStateChanged', {
        'playerId': id,
        'state': s,
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'),
            (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  test('completed then "paused" stays completed (Android/iOS order)', () async {
    final player = MediaPlayer(playerId: 'completed-paused');
    await player.initialize();
    await state('completed-paused', 'completed');
    await state('completed-paused', 'paused');
    expect(player.currentState.state, PlayerState.completed);
    await player.dispose();
  });

  test('completed then "idle" stays completed', () async {
    final player = MediaPlayer(playerId: 'completed-idle');
    await player.initialize();
    await state('completed-idle', 'completed');
    await state('completed-idle', 'idle');
    expect(player.currentState.state, PlayerState.completed);
    await player.dispose();
  });

  test('paused then completed ends completed', () async {
    final player = MediaPlayer(playerId: 'paused-completed');
    await player.initialize();
    await state('paused-completed', 'paused');
    await state('paused-completed', 'completed');
    expect(player.currentState.state, PlayerState.completed);
    await player.dispose();
  });

  test('real forward progress ends the latch', () async {
    final player = MediaPlayer(playerId: 'completed-progress');
    await player.initialize();
    await state('completed-progress', 'completed');
    await state('completed-progress', 'playing');
    expect(player.currentState.state, PlayerState.playing);
    await state('completed-progress', 'paused');
    expect(player.currentState.state, PlayerState.paused);
    await player.dispose();
  });

  test('a host command (seekTo) ends the latch', () async {
    final player = MediaPlayer(playerId: 'completed-seek');
    await player.initialize();
    await state('completed-seek', 'completed');
    await player.seekTo(Duration.zero);
    await state('completed-seek', 'paused');
    expect(player.currentState.state, PlayerState.paused);
    await player.dispose();
  });

  test('play() after completion restarts from zero', () async {
    final player = MediaPlayer(playerId: 'completed-play');
    await player.initialize();
    await state('completed-play', 'completed');
    await state('completed-play', 'paused');
    calls.clear();
    await player.play();
    final names = calls.map((c) => c.method).toList();
    expect(names.indexOf('seekTo'), greaterThanOrEqualTo(0));
    expect(names.indexOf('seekTo'), lessThan(names.indexOf('play')));
    final seek = calls.firstWhere((c) => c.method == 'seekTo');
    expect((seek.arguments as Map)['position'], 0);
    await player.dispose();
  });

  test('stop() ends the latch so the following idle is reported', () async {
    final player = MediaPlayer(playerId: 'completed-stop');
    await player.initialize();
    await state('completed-stop', 'completed');
    await player.stop();
    await state('completed-stop', 'idle');
    expect(player.currentState.state, PlayerState.idle);
    await player.dispose();
  });

  test('seekTo() away from the end leaves completed (issue #143)', () async {
    final player = MediaPlayer(playerId: 'completed-seek-away');
    await player.initialize();
    await state('completed-seek-away', 'completed');
    await player.seekTo(const Duration(seconds: 30));
    expect(player.currentState.state, PlayerState.paused);
    // A trailing native paused changes nothing; the latch is gone.
    await state('completed-seek-away', 'paused');
    expect(player.currentState.state, PlayerState.paused);
    await player.dispose();
  });

  test('seekTo() away from the end emits paused WITH the seek position',
      () async {
    final player = MediaPlayer(playerId: 'completed-seek-first-emit');
    await player.initialize();
    await state('completed-seek-first-emit', 'completed');
    final emitted = <PlaybackState>[];
    final sub = player.stateStream.listen(emitted.add);
    const target = Duration(seconds: 30);
    await player.seekTo(target);
    await Future<void>.delayed(Duration.zero);
    // Position-only pushes are silent, so the first emission must already
    // carry both the left-completed state and the seek position.
    expect(emitted, isNotEmpty);
    expect(emitted.first.state, PlayerState.paused);
    expect(emitted.first.position, target);
    await sub.cancel();
    await player.dispose();
  });

  test('play() after a seek away from the end does not restart (issue #143)',
      () async {
    final player = MediaPlayer(playerId: 'completed-seek-play');
    await player.initialize();
    await state('completed-seek-play', 'completed');
    await player.seekTo(const Duration(seconds: 30));
    calls.clear();
    await player.play();
    expect(calls.where((c) => c.method == 'seekTo'), isEmpty);
    expect(calls.map((c) => c.method), contains('play'));
    await player.dispose();
  });

  test('play() on a completed live stream does not seek (issue #142)',
      () async {
    final player = MediaPlayer(playerId: 'completed-live-play');
    await player.initialize();
    await player.load(const MediaItem(
      id: 'live',
      url: 'https://example.com/live.m3u8',
      title: 'Live',
      isLive: true,
    ));
    await state('completed-live-play', 'completed');
    expect(player.currentState.state, PlayerState.completed);
    calls.clear();
    await player.play();
    expect(calls.where((c) => c.method == 'seekTo'), isEmpty);
    expect(calls.map((c) => c.method), contains('play'));
    await player.dispose();
  });
}

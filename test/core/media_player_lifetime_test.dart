// Issue #133 regression coverage: a paused MediaPlayer that the app still holds
// must never be reaped. The old Dart stale-instance sweep (and its native
// twins) disposed any non-playing instance idle for 15 minutes; Dart now owns
// the lifecycle and an instance lives until dispose().

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('an idle, paused player with no listeners survives hours of inactivity',
      () async {
    final player = MediaPlayer(playerId: 'lifetime-idle');
    await player.initialize();
    await player.pause();

    fakeAsync((async) {
      // Far past the old 15-minute threshold and many 5-minute sweep ticks.
      async.elapse(const Duration(hours: 3));
    });
    await Future<void>.delayed(Duration.zero);

    expect(player.isDisposed, isFalse);
    expect(calls, isNot(contains('dispose')));

    // The original symptom: Play after a long pause must still reach native.
    calls.clear();
    await player.play();
    expect(calls, contains('play'));

    await player.dispose();
    expect(calls, contains('dispose'));
  });

  test('the deprecated attach()/detach() are harmless no-ops', () async {
    final player = MediaPlayer(playerId: 'lifetime-attach');
    await player.initialize();
    // ignore: deprecated_member_use_from_same_package
    player.attach();
    // ignore: deprecated_member_use_from_same_package
    player.detach();
    // ignore: deprecated_member_use_from_same_package
    player.detach();
    expect(player.isDisposed, isFalse);
    await player.dispose();
  });

  test('a native command error for a missing player surfaces as a typed error',
      () async {
    final player = MediaPlayer(playerId: 'lifetime-missing');
    await player.initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
      if (call.method == 'play') {
        throw PlatformException(
          code: 'PLAY_ERROR',
          message: 'Player not found: lifetime-missing',
        );
      }
      return null;
    });

    await expectLater(player.play(), throwsA(isA<MediaPlayerException>()));
    await player.dispose();
  });
}

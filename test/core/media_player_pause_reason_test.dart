import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Issue #126 — `PlayerPauseReason` is wire-valued, and every member is
/// actually reachable.
///
/// Before this change the enum declared `user` and `audioFocusLoss` but the
/// only emission site compared the payload against the hardcoded string
/// `'audioFocusLoss'`, so `user` could not be produced by any input at all —
/// "declared but never emitted". Android additionally collapsed every
/// non-focus-loss reason to `null`, which mislabelled an
/// `AUDIO_BECOMING_NOISY` pause (headphones unplugged) as an unattributed —
/// i.e. viewer — pause.
///
/// ## What is NOT covered here
///
/// These tests inject the `onStateChanged` payload directly, so they prove
/// the **Dart** half of the contract: every wire value parses, and nothing
/// else emits. They cannot prove either native actually *sends* those
/// values — that is what
/// `test/native_contract/pause_reason_vocabulary_test.dart` guards (by
/// parsing the Kotlin/Swift as text), plus on-device verification.
///
/// In particular, iOS's `pauseWasHostInitiated` / `interruptionInProgress`
/// bookkeeping is inspection + on-device only: the tests mock the channel,
/// and `MediaPlayerManager.swift`'s interruption handler already carries its
/// own `NEEDS ON-DEVICE VERIFICATION` marker for exactly this reason (a
/// phone call/Siri/alarm cannot be exercised in a simulator).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> injectEvent(String method, Map<String, dynamic> args) async {
    const codec = StandardMethodCodec();
    final data = codec.encodeMethodCall(MethodCall(method, args));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('zmedia_player', data, (_) {});
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (_) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  group('PlayerPauseReason.fromWireValue', () {
    test('round-trips every member', () {
      for (final reason in PlayerPauseReason.values) {
        expect(PlayerPauseReason.fromWireValue(reason.wireValue), reason);
      }
    });

    test('wire values are unique', () {
      final values = PlayerPauseReason.values.map((r) => r.wireValue).toList();
      expect(values.toSet(), hasLength(values.length));
    });

    /// The deliberate difference from `MediaErrorCategory.fromWireValue`,
    /// which falls back to `unknown`: there is no catch-all member to guess
    /// with here, and guessing `user` would recreate #126 (a headphone-unplug
    /// pause reading as a deliberate viewer pause) for any host keying
    /// "don't auto-recover" off it.
    test('returns null — never a guess — for unknown and absent values', () {
      expect(PlayerPauseReason.fromWireValue(null), isNull);
      expect(PlayerPauseReason.fromWireValue(''), isNull);
      expect(PlayerPauseReason.fromWireValue('somethingNew'), isNull);
      expect(PlayerPauseReason.fromWireValue('User'), isNull,
          reason: 'Matching is exact, not case-insensitive.');
      expect(PlayerPauseReason.fromWireValue('audio_focus_loss'), isNull);
    });
  });

  group('onStateChanged pauseReason → pauseReasonStream', () {
    Future<PlayerPauseReason?> emittedFor(String id, String? wireValue) async {
      final player = MediaPlayer(playerId: id);
      await player.initialize();

      PlayerPauseReason? received;
      final sub = player.pauseReasonStream.listen((r) => received = r);

      await injectEvent('onStateChanged', {
        'playerId': id,
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
        if (wireValue != null) 'pauseReason': wireValue,
      });
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await player.dispose();
      return received;
    }

    // One test per wire value, so a rename/typo in the enum fails loudly
    // rather than quietly reducing what a host can observe.
    for (final reason in PlayerPauseReason.values) {
      test('"${reason.wireValue}" emits PlayerPauseReason.${reason.name}',
          () async {
        expect(
          await emittedFor('pause-reason-${reason.name}', reason.wireValue),
          reason,
        );
      });
    }

    test('an unrecognized value emits nothing', () async {
      expect(
        await emittedFor('pause-reason-unknown', 'somethingNativeInvented'),
        isNull,
      );
    });

    test('an absent pauseReason key emits nothing', () async {
      expect(await emittedFor('pause-reason-absent', null), isNull);
    });

    /// The state itself is unaffected by attribution: an attributed pause is
    /// still a `paused` state, exactly as before.
    test('the paused state is reported regardless of attribution', () async {
      final player = MediaPlayer(playerId: 'pause-reason-state');
      await player.initialize();

      await injectEvent('onStateChanged', {
        'playerId': 'pause-reason-state',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
        'pauseReason': 'audioBecomingNoisy',
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.paused);

      await player.dispose();
    });

    /// A `pauseReason` riding a non-`paused` state should not happen (native
    /// only attaches one to a pause), but if it did, parsing it is still the
    /// honest reading of the payload — it is native's statement about why
    /// playback stopped. Pinned so the behaviour is a decision, not an
    /// accident.
    test('a pauseReason on a non-paused state is still parsed', () async {
      final player = MediaPlayer(playerId: 'pause-reason-nonpaused');
      await player.initialize();

      PlayerPauseReason? received;
      final sub = player.pauseReasonStream.listen((r) => received = r);

      await injectEvent('onStateChanged', {
        'playerId': 'pause-reason-nonpaused',
        'state': 'idle',
        'isBuffering': false,
        'bufferPercentage': 0.0,
        'pauseReason': 'remote',
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, PlayerPauseReason.remote);

      await sub.cancel();
      await player.dispose();
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('PlaybackState.copyWith', () {
    test('preserves bufferedPosition when copying other fields', () {
      const buffered = Duration(seconds: 30);
      const initial = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: buffered,
      );

      final updated = initial.copyWith(state: PlayerState.paused);

      expect(updated.state, PlayerState.paused);
      expect(updated.bufferedPosition, buffered,
          reason: 'bufferedPosition must survive a copyWith that omits it');
    });

    test('copyWith can update bufferedPosition', () {
      const initial = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: Duration(seconds: 10),
      );

      final updated = initial.copyWith(
        bufferedPosition: const Duration(seconds: 45),
      );

      expect(updated.bufferedPosition, const Duration(seconds: 45));
    });

    test('copyWith preserves bufferedPosition when updating position', () {
      const buffered = Duration(seconds: 60);
      const initial = PlaybackState(
        state: PlayerState.playing,
        position: Duration(seconds: 5),
        bufferedPosition: buffered,
      );

      final updated = initial.copyWith(position: const Duration(seconds: 10));

      expect(updated.position, const Duration(seconds: 10));
      expect(updated.bufferedPosition, buffered);
    });
  });

  group('PlaybackState equality', () {
    test('two states differing only in bufferedPosition are not equal', () {
      const a = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: Duration(seconds: 10),
      );
      const b = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: Duration(seconds: 20),
      );

      expect(a == b, isFalse);
    });

    test('two states with same bufferedPosition are equal', () {
      const a = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: Duration(seconds: 15),
      );
      const b = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: Duration(seconds: 15),
      );

      expect(a == b, isTrue);
    });

    test('bufferedPosition participates in hashCode', () {
      const a = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: Duration(seconds: 10),
      );
      const b = PlaybackState(
        state: PlayerState.playing,
        bufferedPosition: Duration(seconds: 20),
      );

      expect(a.hashCode == b.hashCode, isFalse);
    });
  });
}

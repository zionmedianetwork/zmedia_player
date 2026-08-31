// Model-level regression tests for issue #88 ("No live-edge signal: with DVR
// enabled, a healthy live edge is indistinguishable from a frozen playhead").
//
// Covers the two fields added to PlaybackState — `liveEdgeOffset` and
// `positionBasis` — plus the `isAtLiveEdge` / `isAtLiveEdgeWithin` /
// `isPositionWindowRelative` getters derived from them, and their round trip
// through copyWith / == / hashCode.
//
// The tolerance under test is PlaybackState.defaultLiveEdgeTolerance
// (15 seconds); these tests assert against that constant rather than a
// hard-coded 15s so that changing the documented default is a one-line change
// that stays covered on both sides of the boundary.

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('PlaybackState live-edge defaults (VOD)', () {
    test('liveEdgeOffset defaults to null and positionBasis to absolute', () {
      const state = PlaybackState(state: PlayerState.playing);

      expect(state.liveEdgeOffset, isNull,
          reason: 'VOD has no live edge, so there is no offset to report');
      expect(state.positionBasis, PositionBasis.absolute);
      expect(state.isPositionWindowRelative, isFalse);
    });

    test('isAtLiveEdge is false when liveEdgeOffset is null', () {
      const state = PlaybackState(state: PlayerState.playing);

      expect(state.isAtLiveEdge, isFalse,
          reason: '"at the live edge" is answered false, not null/throwing, '
              'for media that has no live edge');
      expect(state.isAtLiveEdgeWithin(const Duration(days: 1)), isFalse,
          reason: 'a null offset is never at the edge, however wide the '
              'tolerance');
    });
  });

  group('PlaybackState.isAtLiveEdge tolerance boundary', () {
    const tolerance = PlaybackState.defaultLiveEdgeTolerance;

    test('documented default tolerance is 15 seconds', () {
      expect(tolerance, const Duration(seconds: 15),
          reason: 'the tolerance is public API and documented in '
              'docs/api-reference/live-streaming.md — changing it is a '
              'behaviour change, not an implementation detail');
    });

    test('true strictly inside the tolerance', () {
      const state = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 14, milliseconds: 999),
      );
      expect(state.isAtLiveEdge, isTrue);
    });

    test('true exactly at the tolerance (inclusive boundary)', () {
      final state = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: tolerance,
      );
      expect(state.isAtLiveEdge, isTrue,
          reason: 'the boundary is inclusive: offset <= tolerance');
    });

    test('false just beyond the tolerance', () {
      const state = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 15, milliseconds: 1),
      );
      expect(state.isAtLiveEdge, isFalse);
    });

    test('false far behind the edge (viewer scrubbed back into the DVR window)',
        () {
      const state = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(minutes: 4),
      );
      expect(state.isAtLiveEdge, isFalse);
    });

    test('a negative offset counts as at the edge', () {
      const state = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(milliseconds: -250),
      );
      expect(state.isAtLiveEdge, isTrue,
          reason: 'the playhead can transiently read slightly ahead of the '
              'last observed edge between samples');
    });

    test('isAtLiveEdgeWithin honours a caller-supplied tolerance', () {
      const state = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 8),
      );

      expect(state.isAtLiveEdge, isTrue,
          reason: '8s is inside the 15s default');
      expect(state.isAtLiveEdgeWithin(const Duration(seconds: 3)), isFalse,
          reason: 'a low-latency host can tighten the tolerance');
      expect(state.isAtLiveEdgeWithin(const Duration(seconds: 30)), isTrue,
          reason: 'a long-segment host can widen it');
    });
  });

  group('PlaybackState.positionBasis', () {
    test('liveWindow basis flags position as window-relative', () {
      const state = PlaybackState(
        state: PlayerState.playing,
        positionBasis: PositionBasis.liveWindow,
      );

      expect(state.isPositionWindowRelative, isTrue);
    });

    test('basis is independent of liveEdgeOffset being known', () {
      // A live item whose basis native already knows, but whose edge offset it
      // cannot answer yet (playlist just loaded).
      const state = PlaybackState(
        state: PlayerState.buffering,
        positionBasis: PositionBasis.liveWindow,
      );

      expect(state.isPositionWindowRelative, isTrue);
      expect(state.liveEdgeOffset, isNull);
      expect(state.isAtLiveEdge, isFalse);
    });
  });

  group('PlaybackState copyWith / equality round trip', () {
    test('copyWith carries both new fields forward when unspecified', () {
      const original = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 6),
        positionBasis: PositionBasis.liveWindow,
      );

      final copy = original.copyWith(position: const Duration(seconds: 30));

      expect(copy.liveEdgeOffset, const Duration(seconds: 6));
      expect(copy.positionBasis, PositionBasis.liveWindow);
    });

    test('copyWith updates both new fields', () {
      const original = PlaybackState(state: PlayerState.playing);

      final copy = original.copyWith(
        liveEdgeOffset: const Duration(seconds: 42),
        positionBasis: PositionBasis.liveWindow,
      );

      expect(copy.liveEdgeOffset, const Duration(seconds: 42));
      expect(copy.positionBasis, PositionBasis.liveWindow);
      expect(copy.isAtLiveEdge, isFalse);
    });

    test('clearLiveEdgeOffset resets a previously reported offset to null', () {
      const original = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 6),
      );

      final cleared = original.copyWith(clearLiveEdgeOffset: true);

      expect(cleared.liveEdgeOffset, isNull,
          reason: 'a nullable field cannot be cleared by `?? this.field` '
              'alone — this flag is why load() can drop a stale live offset');
      expect(cleared.isAtLiveEdge, isFalse);
    });

    test('clearLiveEdgeOffset wins over a simultaneously passed value', () {
      const original = PlaybackState(state: PlayerState.playing);

      final cleared = original.copyWith(
        liveEdgeOffset: const Duration(seconds: 3),
        clearLiveEdgeOffset: true,
      );

      expect(cleared.liveEdgeOffset, isNull);
    });

    test('== and hashCode account for liveEdgeOffset', () {
      const a = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 6),
      );
      const b = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 6),
      );
      const c = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 90),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)),
          reason: 'a state that moved away from the live edge is not equal to '
              'one riding it — otherwise a stall would never notify listeners');
      expect(a, isNot(equals(const PlaybackState(state: PlayerState.playing))));
    });

    test('== and hashCode account for positionBasis', () {
      const absolute = PlaybackState(state: PlayerState.playing);
      const window = PlaybackState(
        state: PlayerState.playing,
        positionBasis: PositionBasis.liveWindow,
      );

      expect(absolute, isNot(equals(window)));
      expect(absolute.hashCode, isNot(equals(window.hashCode)));
    });

    test('toString surfaces both new fields for diagnostics', () {
      const state = PlaybackState(
        state: PlayerState.playing,
        liveEdgeOffset: Duration(seconds: 6),
        positionBasis: PositionBasis.liveWindow,
      );

      expect(state.toString(), contains('liveWindow'));
      expect(state.toString(), contains('liveEdgeOffset'));
    });
  });
}

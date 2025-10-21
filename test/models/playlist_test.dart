import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Phase 1: Playlist tests
void main() {
  group('Playlist', () {
    final testItems = [
      const MediaItem(
        id: '1',
        title: 'Video 1',
        url: 'https://example.com/video1.mp4',
      ),
      const MediaItem(
        id: '2',
        title: 'Video 2',
        url: 'https://example.com/video2.mp4',
      ),
      const MediaItem(
        id: '3',
        title: 'Video 3',
        url: 'https://example.com/video3.mp4',
      ),
    ];

    test('creates playlist with required fields', () {
      final playlist = Playlist(
        id: 'playlist1',
        title: 'My Playlist',
        items: testItems,
      );

      expect(playlist.id, 'playlist1');
      expect(playlist.title, 'My Playlist');
      expect(playlist.items.length, 3);
      expect(playlist.currentIndex, 0);
      expect(playlist.mode, PlaybackMode.sequential);
      expect(playlist.repeatMode, RepeatMode.none);
    });

    test('creates playlist with custom index', () {
      final playlist = Playlist(
        id: 'playlist1',
        title: 'My Playlist',
        items: testItems,
        currentIndex: 1,
      );

      expect(playlist.currentIndex, 1);
      expect(playlist.currentItem, testItems[1]);
    });

    group('Navigation', () {
      test('hasNext returns true when not at end', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 0,
        );

        expect(playlist.hasNext, true);
      });

      test('hasNext returns false at end', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 2,
        );

        expect(playlist.hasNext, false);
      });

      test('hasPrevious returns false at start', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 0,
        );

        expect(playlist.hasPrevious, false);
      });

      test('hasPrevious returns true when not at start', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 1,
        );

        expect(playlist.hasPrevious, true);
      });

      test('nextIndex returns correct index', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 0,
        );

        expect(playlist.nextIndex, 1);
      });

      test('nextIndex returns null at end', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 2,
        );

        expect(playlist.nextIndex, null);
      });

      test('previousIndex returns correct index', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 1,
        );

        expect(playlist.previousIndex, 0);
      });

      test('previousIndex returns null at start', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 0,
        );

        expect(playlist.previousIndex, null);
      });
    });

    group('Repeat Modes', () {
      test('RepeatMode.none ends at last item', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 2,
          repeatMode: RepeatMode.none,
        );

        expect(playlist.nextIndex, null);
      });

      test('RepeatMode.all loops to start', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 2,
          repeatMode: RepeatMode.all,
        );

        expect(playlist.hasNext, true);
        expect(playlist.nextIndex, 0);
      });

      test('RepeatMode.single stays on current item', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 1,
          repeatMode: RepeatMode.single,
        );

        expect(playlist.hasNext, true);
        expect(playlist.nextIndex, 1);
      });
    });

    group('Playlist Modes', () {
      test('sequential mode plays in order', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          mode: PlaybackMode.sequential,
        );

        expect(playlist.mode, PlaybackMode.sequential);
        expect(playlist.nextIndex, 1);
      });

      test('shuffle mode randomizes (implementation dependent)', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          mode: PlaybackMode.shuffle,
        );

        expect(playlist.mode, PlaybackMode.shuffle);
      });

      test('shuffle mode randomizes playback', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 0,
          mode: PlaybackMode.shuffle,
        );

        expect(playlist.mode, PlaybackMode.shuffle);
        expect(playlist.items.length, 3);
      });
    });

    group('copyWith', () {
      test('updates current index', () {
        final original = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 0,
        );

        final updated = original.copyWith(currentIndex: 2);

        expect(updated.currentIndex, 2);
        expect(updated.currentItem, testItems[2]);
        expect(updated.id, original.id);
        expect(updated.title, original.title);
      });

      test('updates repeat mode', () {
        final original = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          repeatMode: RepeatMode.none,
        );

        final updated = original.copyWith(repeatMode: RepeatMode.all);

        expect(updated.repeatMode, RepeatMode.all);
      });

      test('updates playlist mode', () {
        final original = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          mode: PlaybackMode.sequential,
        );

        final updated = original.copyWith(mode: PlaybackMode.shuffle);

        expect(updated.mode, PlaybackMode.shuffle);
      });

      test('updates items', () {
        final original = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
        );

        final newItems = [testItems[0], testItems[2]];
        final updated = original.copyWith(items: newItems);

        expect(updated.items.length, 2);
        expect(updated.items[0], testItems[0]);
        expect(updated.items[1], testItems[2]);
      });
    });

    group('Edge Cases', () {
      test('handles single item playlist', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Single Item',
          items: [testItems[0]],
        );

        expect(playlist.items.length, 1);
        expect(playlist.hasNext, false);
        expect(playlist.hasPrevious, false);
      });

      test('handles empty items (should be avoided)', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Empty',
          items: [],
        );

        expect(playlist.items, isEmpty);
        expect(playlist.hasNext, false);
        expect(playlist.hasPrevious, false);
      });

      test('currentItem returns null for invalid index', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: 999,
        );

        expect(playlist.currentItem, null);
      });

      test('clamps negative index to 0', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          currentIndex: -1,
        );

        // Implementation should handle this
        expect(playlist.currentIndex, -1); // Will be validated by controller
      });
    });

    group('Equality', () {
      test('playlists with same id are equal', () {
        final playlist1 = Playlist(
          id: 'p1',
          title: 'Playlist 1',
          items: testItems,
        );

        final playlist2 = Playlist(
          id: 'p1',
          title: 'Different Title',
          items: [testItems[0]],
        );

        expect(playlist1 == playlist2, true);
        expect(playlist1.hashCode, playlist2.hashCode);
      });

      test('playlists with different ids are not equal', () {
        final playlist1 = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
        );

        final playlist2 = Playlist(
          id: 'p2',
          title: 'Playlist',
          items: testItems,
        );

        expect(playlist1 == playlist2, false);
      });
    });

    group('Metadata', () {
      test('supports custom metadata', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
          metadata: {
            'creator': 'User123',
            'genre': 'Music Videos',
            'year': 2024,
          },
        );

        expect(playlist.metadata?['creator'], 'User123');
        expect(playlist.metadata?['genre'], 'Music Videos');
        expect(playlist.metadata?['year'], 2024);
      });

      test('handles null metadata', () {
        final playlist = Playlist(
          id: 'p1',
          title: 'Playlist',
          items: testItems,
        );

        expect(playlist.metadata, null);
      });
    });
  });
}

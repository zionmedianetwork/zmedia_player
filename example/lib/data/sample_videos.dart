import 'package:zmedia_player/zmedia_player.dart';

/// Sample video URLs for demonstration
class SampleVideos {
  static final List<MediaItem> videos = [
    MediaItem(
      id: '1',
      title: 'Big Buck Bunny',
      artist: 'Blender Foundation',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      artworkUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/800px-Big_buck_bunny_poster_big.jpg',
      duration: const Duration(minutes: 9, seconds: 56),
      mediaType: MediaType.video,
      metadata: {
        'description':
            'A large and lovable rabbit deals with three tiny bullies.',
        'year': '2008',
        'genre': 'Animation',
      },
    ),
    MediaItem(
      id: '2',
      title: 'Elephant\'s Dream',
      artist: 'Blender Foundation',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      artworkUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e8/Elephants_Dream_s5_both.jpg/800px-Elephants_Dream_s5_both.jpg',
      duration: const Duration(minutes: 10, seconds: 53),
      mediaType: MediaType.video,
      metadata: {
        'description': 'Two friends explore a surreal mechanical landscape.',
        'year': '2006',
        'genre': 'Sci-Fi',
      },
    ),
    MediaItem(
      id: '3',
      title: 'For Bigger Blazes',
      artist: 'Google',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      artworkUrl:
          'https://via.placeholder.com/800x450/FF6B6B/FFFFFF?text=For+Bigger+Blazes',
      duration: const Duration(seconds: 15),
      mediaType: MediaType.video,
      metadata: {
        'description': 'Sample video for testing purposes.',
        'year': '2018',
        'genre': 'Demo',
      },
    ),
    MediaItem(
      id: '4',
      title: 'For Bigger Escape',
      artist: 'Google',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
      artworkUrl:
          'https://via.placeholder.com/800x450/4ECDC4/FFFFFF?text=For+Bigger+Escape',
      duration: const Duration(seconds: 15),
      mediaType: MediaType.video,
      metadata: {
        'description': 'Experience the great outdoors.',
        'year': '2018',
        'genre': 'Travel',
      },
    ),
    MediaItem(
      id: '5',
      title: 'For Bigger Fun',
      artist: 'Google',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
      artworkUrl:
          'https://via.placeholder.com/800x450/95E1D3/FFFFFF?text=For+Bigger+Fun',
      duration: const Duration(seconds: 15),
      mediaType: MediaType.video,
      metadata: {
        'description': 'Fun and entertainment for everyone.',
        'year': '2018',
        'genre': 'Entertainment',
      },
    ),
    MediaItem(
      id: '6',
      title: 'For Bigger Joyrides',
      artist: 'Google',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
      artworkUrl:
          'https://via.placeholder.com/800x450/F38181/FFFFFF?text=For+Bigger+Joyrides',
      duration: const Duration(seconds: 15),
      mediaType: MediaType.video,
      metadata: {
        'description': 'Take a joyride through beautiful landscapes.',
        'year': '2018',
        'genre': 'Adventure',
      },
    ),
    MediaItem(
      id: '7',
      title: 'Sintel',
      artist: 'Blender Foundation',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      artworkUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/5/50/Sintel_poster.jpg/800px-Sintel_poster.jpg',
      duration: const Duration(minutes: 14, seconds: 48),
      mediaType: MediaType.video,
      metadata: {
        'description': 'A lonely young woman finds a dragon.',
        'year': '2010',
        'genre': 'Fantasy',
      },
    ),
    MediaItem(
      id: '8',
      title: 'Tears of Steel',
      artist: 'Blender Foundation',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
      artworkUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/6/66/Tears_of_Steel_-_title_screen.jpg/800px-Tears_of_Steel_-_title_screen.jpg',
      duration: const Duration(minutes: 12, seconds: 14),
      mediaType: MediaType.video,
      metadata: {
        'description': 'A group of warriors face a robot menace.',
        'year': '2012',
        'genre': 'Sci-Fi',
      },
    ),
  ];

  /// Get a default video for quick testing
  static MediaItem get defaultVideo => videos[0];

  /// Get playlist with first 5 videos
  static Playlist get samplePlaylist => Playlist(
        id: 'sample_playlist',
        title: 'Sample Playlist',
        items: videos.take(5).toList(),
        currentIndex: 0,
        mode: PlaybackMode.sequential,
        repeatMode: RepeatMode.none,
      );

  /// Get full playlist
  static Playlist get fullPlaylist => Playlist(
        id: 'full_playlist',
        title: 'All Videos',
        items: videos,
        currentIndex: 0,
        mode: PlaybackMode.sequential,
        repeatMode: RepeatMode.none,
      );

  /// Get a specific video by ID
  static MediaItem? getVideoById(String id) {
    try {
      return videos.firstWhere((video) => video.id == id);
    } catch (e) {
      return null;
    }
  }
}

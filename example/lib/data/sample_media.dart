import 'package:zmedia_player/zmedia_player.dart';

/// Reusable sample media items used across the feature gallery pages.
///
/// All MP4 sources are from Google's public GCS sample bucket.
/// The HLS source is Apple's bipbop reference stream.
/// The DASH source is Akamai's Big Buck Bunny DASH manifest.
class SampleMedia {
  SampleMedia._();

  // ---------------------------------------------------------------------------
  // Base URLs
  // ---------------------------------------------------------------------------

  static const _gcs =
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample';

  // ---------------------------------------------------------------------------
  // Individual MP4 items
  // ---------------------------------------------------------------------------

  static const bigBuckBunny = MediaItem(
    id: 'bbb',
    title: 'Big Buck Bunny',
    artist: 'Blender Foundation',
    url: '$_gcs/BigBuckBunny.mp4',
    artworkUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/800px-Big_buck_bunny_poster_big.jpg',
    duration: Duration(minutes: 9, seconds: 56),
    mediaType: MediaType.video,
  );

  static const elephantsDream = MediaItem(
    id: 'ed',
    title: 'Elephants Dream',
    artist: 'Blender Foundation',
    url: '$_gcs/ElephantsDream.mp4',
    artworkUrl:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6c/Elephants_Dream_s5_both.jpg/800px-Elephants_Dream_s5_both.jpg',
    duration: Duration(minutes: 10, seconds: 54),
    mediaType: MediaType.video,
  );

  static const forBiggerBlazes = MediaItem(
    id: 'fbb',
    title: 'For Bigger Blazes',
    artist: 'Google',
    url: '$_gcs/ForBiggerBlazes.mp4',
    duration: Duration(seconds: 15),
    mediaType: MediaType.video,
  );

  static const forBiggerEscapes = MediaItem(
    id: 'fbe',
    title: 'For Bigger Escapes',
    artist: 'Google',
    url: '$_gcs/ForBiggerEscapes.mp4',
    duration: Duration(seconds: 15),
    mediaType: MediaType.video,
  );

  static const forBiggerFun = MediaItem(
    id: 'fbf',
    title: 'For Bigger Fun',
    artist: 'Google',
    url: '$_gcs/ForBiggerFun.mp4',
    duration: Duration(seconds: 60),
    mediaType: MediaType.video,
  );

  static const forBiggerJoyrides = MediaItem(
    id: 'fbj',
    title: 'For Bigger Joyrides',
    artist: 'Google',
    url: '$_gcs/ForBiggerJoyrides.mp4',
    duration: Duration(seconds: 15),
    mediaType: MediaType.video,
  );

  static const sintel = MediaItem(
    id: 'sintel',
    title: 'Sintel',
    artist: 'Blender Foundation',
    url: '$_gcs/Sintel.mp4',
    duration: Duration(minutes: 14, seconds: 48),
    mediaType: MediaType.video,
  );

  static const tearsOfSteel = MediaItem(
    id: 'tos',
    title: 'Tears of Steel',
    artist: 'Blender Foundation',
    url: '$_gcs/TearsOfSteel.mp4',
    duration: Duration(minutes: 12, seconds: 14),
    mediaType: MediaType.video,
  );

  // ---------------------------------------------------------------------------
  // HLS adaptive stream — Apple bipbop reference stream
  // ---------------------------------------------------------------------------

  /// Apple's official bipbop HLS test stream (fMP4 variant).
  /// This stream provides multiple quality levels for ABR testing.
  static const hlsStream = MediaItem(
    id: 'hls_bipbop',
    title: 'Apple Bipbop HLS (fMP4)',
    artist: 'Apple Inc.',
    url:
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
    mimeType: 'application/x-mpegURL',
    mediaType: MediaType.video,
  );

  // ---------------------------------------------------------------------------
  // DASH adaptive stream — Akamai Big Buck Bunny
  // ---------------------------------------------------------------------------

  /// Akamai DASH test stream (Big Buck Bunny, 30 fps).
  static const dashStream = MediaItem(
    id: 'dash_bbb',
    title: 'Big Buck Bunny DASH',
    artist: 'Akamai / Blender Foundation',
    url: 'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
    mimeType: 'application/dash+xml',
    mediaType: MediaType.video,
  );

  // ---------------------------------------------------------------------------
  // Subtitle tracks (WebVTT hosted on GitHub Gist for demo purposes)
  // The tracks are plain WebVTT so they parse cleanly with SubtitleService.
  // NOTE: setSubtitleTrack validates tracks against those the native player
  // reports.  These objects are provided so the page can show how the API
  // is called; actual in-stream subtitles come from the player via
  // onSubtitleTracksChanged.
  // ---------------------------------------------------------------------------

  static final List<SubtitleTrack> demoCaptionTracks = [
    const SubtitleTrack(
      id: 'sub_en',
      title: 'English',
      language: 'en',
      format: SubtitleFormat.webvtt,
      isDefault: true,
    ),
    const SubtitleTrack(
      id: 'sub_es',
      title: 'Spanish',
      language: 'es',
      format: SubtitleFormat.webvtt,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Playlist helper
  // ---------------------------------------------------------------------------

  /// Returns a [Playlist] suitable for the playlist demo page.
  static Playlist samplePlaylist({
    PlaybackMode mode = PlaybackMode.sequential,
    RepeatMode repeatMode = RepeatMode.none,
  }) {
    return Playlist(
      id: 'sample_playlist',
      title: 'Sample Videos',
      items: const [
        bigBuckBunny,
        forBiggerBlazes,
        forBiggerEscapes,
        forBiggerFun,
        forBiggerJoyrides,
        elephantsDream,
      ],
      mode: mode,
      repeatMode: repeatMode,
    );
  }
}

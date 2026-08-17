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

  // Reliable progressive MP4 sources that include BOTH video and audio tracks.
  // NOTE: the old Google GCS sample bucket
  // (commondatastorage.googleapis.com/gtv-videos-bucket) now returns HTTP 403.
  // The test-videos.co.uk clips are reachable but VIDEO-ONLY (no audio), so we
  // use sources verified (via ffprobe) to carry an audio track: the
  // ExoPlayer test-media GCS bucket's full Big Buck Bunny, Flutter's
  // bee/butterfly clips, and W3Schools' BBB clip.
  //
  // The `archive.org/download/BigBuckBunny_124/...` URL this constant used
  // to point at is unreliable — verified via repeated
  // `curl -s -o /dev/null -w '%{http_code}' -L <url>` runs returning a
  // consistent HTTP 500 for that exact item/path, and a *different*
  // archive.org BBB item (`BigBuckBunny_328/BigBuckBunny_512kb.mp4`, same
  // 9:56 duration, video+audio confirmed via ffprobe) taking 60+ seconds to
  // resolve through archive.org's CDN redirect — too slow to be a usable
  // fixture regardless. This bucket is Google-hosted, specifically
  // maintained for ExoPlayer's own test suite, and returned a consistent,
  // fast HTTP 200 with the same 9:56 duration (video h264 + audio aac,
  // confirmed via ffprobe) in repeated checks.
  static const _bbbFull =
      'https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4';
  static const _bbbShort = 'https://www.w3schools.com/html/mov_bbb.mp4';
  static const _bee =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
  static const _butterfly =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  // ---------------------------------------------------------------------------
  // Individual MP4 items (all sources include an audio track)
  // ---------------------------------------------------------------------------

  static const bigBuckBunny = MediaItem(
    id: 'bbb',
    title: 'Big Buck Bunny',
    artist: 'Blender Foundation',
    // Direct HTTP 200 (no redirect) + audio — reliable first-load on iOS.
    url: _bbbShort,
    // NOTE: the `/thumb/.../800px-...jpg` Wikimedia thumbnail path below
    // returns HTTP 400 (malformed thumb request) — verified via
    // `curl -s -o /dev/null -w '%{http_code}' -L <url>`. This is the
    // full-size original file at the same Commons path (no /thumb/ prefix,
    // no width suffix), verified HTTP 200 `image/jpeg`.
    artworkUrl:
        'https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg',
    duration: Duration(seconds: 10),
    mediaType: MediaType.video,
  );

  static const elephantsDream = MediaItem(
    id: 'butterfly',
    title: 'Butterfly',
    artist: 'Flutter',
    url: _butterfly,
    duration: Duration(seconds: 4),
    mediaType: MediaType.video,
  );

  static const forBiggerBlazes = MediaItem(
    id: 'bbb_short',
    title: 'Big Buck Bunny (short)',
    artist: 'Blender Foundation',
    url: _bbbShort,
    duration: Duration(seconds: 10),
    mediaType: MediaType.video,
  );

  static const forBiggerEscapes = MediaItem(
    id: 'bee',
    title: 'Bee',
    artist: 'Flutter',
    url: _bee,
    duration: Duration(seconds: 5),
    mediaType: MediaType.video,
  );

  // Full ~10-minute Big Buck Bunny (Google's ExoPlayer test-media bucket —
  // see the _bbbFull doc above) — kept as a longer sample for seek/playlist
  // demos, not as the primary item.
  static const forBiggerFun = MediaItem(
    id: 'bbb_full',
    title: 'Big Buck Bunny (full · 10 min)',
    artist: 'Blender Foundation',
    url: _bbbFull,
    duration: Duration(minutes: 9, seconds: 56),
    mediaType: MediaType.video,
  );

  static const forBiggerJoyrides = MediaItem(
    id: 'bee2',
    title: 'Bee (clip)',
    artist: 'Flutter',
    url: _bee,
    duration: Duration(seconds: 5),
    mediaType: MediaType.video,
  );

  static const sintel = MediaItem(
    id: 'bbb_short2',
    title: 'Big Buck Bunny (clip)',
    artist: 'Blender Foundation',
    url: _bbbShort,
    duration: Duration(seconds: 10),
    mediaType: MediaType.video,
  );

  static const tearsOfSteel = MediaItem(
    id: 'butterfly3',
    title: 'Butterfly (alt)',
    artist: 'Flutter',
    url: _butterfly,
    duration: Duration(seconds: 4),
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
  // HLS live stream — Unified Streaming demo channel
  // ---------------------------------------------------------------------------

  /// Unified Streaming's public HLS live demo channel. Used by the Stage 7a
  /// measurement harness's off-screen-pause bandwidth check
  /// (`live_offscreen_bandwidth_page.dart`).
  ///
  /// The previous fixture here (Akamai's `cph-p2p-msl.akamaized.net` test
  /// channel) looked live under a naive check — its master playlist
  /// returned 200 and its child playlist had no `EXT-X-ENDLIST` — but the
  /// child's variant URI actually 404'd, so "no ENDLIST" was true only
  /// because we'd fetched an error page, not a real playlist. Do not
  /// substitute another "live" URL without verifying it properly:
  ///   1. Master playlist request must return HTTP 200.
  ///   2. Resolve the first variant URI from the master and fetch it: the
  ///      child must return HTTP 200 AND contain `#EXTINF` segment lines.
  ///      Zero `#EXTINF` lines means you fetched an error page, not a
  ///      playlist, even if the HTTP status was 200.
  ///   3. The child must NOT contain `#EXT-X-ENDLIST` (that marks VOD).
  ///   4. Fetch the child again ~15s later and confirm
  ///      `#EXT-X-MEDIA-SEQUENCE` has advanced — this is the only positive
  ///      proof of liveness; steps 1-3 alone are not sufficient.
  static const hlsLiveStream = MediaItem(
    id: 'hls_live_unified_streaming',
    title: 'Unified Streaming Live (demo channel)',
    artist: 'Unified Streaming',
    url: 'https://demo.unified-streaming.com/k8s/live/stable/live.isml/.m3u8',
    mimeType: 'application/x-mpegURL',
    mediaType: MediaType.video,
    isLive: true,
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
    MediaRepeatMode repeatMode = MediaRepeatMode.none,
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

import 'drm_config.dart';

/// Represents a media item that can be played by the media player.
class MediaItem {
  /// Unique identifier for the media item
  final String id;

  /// Display title of the media item
  final String title;

  /// Artist or creator name
  final String? artist;

  /// Album name (for audio content)
  final String? album;

  /// Duration of the media item
  final Duration? duration;

  /// URL or file path to the media content
  final String url;

  /// URL or path to artwork/thumbnail
  final String? artworkUrl;

  /// MIME type of the media content
  final String? mimeType;

  /// Custom HTTP headers for this specific media item
  final Map<String, String>? httpHeaders;

  /// Whether this is a video or audio-only content
  final MediaType mediaType;

  /// DRM configuration for protected content
  final DrmConfig? drmConfig;

  /// Additional metadata
  final Map<String, dynamic>? metadata;

  /// Whether this is a live stream (affects seeking and DVR capabilities)
  final bool isLive;

  /// Explicit streaming container/manifest format for [url].
  ///
  /// Decides which of `MediaConfig.hlsConfig` / `MediaConfig.dashConfig`
  /// applies to this item — and therefore whether `enableDvr`,
  /// `liveLatency` and the bitrate bounds reach the player at all.
  ///
  /// `null` (the default) means "infer it from [url]", which is what every
  /// item did before this field existed; see [resolvedStreamingFormat] for
  /// the exact inference rules. Set it explicitly whenever the URL does not
  /// end in `.m3u8`/`.mpd` — CDN rewrites, signed/tokenised URLs whose path
  /// is masked, extension-less manifest endpoints, or a URL whose path
  /// happens to mention the *other* format:
  ///
  /// ```dart
  /// MediaItem(
  ///   id: 'live',
  ///   title: 'Live',
  ///   url: 'https://cdn.example.com/hls.m3u8-archive/eu/manifest',
  ///   isLive: true,
  ///   streamingFormat: StreamingFormat.dash,
  /// );
  /// ```
  ///
  /// An explicit value always wins over inference, on the Dart side and on
  /// both native platforms (it is serialized to native as the
  /// `streamingFormat` key of the `mediaItem` payload).
  final StreamingFormat? streamingFormat;

  const MediaItem({
    required this.id,
    required this.title,
    required this.url,
    this.artist,
    this.album,
    this.duration,
    this.artworkUrl,
    this.mimeType,
    this.httpHeaders,
    this.mediaType = MediaType.video,
    this.drmConfig,
    this.metadata,
    this.isLive = false,
    this.streamingFormat,
  });

  /// The streaming format that actually applies to this item: the explicit
  /// [streamingFormat] when set, otherwise inferred from [url].
  ///
  /// Inference looks at the URL's **path only** — the query string and
  /// fragment are stripped first, so a signed URL like
  /// `…/manifest.mpd?token=…&hint=.m3u8` still resolves to
  /// [StreamingFormat.dash]. A path ending (case-insensitively) in `.m3u8`
  /// is [StreamingFormat.hls], a path ending in `.mpd` is
  /// [StreamingFormat.dash], and everything else — including
  /// `/hls.m3u8-archive/…/manifest` and any URL that merely *mentions* a
  /// manifest extension mid-path — is [StreamingFormat.progressive].
  ///
  /// Because the match is `endsWith` on a single path, at most one format
  /// can ever match, so the result is deterministic and order-independent.
  /// A malformed/unparseable [url] never throws: it falls back to a plain
  /// truncation at the first `?`/`#` and the same `endsWith` test.
  ///
  /// Note that [StreamingFormat.progressive] means "no streaming config
  /// applies" — neither `hlsConfig` nor `dashConfig` is consulted for such
  /// an item, so `enableDvr` is effectively `false` for it.
  StreamingFormat get resolvedStreamingFormat =>
      streamingFormat ?? StreamingFormat.fromUrl(url);

  /// Creates a copy of this media item with updated values
  MediaItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? url,
    String? artworkUrl,
    String? mimeType,
    Map<String, String>? httpHeaders,
    MediaType? mediaType,
    DrmConfig? drmConfig,
    Map<String, dynamic>? metadata,
    bool? isLive,
    StreamingFormat? streamingFormat,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      url: url ?? this.url,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      mimeType: mimeType ?? this.mimeType,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      mediaType: mediaType ?? this.mediaType,
      drmConfig: drmConfig ?? this.drmConfig,
      metadata: metadata ?? this.metadata,
      isLive: isLive ?? this.isLive,
      streamingFormat: streamingFormat ?? this.streamingFormat,
    );
  }

  /// Converts the media item to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration?.inMilliseconds,
      'url': url,
      'artworkUrl': artworkUrl,
      'mimeType': mimeType,
      'httpHeaders': httpHeaders,
      'mediaType': mediaType.name,
      'drmConfig': drmConfig?.toMap(),
      'metadata': metadata,
      'isLive': isLive,
      // Null when the item leaves format detection to inference; native
      // then runs the same path-based inference as
      // [StreamingFormat.fromUrl]. See [streamingFormat].
      'streamingFormat': streamingFormat?.name,
    };
  }

  /// Creates a media item from a map
  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      duration: map['duration'] != null
          ? Duration(milliseconds: map['duration'] as int)
          : null,
      url: map['url'] as String,
      artworkUrl: map['artworkUrl'] as String?,
      mimeType: map['mimeType'] as String?,
      httpHeaders: map['httpHeaders'] != null
          ? Map<String, String>.from(map['httpHeaders'] as Map)
          : null,
      mediaType: MediaType.values.firstWhere(
        (type) => type.name == map['mediaType'],
        orElse: () => MediaType.video,
      ),
      drmConfig: map['drmConfig'] != null
          ? DrmConfig.fromMap(map['drmConfig'] as Map<String, dynamic>)
          : null,
      metadata: map['metadata'] as Map<String, dynamic>?,
      isLive: map['isLive'] as bool? ?? false,
      // An unknown/absent name deliberately decodes to `null` (i.e. "infer
      // from the URL") rather than to a wrong-but-concrete format.
      streamingFormat: StreamingFormat.fromName(map['streamingFormat']),
    );
  }

  /// Identity equality: two [MediaItem]s are equal when their [id]s match.
  ///
  /// This is deliberate and long-standing — playlists look items up by
  /// identity, so no content field ([url], [isLive], [streamingFormat],
  /// [drmConfig], …) participates in equality. Give two variants of the
  /// same logical stream different [id]s if you need to tell them apart.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    // An unset streamingFormat is rendered as `auto(<resolved>)` so a log line
    // shows both that inference was used AND what it decided — the single most
    // useful thing to know when a streaming config unexpectedly did not apply.
    final format =
        streamingFormat?.name ?? 'auto(${resolvedStreamingFormat.name})';
    return 'MediaItem(id: $id, title: $title, '
        'url: ${_redactUrlForDisplay(url)}, mediaType: $mediaType, '
        'isLive: $isLive, streamingFormat: $format)';
  }
}

/// M-19: strips the query string and fragment from [url] before
/// [MediaItem.toString] embeds it. Query strings frequently carry signed
/// cookies/auth tokens for authenticated media URLs, and `toString()`
/// output routinely ends up in logs (print statements, log frameworks,
/// debugger watch expressions) that this package has no control over once
/// emitted.
///
/// Deliberately does plain substring truncation at the first `?`/`#` rather
/// than round-tripping through [Uri] — `Uri.replace(query: '', fragment:
/// '')` sets an *empty* query/fragment component rather than removing it,
/// which leaves a dangling `?`/`#` in the output. Never throws: an
/// unparseable/malformed [url] is truncated the same way, rather than being
/// passed through unredacted. Mirrors `_redactUrlForCrashReporting` in
/// `lib/src/core/media_player.dart` (kept as a separate, self-contained
/// copy here rather than a shared import, to avoid coupling this model file
/// to `core/`).
String _redactUrlForDisplay(String url) {
  final queryIndex = url.indexOf('?');
  final fragmentIndex = url.indexOf('#');
  var cut = url.length;
  if (queryIndex != -1 && queryIndex < cut) cut = queryIndex;
  if (fragmentIndex != -1 && fragmentIndex < cut) cut = fragmentIndex;
  return url.substring(0, cut);
}

/// The streaming container/manifest format of a [MediaItem]'s URL.
///
/// Decides which streaming config applies to an item: [hls] selects
/// `MediaConfig.hlsConfig`, [dash] selects `MediaConfig.dashConfig`, and
/// [progressive] selects neither (a plain file has no manifest-level
/// configuration — `enableDvr`, `liveLatency` and the bitrate bounds have
/// nothing to apply to).
///
/// Set it explicitly via [MediaItem.streamingFormat] whenever the URL is not
/// self-describing; leave it `null` to fall back to [fromUrl] inference.
enum StreamingFormat {
  /// HTTP Live Streaming (`.m3u8` manifest). Selects `MediaConfig.hlsConfig`.
  hls,

  /// MPEG-DASH (`.mpd` manifest). Selects `MediaConfig.dashConfig`.
  dash,

  /// A single, non-adaptive media file (MP4/WebM/MP3/…) served over plain
  /// HTTP range requests, or any local `file://` asset. No streaming config
  /// applies.
  progressive;

  /// Decodes a serialized [StreamingFormat] name (`'hls'`/`'dash'`/
  /// `'progressive'`), returning `null` for `null`, a non-`String`, or an
  /// unrecognised name.
  ///
  /// `null` means "unspecified — infer from the URL", which is why an
  /// unrecognised value maps to `null` rather than to an arbitrary concrete
  /// format: a newer producer sending a format this build does not know
  /// about degrades to inference instead of being silently mis-typed.
  static StreamingFormat? fromName(Object? name) {
    if (name is! String) return null;
    for (final format in StreamingFormat.values) {
      if (format.name == name) return format;
    }
    return null;
  }

  /// Infers the format from [url]'s **path**, ignoring query and fragment.
  ///
  /// Rules, in order:
  /// 1. Parse [url]; on failure fall back to truncating it at the first
  ///    `?`/`#`. This never throws for any input.
  /// 2. Lower-case the path and test `endsWith('.m3u8')` -> [hls], then
  ///    `endsWith('.mpd')` -> [dash].
  /// 3. Anything else -> [progressive].
  ///
  /// Because step 2 matches the *end* of a single path, at most one branch
  /// can ever match — the result does not depend on the test order, and a
  /// path such as `/hls.m3u8-archive/eu/manifest.mpd` correctly resolves to
  /// [dash]. Conversely, a manifest served from an extension-less or
  /// rewritten path resolves to [progressive]; use
  /// [MediaItem.streamingFormat] to state the format explicitly in that
  /// case.
  static StreamingFormat fromUrl(String url) {
    final path = _pathOf(url).toLowerCase();
    if (path.endsWith('.m3u8')) return StreamingFormat.hls;
    if (path.endsWith('.mpd')) return StreamingFormat.dash;
    return StreamingFormat.progressive;
  }

  /// [url]'s path component, or a query/fragment-stripped truncation of it
  /// when [url] cannot be parsed as a URI. Never throws.
  static String _pathOf(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path;
    if (path != null && path.isNotEmpty) return path;
    // Unparseable, or parseable but path-less (e.g. an opaque or
    // scheme-only URI): degrade to plain truncation rather than guessing.
    final queryIndex = url.indexOf('?');
    final fragmentIndex = url.indexOf('#');
    var cut = url.length;
    if (queryIndex != -1 && queryIndex < cut) cut = queryIndex;
    if (fragmentIndex != -1 && fragmentIndex < cut) cut = fragmentIndex;
    return url.substring(0, cut);
  }
}

/// Enum representing the type of media content
enum MediaType {
  /// Video content
  video,

  /// Audio-only content
  audio,
}

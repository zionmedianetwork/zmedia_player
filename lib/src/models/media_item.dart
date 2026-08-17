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
  });

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
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MediaItem(id: $id, title: $title, url: ${_redactUrlForDisplay(url)}, mediaType: $mediaType, isLive: $isLive)';
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

/// Enum representing the type of media content
enum MediaType {
  /// Video content
  video,

  /// Audio-only content
  audio,
}

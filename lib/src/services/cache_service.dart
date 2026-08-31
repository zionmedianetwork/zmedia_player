import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';
import '../core/media_config.dart';
import '../core/local_media_utils.dart';

/// Service for managing media caching
class CacheService {
  static const String _cacheDirName = 'zmedia_player_cache';
  static const String _metadataFileName = 'cache_metadata.json';

  late final Directory _cacheDir;
  late final File _metadataFile;
  final CacheConfig _config;

  /// Cache metadata storage
  final Map<String, CacheEntry> _metadata = {};

  /// Current cache size in bytes
  int _currentCacheSize = 0;

  /// Whether the service is initialized
  bool _isInitialized = false;

  /// Stream controller for download progress
  final StreamController<DownloadProgress> _downloadProgressController =
      StreamController<DownloadProgress>.broadcast();

  /// Active download operations
  final Map<String, http.Client> _activeDownloads = {};

  /// Factory used to create a new [http.Client] per download (H-12: kept as
  /// a factory, not a single shared client, so [cancelDownload] can close
  /// just one in-flight download without invalidating every other active
  /// download on this service). Overridable for tests (e.g. with
  /// `MockClient.streaming`) via the [httpClientFactory] constructor param.
  final http.Client Function() _httpClientFactory;

  CacheService(this._config, {http.Client Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory ?? http.Client.new;

  /// Stream of download progress updates
  Stream<DownloadProgress> get downloadProgressStream =>
      _downloadProgressController.stream;

  /// Initialize the cache service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Determine cache directory
      if (_config.cacheDirectory != null) {
        _cacheDir = Directory(_config.cacheDirectory!);
      } else {
        final appDir = await _getAppCacheDirectory();
        _cacheDir = Directory(path.join(appDir.path, _cacheDirName));
      }

      // Create cache directory if it doesn't exist
      if (!await _cacheDir.exists()) {
        await _cacheDir.create(recursive: true);
      }

      _metadataFile = File(path.join(_cacheDir.path, _metadataFileName));

      // Load existing metadata
      await _loadMetadata();

      // Drop entries written by the pre-fix filename scheme (see
      // _invalidateLegacyCacheEntries) before anything else can hand one
      // out as a valid cache hit.
      await _invalidateLegacyCacheEntries();

      // Clean up expired entries
      await _cleanupExpiredEntries();

      _isInitialized = true;
    } catch (e) {
      throw CacheException('Failed to initialize cache service: $e');
    }
  }

  /// Get cached media data.
  ///
  /// **Deprecated (C-03a):** this loads the *entire* cached file into
  /// memory as a single [Uint8List] — for any real video/audio file that is
  /// enough to exhaust a low-end device's RAM, and it is never actually
  /// necessary: the file already lives on disk. Prefer [getCachedFileUri]
  /// (or [getCachedMediaItem], which builds a ready-to-[MediaItem.copyWith]-
  /// free [MediaItem] for you) and hand the resulting `file://` URI to the
  /// ordinary `MediaController.load()` / `MediaPlayer.load()` path, which
  /// streams from disk instead of buffering in Dart heap. Kept (not
  /// removed) because this package does not ship breaking API removals
  /// mid-cycle; it will keep working exactly as before.
  @Deprecated(
    'Buffers the whole cached file into memory. Use getCachedFileUri or '
    'getCachedMediaItem instead, which return a file:// URI/MediaItem that '
    'plays directly from disk via MediaController.load()/MediaPlayer.load().',
  )
  Future<Uint8List?> getCachedMedia(String mediaId) async {
    if (!_isInitialized) await initialize();

    final entry = _metadata[mediaId];
    if (entry == null || !entry.isValid) return null;

    try {
      final file = File(path.join(_cacheDir.path, entry.fileName));
      if (await file.exists()) {
        // Update last accessed time
        entry.lastAccessed = DateTime.now();
        await _saveMetadata();
        return await file.readAsBytes();
      }
    } catch (e) {
      // Remove invalid entry
      _metadata.remove(mediaId);
      await _saveMetadata();
    }

    return null;
  }

  /// Returns a `file://` URI pointing at the on-disk cache file for
  /// [mediaId], or `null` if there is no cache entry, the entry has expired
  /// (per [CacheEntry.isValid] / [CacheConfig.cacheExpiration]), or the
  /// underlying file is missing from disk (e.g. removed out-of-band).
  ///
  /// Unlike [getCachedMedia] this never reads the file's contents — it only
  /// resolves and returns a path, via [LocalMediaUtils.fileUri] so the
  /// result is directly usable as [MediaItem.url] (percent-encoding
  /// handled the same way local-file playback already requires — see
  /// `LocalMediaUtils`' dartdoc). The returned URI is accepted by
  /// [InputValidator.validateUrl] (`file` is a permitted media scheme)
  /// exactly like any other locally-sourced [MediaItem], so a cached item
  /// still goes through the normal `MediaController.load()` /
  /// `MediaPlayer.load()` path — including DRM fail-closed validation, for
  /// which a `file://` URL always fails the HTTPS check (offline DRM is not
  /// supported).
  ///
  /// A hit updates [CacheEntry.lastAccessed], the same LRU bookkeeping
  /// [getCachedMedia] already performs.
  Future<String?> getCachedFileUri(String mediaId) async {
    if (!_isInitialized) await initialize();

    final entry = _metadata[mediaId];
    if (entry == null || !entry.isValid) return null;

    try {
      final file = File(path.join(_cacheDir.path, entry.fileName));
      if (!await file.exists()) {
        // Mirrors getCachedMedia: a metadata entry with no backing file on
        // disk is not a valid cache hit — drop the stale entry.
        _metadata.remove(mediaId);
        await _saveMetadata();
        return null;
      }

      entry.lastAccessed = DateTime.now();
      await _saveMetadata();
      return LocalMediaUtils.fileUri(file.path);
    } catch (e) {
      _metadata.remove(mediaId);
      await _saveMetadata();
      return null;
    }
  }

  /// Returns a [MediaItem] ready to be played straight from the cache, or
  /// `null` under the same conditions as [getCachedFileUri] (no entry,
  /// expired, or the file is missing).
  ///
  /// This is a convenience wrapper around [getCachedFileUri]: it returns a
  /// copy of the [MediaItem] that was originally passed to
  /// [downloadAndCache]/[cacheMedia] (same id/title/artist/album/duration/
  /// artworkUrl/mimeType/mediaType/metadata/drmConfig) with only
  /// [MediaItem.url] swapped for the local `file://` URI, so a host can do
  /// "download, then play from cache" as:
  ///
  /// ```dart
  /// await cache.downloadAndCache(mediaItem);
  /// final cached = await cache.getCachedMediaItem(mediaItem.id);
  /// if (cached != null) await controller.load(cached);
  /// ```
  ///
  /// [MediaItem.drmConfig] is deliberately *preserved*, not stripped: if
  /// the original item carried DRM, the copy still does too, so it still
  /// routes through the same `MediaController.load()`/`MediaPlayer.load()`
  /// validation as any other item — and [InputValidator
  /// .validateMediaItemWithDrm] still rejects it, because a `file://` media
  /// URL can never satisfy the HTTPS requirement DRM enforces. That is
  /// correct, fail-closed behavior: this package has no offline DRM
  /// license flow, so a cached copy of DRM content must not be playable
  /// from disk.
  Future<MediaItem?> getCachedMediaItem(String mediaId) async {
    final uri = await getCachedFileUri(mediaId);
    if (uri == null) return null;

    final original = _metadata[mediaId]?.mediaItem;
    if (original == null) return null;

    return original.copyWith(url: uri);
  }

  /// Cache media data
  Future<void> cacheMedia(
      String mediaId, Uint8List data, MediaItem mediaItem) async {
    if (!_isInitialized) await initialize();

    if (!_config.enabled) return;

    // M-08: sanitize before it becomes part of a filename — see
    // _sanitizeMediaIdForFilename.
    final safeMediaId = _sanitizeMediaIdForFilename(mediaId);

    try {
      // Check if we need to make space
      await _ensureCacheSpace(data.length);

      // Generate unique filename, preserving the source media's extension
      // (see _deriveExtension) so the cached file remains playable on iOS.
      final extension =
          _deriveExtension(mediaItem.url, mimeType: mediaItem.mimeType);
      final fileName = _buildCacheFileName(safeMediaId, extension);
      final file = File(path.join(_cacheDir.path, fileName));

      // Write data to file
      await file.writeAsBytes(data);

      // Create cache entry
      final entry = CacheEntry(
        mediaId: mediaId,
        fileName: fileName,
        size: data.length,
        mediaItem: mediaItem,
        createdAt: DateTime.now(),
        lastAccessed: DateTime.now(),
        expiresAt: DateTime.now().add(_config.cacheExpiration),
      );

      // Add to metadata
      _metadata[mediaId] = entry;
      _currentCacheSize += data.length;

      // Save metadata
      await _saveMetadata();
    } catch (e) {
      throw CacheException('Failed to cache media: $e');
    }
  }

  /// Check if media is cached
  Future<bool> isCached(String mediaId) async {
    if (!_isInitialized) await initialize();

    final entry = _metadata[mediaId];
    return entry != null && entry.isValid;
  }

  /// Get cache info
  Future<CacheInfo> getCacheInfo() async {
    if (!_isInitialized) await initialize();

    return CacheInfo(
      totalSize: _currentCacheSize,
      maxSize: _config.maxCacheSize,
      entryCount: _metadata.length,
      enabled: _config.enabled,
    );
  }

  /// Clear all cached media
  Future<void> clearCache() async {
    if (!_isInitialized) await initialize();

    try {
      // Delete all cache files
      for (final entry in _metadata.values) {
        final file = File(path.join(_cacheDir.path, entry.fileName));
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Clear metadata
      _metadata.clear();
      _currentCacheSize = 0;

      // Save empty metadata
      await _saveMetadata();
    } catch (e) {
      throw CacheException('Failed to clear cache: $e');
    }
  }

  /// Remove specific media from cache
  Future<void> removeFromCache(String mediaId) async {
    if (!_isInitialized) await initialize();

    final entry = _metadata[mediaId];
    if (entry == null) return;

    await _deleteEntry(entry);
  }

  /// Internal helper that deletes a cache entry without requiring
  /// [_isInitialized] to be true.  This must only be called when
  /// [_cacheDir] and [_metadataFile] have already been assigned (i.e. from
  /// within [initialize] after those fields are set, or from [removeFromCache]
  /// after the [_isInitialized] guard has passed).
  Future<void> _deleteEntry(CacheEntry entry) async {
    try {
      // Delete cache file
      final file = File(path.join(_cacheDir.path, entry.fileName));
      if (await file.exists()) {
        await file.delete();
      }

      // Remove from metadata
      _currentCacheSize -= entry.size;
      _metadata.remove(entry.mediaId);

      // Save metadata
      await _saveMetadata();
    } catch (e) {
      throw CacheException('Failed to remove from cache: $e');
    }
  }

  /// Preload media for better performance
  Future<void> preloadMedia(List<MediaItem> mediaItems,
      {Map<String, String>? headers}) async {
    if (!_isInitialized) await initialize();

    if (!_config.enabled) return;

    for (final mediaItem in mediaItems) {
      if (await isCached(mediaItem.id)) continue;

      try {
        // Download and cache media with headers support
        await downloadAndCache(mediaItem, headers: headers);
      } catch (e) {
        // Log error but continue with other items
        // Failed to preload ${mediaItem.title}: $e
      }
    }
  }

  /// Ensure there's enough space in cache
  Future<void> _ensureCacheSpace(int requiredSize) async {
    if (_currentCacheSize + requiredSize <= _config.maxCacheSize) return;

    // Sort entries by last accessed time (LRU)
    final sortedEntries = _metadata.values.toList()
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

    // Remove entries until we have enough space
    for (final entry in sortedEntries) {
      if (_currentCacheSize + requiredSize <= _config.maxCacheSize) break;

      await removeFromCache(entry.mediaId);
    }

    // If still not enough space, throw error
    if (_currentCacheSize + requiredSize > _config.maxCacheSize) {
      throw CacheException('Insufficient cache space');
    }
  }

  /// Clean up expired cache entries.
  ///
  /// Uses [_deleteEntry] directly so that it never calls back into the public
  /// [removeFromCache] (which would re-enter [initialize] while the lock-free
  /// [_isInitialized] flag is still false, causing a [LateInitializationError]
  /// on the [late final] fields).
  Future<void> _cleanupExpiredEntries() async {
    final now = DateTime.now();
    final expiredEntries = <CacheEntry>[];

    for (final entry in _metadata.values) {
      if (entry.expiresAt.isBefore(now)) {
        expiredEntries.add(entry);
      }
    }

    for (final entry in expiredEntries) {
      await _deleteEntry(entry);
    }
  }

  /// Drops cache entries written by the pre-fix filename scheme, which
  /// hardcoded every cached file's extension as `.cache` regardless of the
  /// source media's real container — harmless on Android (ExoPlayer sniffs
  /// the container from the bytes) but unplayable on iOS (AVURLAsset infers
  /// container type from the extension, so `.cache` fails with
  /// AVErrorFileFormatNotRecognized).
  ///
  /// The fixed filename scheme ([_buildCacheFileName]) never produces a
  /// literal `.cache` suffix, so any entry whose [CacheEntry.fileName] ends
  /// with `.cache` unambiguously predates this fix and is silently broken
  /// on iOS. The cache is already transient and expiry-bound — letting
  /// entries simply age out would normally be enough — but a *silently
  /// broken* entry is a different case: it looks valid (unexpired, file
  /// present) right up until playback fails, so it is invalidated
  /// proactively here, at the same point [_cleanupExpiredEntries] already
  /// runs, rather than waiting for a host app to hit the iOS playback
  /// failure and only then discover the entry.
  Future<void> _invalidateLegacyCacheEntries() async {
    final legacyEntries =
        _metadata.values.where((entry) => entry.fileName.endsWith('.cache'));

    for (final entry in legacyEntries.toList()) {
      await _deleteEntry(entry);
    }
  }

  /// Load metadata from file
  Future<void> _loadMetadata() async {
    if (!await _metadataFile.exists()) return;

    try {
      final content = await _metadataFile.readAsString();
      final data = Map<String, dynamic>.from(
        json.decode(content) as Map,
      );

      _metadata.clear();
      _currentCacheSize = 0;

      for (final entry in data.values) {
        final cacheEntry = CacheEntry.fromMap(entry);
        _metadata[cacheEntry.mediaId] = cacheEntry;
        _currentCacheSize += cacheEntry.size;
      }
    } catch (e) {
      // If metadata is corrupted, start fresh
      // Failed to load cache metadata: $e
      _metadata.clear();
      _currentCacheSize = 0;
    }
  }

  /// Save metadata to file
  Future<void> _saveMetadata() async {
    try {
      final data = <String, dynamic>{};
      for (final entry in _metadata.values) {
        data[entry.mediaId] = entry.toMap();
      }

      await _metadataFile.writeAsString(json.encode(data));
    } catch (e) {
      throw CacheException('Failed to save cache metadata: $e');
    }
  }

  /// M-08: sanitizes a caller-supplied media id before it is used to build
  /// an on-disk cache filename, closing a path-traversal hole where an
  /// unsanitized id (e.g. `'../../../etc/passwd'`, an absolute path, or one
  /// containing a null byte) was interpolated directly into a filename that
  /// [File] would happily resolve outside [_cacheDir].
  ///
  /// Only [A-Za-z0-9_-] survive; everything else (path separators, `.`
  /// — which also kills any `..` traversal segment — drive letters, UNC
  /// prefixes, null bytes, etc.) is replaced with `_`. This does not change
  /// the *lookup* key used in [_metadata] (still the original, unsanitized
  /// [mediaId]) — only what actually becomes part of a filename on disk.
  static String _sanitizeMediaIdForFilename(String mediaId) {
    if (mediaId.trim().isEmpty) {
      throw const CacheException('mediaId cannot be empty');
    }

    // Reject outright rather than silently stripping: a null byte is a
    // strong signal of a hostile/corrupted caller (e.g. a classic
    // path-truncation attack against native filesystem APIs), not merely an
    // unconventional identifier.
    if (mediaId.contains('\x00')) {
      throw const CacheException('mediaId must not contain a null byte');
    }

    final sanitized = mediaId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? '_' : sanitized;
  }

  /// Longest extension kept verbatim (after sanitisation). Long enough for
  /// any real container extension this package deals with (`webm`,
  /// `mpeg4`, `m3u8`) while rejecting anything built to pad out — or
  /// otherwise deform — the cache filename.
  static const int _maxExtensionLength = 8;

  /// Maps a MIME type (bare `type/subtype`, no parameters) to the file
  /// extension AVURLAsset/ExoPlayer expect for it. Covers the containers
  /// this package already documents support for (DRM/HLS/DASH docs,
  /// `MediaType`/`MimeTypes` usage elsewhere in the codebase).
  static const Map<String, String> _mimeTypeExtensions = {
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'video/mpeg': 'mpeg',
    'video/3gpp': '3gp',
    'video/x-msvideo': 'avi',
    'application/vnd.apple.mpegurl': 'm3u8',
    'application/x-mpegurl': 'm3u8',
    'application/dash+xml': 'mpd',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/ogg': 'ogg',
    'audio/flac': 'flac',
  };

  /// Builds the on-disk cache filename for [safeMediaId], appending
  /// [extension] (as produced by [_deriveExtension], without the leading
  /// dot) when one is available.
  ///
  /// No extension is reproduced as the historical hardcoded `.cache` used
  /// to be, on purpose: a fabricated/wrong extension is exactly what broke
  /// iOS playback (AVURLAsset infers container type from the extension),
  /// so when the real one can't be determined the filename simply carries
  /// none rather than lying about it. Android is unaffected either way, as
  /// ExoPlayer sniffs the container from the bytes.
  static String _buildCacheFileName(String safeMediaId, String? extension,
      {int? timestamp}) {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final suffix = extension != null ? '.$extension' : '';
    return '${safeMediaId}_$ts$suffix';
  }

  /// Derives a safe, iOS-playable file extension (without the leading dot)
  /// for a cached file — see task notes on the on-disk cache filename
  /// scheme: [_buildCacheFileName] appends the result, if any.
  ///
  /// Tries, in order:
  ///  1. The extension in [mediaUrl]'s path, after stripping the query
  ///     string and fragment — required because signed/tokenised media
  ///     URLs are the norm (`https://cdn/video.mp4?token=abc&expires=123`
  ///     must yield `mp4`, not `mp4?token=abc&expires=123`).
  ///  2. [mimeType] — for [cacheMedia] this is [MediaItem.mimeType]; for
  ///     the streaming download path ([_downloadAndCacheToFile]) the
  ///     caller passes the response's `Content-Type` header (falling back
  ///     to [MediaItem.mimeType] if that header is absent), since that is
  ///     the most authoritative description of what was actually
  ///     downloaded.
  ///
  /// Returns `null` if neither source yields anything usable — see
  /// [_buildCacheFileName] for why the caller then omits the extension
  /// entirely rather than defaulting to something that may well be wrong.
  static String? _deriveExtension(String mediaUrl, {String? mimeType}) {
    return _extensionFromUrl(mediaUrl) ?? _extensionFromMimeType(mimeType);
  }

  static String? _extensionFromUrl(String mediaUrl) {
    // Uri.path/parse strips the query string and fragment for us; falls
    // back to naive splitting if the URL fails to parse (e.g. a bare path)
    // so a malformed URL doesn't crash caching altogether.
    final parsed = Uri.tryParse(mediaUrl);
    final urlPath = parsed?.path.isNotEmpty == true
        ? parsed!.path
        : mediaUrl.split('?').first.split('#').first;

    // path.extension() only looks at the final path segment, so a
    // traversal-style path (`/a/../etc/passwd`) can never smuggle a `..`
    // or `/` through as the "extension" — there is neither a `.` nor a
    // `/` left once we're only looking at the substring after the last
    // dot in the last segment.
    final rawExt = path.extension(urlPath);
    if (rawExt.isEmpty) return null;

    // Drop the leading dot before sanitising.
    return _sanitizeExtension(rawExt.substring(1));
  }

  static String? _extensionFromMimeType(String? mimeType) {
    if (mimeType == null) return null;
    // A `Content-Type` header commonly carries parameters, e.g.
    // "video/mp4; charset=binary" — only the bare type/subtype matters
    // for extension mapping.
    final base = mimeType.split(';').first.trim().toLowerCase();
    return _mimeTypeExtensions[base];
  }

  /// Sanitises a caller-influenced "extension" candidate before it becomes
  /// part of an on-disk filename — the extension is sourced from a URL (or
  /// a `Content-Type` header), so, exactly like [_sanitizeMediaIdForFilename]
  /// (M-08), it must be treated as hostile input: it could contain path
  /// separators, `..`, null bytes, or simply be absurdly long.
  ///
  /// Whitelists (rather than blacklists) `[A-Za-z0-9]` only — no `.`, `/`,
  /// `\`, or null bytes survive, which also means a value like
  /// `mp4%00../../evil` collapses to `mp400evil` (further capped to
  /// [_maxExtensionLength]): it cannot introduce a second `.`, alter the
  /// filename's shape, or escape [_cacheDir]. Returns `null` if nothing
  /// survives sanitisation.
  static String? _sanitizeExtension(String ext) {
    final capped = ext.length > _maxExtensionLength
        ? ext.substring(0, _maxExtensionLength)
        : ext;
    final sanitized = capped.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return sanitized.isEmpty ? null : sanitized.toLowerCase();
  }

  /// Get app cache directory.
  ///
  /// Honors an explicit [CacheConfig.cacheDirectory] override (already handled
  /// by the caller).  For the default case we use
  /// [getApplicationSupportDirectory], which is a persistent, app-private
  /// location on both Android (files dir) and iOS (Application Support).
  /// [getTemporaryDirectory] is intentionally avoided because the OS may
  /// purge it at any time, which would silently invalidate cached media.
  Future<Directory> _getAppCacheDirectory() async {
    final base = await getApplicationSupportDirectory();
    return base;
  }

  /// Downloads [mediaItem]'s media directly to a cache file on disk,
  /// streaming each chunk to an [IOSink] rather than accumulating the whole
  /// response into an in-memory `List<int>` first (H-12).
  ///
  /// The prior implementation buffered the entire response into a growable
  /// `List<int>` — roughly 8-17x the file's size in RAM, since each byte
  /// occupies a full machine word in an untyped list — before ever writing
  /// it to disk. That's enough to exhaust a low-end device on any real
  /// video file.
  ///
  /// The response is written to a `.part` temp file first and only
  /// "committed" (renamed into place, under a name that preserves the
  /// source media's extension — see [_deriveExtension] — and registered as
  /// a valid cache entry in [_metadata]) once the download completes
  /// successfully in full. Any failure or cancellation part-way through —
  /// including via [cancelDownload], which closes this download's
  /// [http.Client] and interrupts the stream — deletes the temp file so a
  /// partial download is never presented as a valid cache entry.
  Future<void> _downloadAndCacheToFile(MediaItem mediaItem,
      {Map<String, String>? headers}) async {
    final client = _httpClientFactory();
    _activeDownloads[mediaItem.id] = client;

    // M-08: sanitize before it becomes part of a filename — see
    // _sanitizeMediaIdForFilename.
    final safeMediaId = _sanitizeMediaIdForFilename(mediaItem.id);
    final downloadToken = DateTime.now().millisecondsSinceEpoch;
    // The temp file's name doesn't need a real extension — it is never
    // exposed as a cache entry and is always either renamed into place
    // (with the real extension, computed below once we know it) or
    // deleted. Only the final, committed filename matters for iOS
    // playability.
    final tempFile =
        File(path.join(_cacheDir.path, '${safeMediaId}_$downloadToken.part'));
    // Determined once the response headers are available, so a
    // `Content-Type` response header can serve as a fallback for a
    // download URL with no extension (see _deriveExtension). Assigned
    // before first use below.
    late final File finalFile;

    IOSink? sink;
    try {
      final uri = Uri.parse(mediaItem.url);
      final request = http.Request('GET', uri);

      // Add custom headers if provided
      if (headers != null) {
        request.headers.addAll(headers);
      }

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw CacheException(
            'Failed to download media: HTTP ${streamedResponse.statusCode}');
      }

      // Preserve the source media's extension in the cache filename (see
      // _deriveExtension). Priority: the download URL itself, then the
      // response's actual `Content-Type` (most authoritative for what was
      // just downloaded), then the caller-declared MediaItem.mimeType.
      final contentType = streamedResponse.headers['content-type'];
      final extension = _deriveExtension(
        mediaItem.url,
        mimeType: contentType ?? mediaItem.mimeType,
      );
      final fileName =
          _buildCacheFileName(safeMediaId, extension, timestamp: downloadToken);
      finalFile = File(path.join(_cacheDir.path, fileName));

      final contentLength = streamedResponse.contentLength ?? 0;
      int downloadedBytes = 0;

      sink = tempFile.openWrite();

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        // Report progress
        if (contentLength > 0) {
          final progress = DownloadProgress(
            mediaId: mediaItem.id,
            downloadedBytes: downloadedBytes,
            totalBytes: contentLength,
            progress: downloadedBytes / contentLength,
          );

          if (!_downloadProgressController.isClosed) {
            _downloadProgressController.add(progress);
          }
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // Make room for the finished file before committing it — mirrors the
      // space check the in-memory `cacheMedia` API performs.
      await _ensureCacheSpace(downloadedBytes);

      // Commit: only now does the download become a real, discoverable
      // cache entry.
      await tempFile.rename(finalFile.path);

      final entry = CacheEntry(
        mediaId: mediaItem.id,
        fileName: path.basename(finalFile.path),
        size: downloadedBytes,
        mediaItem: mediaItem,
        createdAt: DateTime.now(),
        lastAccessed: DateTime.now(),
        expiresAt: DateTime.now().add(_config.cacheExpiration),
      );

      _metadata[mediaItem.id] = entry;
      _currentCacheSize += downloadedBytes;

      await _saveMetadata();
    } catch (e) {
      // A failed or cancelled download must never leave a partial file
      // registered — or even just discoverable on disk — as a valid cache
      // entry.
      try {
        await sink?.close();
      } catch (_) {
        // Best-effort; the delete below is what actually matters.
      }
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {
          // Best-effort cleanup.
        }
      }
      throw CacheException('Failed to download media: $e');
    } finally {
      _activeDownloads.remove(mediaItem.id);
      client.close();
    }
  }

  /// Cancel active download
  Future<void> cancelDownload(String mediaId) async {
    final client = _activeDownloads[mediaId];
    if (client != null) {
      client.close();
      _activeDownloads.remove(mediaId);
    }
  }

  /// Check if download is in progress
  bool isDownloading(String mediaId) {
    return _activeDownloads.containsKey(mediaId);
  }

  /// Download and cache media with progress tracking
  Future<void> downloadAndCache(MediaItem mediaItem,
      {Map<String, String>? headers}) async {
    if (!_isInitialized) await initialize();

    if (!_config.enabled) return;

    // Check if already cached
    if (await isCached(mediaItem.id)) {
      return;
    }

    // Check if already downloading
    if (isDownloading(mediaItem.id)) {
      throw CacheException('Download already in progress for ${mediaItem.id}');
    }

    // H-12: streams directly to a cache file instead of downloading fully
    // into memory (via `_downloadMedia`) and then handing the buffer to
    // `cacheMedia`. `cacheMedia` itself is left unchanged — it remains the
    // public API for callers that already have the bytes in memory (e.g.
    // pre-fetched or generated in-process) and takes a `Uint8List` by
    // design.
    await _downloadAndCacheToFile(mediaItem, headers: headers);
  }

  /// Dispose the cache service
  Future<void> dispose() async {
    if (_isInitialized) {
      // Cancel all active downloads
      for (final client in _activeDownloads.values) {
        client.close();
      }
      _activeDownloads.clear();

      // Close stream controller
      await _downloadProgressController.close();

      await _saveMetadata();
      _isInitialized = false;
    }
  }
}

/// Cache entry metadata
class CacheEntry {
  final String mediaId;
  final String fileName;
  final int size;
  final MediaItem mediaItem;
  final DateTime createdAt;
  DateTime lastAccessed;
  final DateTime expiresAt;

  CacheEntry({
    required this.mediaId,
    required this.fileName,
    required this.size,
    required this.mediaItem,
    required this.createdAt,
    required this.lastAccessed,
    required this.expiresAt,
  });

  /// Check if entry is still valid
  bool get isValid => DateTime.now().isBefore(expiresAt);

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'mediaId': mediaId,
      'fileName': fileName,
      'size': size,
      'mediaItem': mediaItem.toMap(),
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastAccessed': lastAccessed.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    };
  }

  /// Create from map
  factory CacheEntry.fromMap(Map<String, dynamic> map) {
    return CacheEntry(
      mediaId: map['mediaId'] as String,
      fileName: map['fileName'] as String,
      size: map['size'] as int,
      mediaItem: MediaItem.fromMap(map['mediaItem'] as Map<String, dynamic>),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      lastAccessed:
          DateTime.fromMillisecondsSinceEpoch(map['lastAccessed'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(map['expiresAt'] as int),
    );
  }
}

/// Cache information
class CacheInfo {
  final int totalSize;
  final int maxSize;
  final int entryCount;
  final bool enabled;

  const CacheInfo({
    required this.totalSize,
    required this.maxSize,
    required this.entryCount,
    required this.enabled,
  });

  /// Get cache usage percentage
  double get usagePercentage => maxSize > 0 ? (totalSize / maxSize) * 100 : 0;

  /// Get formatted total size
  String get formattedTotalSize => _formatBytes(totalSize);

  /// Get formatted max size
  String get formattedMaxSize => _formatBytes(maxSize);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

/// Download progress information
class DownloadProgress {
  /// Media ID being downloaded
  final String mediaId;

  /// Number of bytes downloaded
  final int downloadedBytes;

  /// Total bytes to download
  final int totalBytes;

  /// Progress percentage (0.0 to 1.0)
  final double progress;

  const DownloadProgress({
    required this.mediaId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
  });

  /// Check if download is complete
  bool get isComplete => progress >= 1.0;

  /// Get formatted progress string
  String get formattedProgress => '${(progress * 100).toStringAsFixed(1)}%';

  /// Get formatted downloaded size
  String get formattedDownloadedSize => _formatBytes(downloadedBytes);

  /// Get formatted total size
  String get formattedTotalSize => _formatBytes(totalBytes);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  @override
  String toString() {
    return 'DownloadProgress(mediaId: $mediaId, progress: $formattedProgress, '
        'downloaded: $formattedDownloadedSize / $formattedTotalSize)';
  }
}

/// Cache exception
class CacheException implements Exception {
  final String message;

  const CacheException(this.message);

  @override
  String toString() => 'CacheException: $message';
}

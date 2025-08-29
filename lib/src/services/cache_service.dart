import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import '../models/media_item.dart';
import '../core/media_config.dart';

/// Service for managing media caching
class CacheService {
  static const String _cacheDirName = 'flutter_media_player_cache';
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

  CacheService(this._config);

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

      // Clean up expired entries
      await _cleanupExpiredEntries();

      _isInitialized = true;
    } catch (e) {
      throw CacheException('Failed to initialize cache service: $e');
    }
  }

  /// Get cached media data
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

  /// Cache media data
  Future<void> cacheMedia(
      String mediaId, Uint8List data, MediaItem mediaItem) async {
    if (!_isInitialized) await initialize();

    if (!_config.enabled) return;

    try {
      // Check if we need to make space
      await _ensureCacheSpace(data.length);

      // Generate unique filename
      final fileName =
          '${mediaId}_${DateTime.now().millisecondsSinceEpoch}.cache';
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

    try {
      // Delete cache file
      final file = File(path.join(_cacheDir.path, entry.fileName));
      if (await file.exists()) {
        await file.delete();
      }

      // Remove from metadata
      _currentCacheSize -= entry.size;
      _metadata.remove(mediaId);

      // Save metadata
      await _saveMetadata();
    } catch (e) {
      throw CacheException('Failed to remove from cache: $e');
    }
  }

  /// Preload media for better performance
  Future<void> preloadMedia(List<MediaItem> mediaItems) async {
    if (!_isInitialized) await initialize();

    if (!_config.enabled) return;

    for (final mediaItem in mediaItems) {
      if (await isCached(mediaItem.id)) continue;

      try {
        // Download and cache media
        final data = await _downloadMedia(mediaItem);
        await cacheMedia(mediaItem.id, data, mediaItem);
      } catch (e) {
        // Log error but continue with other items
        print('Failed to preload ${mediaItem.title}: $e');
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

  /// Clean up expired cache entries
  Future<void> _cleanupExpiredEntries() async {
    final now = DateTime.now();
    final expiredIds = <String>[];

    for (final entry in _metadata.values) {
      if (entry.expiresAt.isBefore(now)) {
        expiredIds.add(entry.mediaId);
      }
    }

    for (final mediaId in expiredIds) {
      await removeFromCache(mediaId);
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
      print('Failed to load cache metadata: $e');
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

  /// Get app cache directory
  Future<Directory> _getAppCacheDirectory() async {
    // This would typically use path_provider package
    // For now, return a default directory
    return Directory(path.join(Directory.current.path, '.cache'));
  }

  /// Download media data (placeholder implementation)
  Future<Uint8List> _downloadMedia(MediaItem mediaItem) async {
    // This would typically use http package to download media
    // For now, return empty data
    throw UnimplementedError('Media downloading not implemented yet');
  }

  /// Dispose the cache service
  Future<void> dispose() async {
    if (_isInitialized) {
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
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

/// Cache exception
class CacheException implements Exception {
  final String message;

  const CacheException(this.message);

  @override
  String toString() => 'CacheException: $message';
}

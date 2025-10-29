/// Secure storage for sensitive data
///
/// Abstract interface for storing sensitive data like DRM tokens securely.
/// Platform implementations use native secure storage:
/// - Android: EncryptedSharedPreferences
/// - iOS: Keychain Services
library;

import 'package:flutter/services.dart';

/// Abstract secure storage interface
///
/// Implement this to store sensitive data securely. The default implementation
/// uses platform-specific secure storage (Keychain on iOS, EncryptedSharedPreferences
/// on Android).
abstract class SecureStorage {
  /// Writes a value securely
  Future<void> write(String key, String value);

  /// Reads a value securely
  Future<String?> read(String key);

  /// Deletes a value
  Future<void> delete(String key);

  /// Deletes all values
  Future<void> deleteAll();

  /// Checks if a key exists
  Future<bool> containsKey(String key);
}

/// Platform channel based secure storage implementation
///
/// Uses native secure storage via platform channels:
/// - iOS: Keychain Services
/// - Android: EncryptedSharedPreferences
class PlatformSecureStorage implements SecureStorage {
  static const MethodChannel _channel =
      MethodChannel('zmedia_player/secure_storage');

  final String? _namespace;

  /// Creates secure storage with optional namespace for key isolation
  PlatformSecureStorage({String? namespace}) : _namespace = namespace;

  String _namespaceKey(String key) {
    if (_namespace != null) {
      return '${_namespace}_$key';
    }
    return key;
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _channel.invokeMethod('write', {
        'key': _namespaceKey(key),
        'value': value,
      });
    } on PlatformException catch (e) {
      throw SecureStorageException(
        'Failed to write key: ${e.message}',
        key: key,
      );
    }
  }

  @override
  Future<String?> read(String key) async {
    try {
      final result = await _channel.invokeMethod<String>('read', {
        'key': _namespaceKey(key),
      });
      return result;
    } on PlatformException catch (e) {
      throw SecureStorageException(
        'Failed to read key: ${e.message}',
        key: key,
      );
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _channel.invokeMethod('delete', {
        'key': _namespaceKey(key),
      });
    } on PlatformException catch (e) {
      throw SecureStorageException(
        'Failed to delete key: ${e.message}',
        key: key,
      );
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _channel.invokeMethod('deleteAll', {
        'namespace': _namespace,
      });
    } on PlatformException catch (e) {
      throw SecureStorageException(
        'Failed to delete all: ${e.message}',
      );
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    try {
      final result = await _channel.invokeMethod<bool>('containsKey', {
        'key': _namespaceKey(key),
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw SecureStorageException(
        'Failed to check key: ${e.message}',
        key: key,
      );
    }
  }
}

/// In-memory secure storage (for testing/development)
///
/// NOT SECURE! Only use for testing and development.
/// Data is stored in memory and lost when app restarts.
class InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<void> write(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _storage[key];
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _storage.clear();
  }

  @override
  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key);
  }

  /// Gets all keys (for testing)
  List<String> get keys => _storage.keys.toList();

  /// Gets all values (for testing)
  Map<String, String> get all => Map.unmodifiable(_storage);
}

/// Exception thrown by secure storage operations
class SecureStorageException implements Exception {
  final String message;
  final String? key;

  SecureStorageException(this.message, {this.key});

  @override
  String toString() {
    if (key != null) {
      return 'SecureStorageException: $message (key: $key)';
    }
    return 'SecureStorageException: $message';
  }
}

/// Helper for managing DRM tokens securely
class SecureTokenManager {
  final SecureStorage _storage;

  SecureTokenManager(this._storage);

  static const _tokenPrefix = 'drm_token_';
  static const _timestampSuffix = '_timestamp';

  /// Stores a DRM token securely
  Future<void> storeToken({
    required String domain,
    required String token,
  }) async {
    final key = _tokenPrefix + domain;
    await _storage.write(key, token);
    await _storage.write(
      key + _timestampSuffix,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Retrieves a DRM token
  Future<String?> getToken(String domain) async {
    final key = _tokenPrefix + domain;
    return await _storage.read(key);
  }

  /// Checks if token is expired
  Future<bool> isTokenExpired(
    String domain, {
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final key = _tokenPrefix + domain + _timestampSuffix;
    final timestampStr = await _storage.read(key);

    if (timestampStr == null) return true;

    final timestamp = int.tryParse(timestampStr);
    if (timestamp == null) return true;

    final tokenAge = DateTime.now().millisecondsSinceEpoch - timestamp;
    return tokenAge > maxAge.inMilliseconds;
  }

  /// Deletes a token
  Future<void> deleteToken(String domain) async {
    final key = _tokenPrefix + domain;
    await _storage.delete(key);
    await _storage.delete(key + _timestampSuffix);
  }

  /// Deletes all tokens
  Future<void> deleteAllTokens() async {
    // This would ideally enumerate keys, but for now we use deleteAll
    await _storage.deleteAll();
  }

  /// Gets all stored token domains
  Future<List<String>> getTokenDomains() async {
    // This requires enumeration support in SecureStorage
    // For now, return empty list
    return [];
  }
}

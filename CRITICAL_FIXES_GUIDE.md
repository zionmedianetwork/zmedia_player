# Critical Fixes Implementation Guide
**Quick Start Guide for P0 Production Readiness Fixes**

This document provides step-by-step implementation instructions for the 5 critical (P0) fixes identified in the Production Readiness Analysis.

---

## Fix #1: Memory Leak - Static Instance Maps

### Problem
Static maps retaining player instances indefinitely, causing memory leaks.

### Files to Modify
1. `lib/src/core/media_player.dart`
2. `android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt`

### Implementation

#### Dart Layer

```dart
// lib/src/core/media_player.dart

// Replace static map with lifecycle management
class MediaPlayer {
  // Add lifecycle tracking
  static final Map<String, MediaPlayer> _instances = {};
  static final Map<String, DateTime> _lastActivity = {};
  static Timer? _cleanupTimer;
  
  // Add to constructor
  MediaPlayer({required this.playerId, required MediaConfig config})
      : _config = config {
    _instances[playerId] = this;
    _markActivity();
    _ensureCleanupTimer();
  }
  
  // Track activity
  void _markActivity() {
    _lastActivity[playerId] = DateTime.now();
  }
  
  // Override key methods to track activity
  @override
  Future<void> play() async {
    _markActivity();
    // ... existing play logic
  }
  
  @override
  Future<void> pause() async {
    _markActivity();
    // ... existing pause logic
  }
  
  @override
  Future<void> load(MediaItem item) async {
    _markActivity();
    // ... existing load logic
  }
  
  // Cleanup timer
  static void _ensureCleanupTimer() {
    _cleanupTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupStaleInstances(),
    );
  }
  
  static void _cleanupStaleInstances() {
    final now = DateTime.now();
    const staleThreshold = Duration(minutes: 15);
    
    final staleKeys = <String>[];
    
    for (final entry in _lastActivity.entries) {
      if (now.difference(entry.value) > staleThreshold) {
        staleKeys.add(entry.key);
      }
    }
    
    for (final key in staleKeys) {
      final instance = _instances[key];
      if (instance != null && !instance.isPlaying) {
        debugPrint('MediaPlayer: Auto-cleaning stale instance: $key');
        instance.dispose();
        _instances.remove(key);
        _lastActivity.remove(key);
      }
    }
    
    // Stop timer if no instances
    if (_instances.isEmpty) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }
  }
  
  // Enhanced dispose
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    _isDisposed = true;
    _instances.remove(playerId);
    _lastActivity.remove(playerId);
    
    // Cancel timers
    _positionTimer?.cancel();
    _positionTimer = null;
    
    // Close platform channel
    if (_isInitialized) {
      try {
        await _channel.invokeMethod('dispose', {'playerId': playerId});
      } catch (e) {
        debugPrint('Warning: Error disposing MediaPlayer: $e');
      }
    }
    
    // Close stream controllers safely
    await _safeCloseStreams();
    
    _isInitialized = false;
  }
  
  Future<void> _safeCloseStreams() async {
    final controllers = [
      _stateController,
      _positionController,
      _durationController,
      _volumeController,
      _speedController,
      _subtitleTracksController,
      _qualityTracksController,
      _audioTracksController,
      _pipStatusController,
      _castStatusController,
      _castDevicesController,
      _drmSessionController,
      _notificationActionController,
    ];
    
    for (final controller in controllers) {
      if (!controller.isClosed) {
        try {
          await controller.close();
        } catch (e) {
          debugPrint('Error closing controller: $e');
        }
      }
    }
  }
}
```

#### Kotlin Layer

```kotlin
// android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt

class MediaPlayerManager(
    private val context: Context,
    private val methodChannel: MethodChannel
) {
    private val players = ConcurrentHashMap<String, MediaPlayerInstance>()
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // Add cleanup management
    private val lastActivity = ConcurrentHashMap<String, Long>()
    private val cleanupRunnable = object : Runnable {
        override fun run() {
            cleanupStaleInstances()
            mainHandler.postDelayed(this, CLEANUP_INTERVAL_MS)
        }
    }
    
    companion object {
        private const val CLEANUP_INTERVAL_MS = 5 * 60 * 1000L // 5 minutes
        private const val STALE_THRESHOLD_MS = 15 * 60 * 1000L // 15 minutes
    }
    
    init {
        mainHandler.postDelayed(cleanupRunnable, CLEANUP_INTERVAL_MS)
    }
    
    private fun markActivity(playerId: String) {
        lastActivity[playerId] = System.currentTimeMillis()
    }
    
    private fun cleanupStaleInstances() {
        val now = System.currentTimeMillis()
        val stalePlayers = mutableListOf<String>()
        
        lastActivity.forEach { (playerId, lastUsed) ->
            if (now - lastUsed > STALE_THRESHOLD_MS) {
                players[playerId]?.let { instance ->
                    if (!instance.isPlaying()) {
                        stalePlayers.add(playerId)
                    }
                }
            }
        }
        
        stalePlayers.forEach { playerId ->
            Log.d("MediaPlayerManager", "Auto-cleaning stale instance: $playerId")
            players[playerId]?.dispose()
            players.remove(playerId)
            lastActivity.remove(playerId)
        }
    }
    
    // Modify existing methods to track activity
    fun play(playerId: String) {
        markActivity(playerId)
        mainHandler.post {
            players[playerId]?.play()
        }
    }
    
    fun pause(playerId: String) {
        markActivity(playerId)
        mainHandler.post {
            players[playerId]?.pause()
        }
    }
    
    fun loadMediaItem(playerId: String, mediaItem: Map<String, Any>) {
        markActivity(playerId)
        mainHandler.post {
            players[playerId]?.loadMediaItem(mediaItem)
        }
    }
    
    // Clean shutdown
    fun shutdown() {
        mainHandler.removeCallbacks(cleanupRunnable)
        dispose()
    }
}

// Add to MediaPlayerInstance
class MediaPlayerInstance(...) {
    fun isPlaying(): Boolean {
        return exoPlayer?.isPlaying ?: false
    }
}
```

---

## Fix #2: Crash Reporting Integration

### Problem
No crash reporting, making production debugging impossible.

### Files to Create/Modify
1. `lib/src/core/crash_reporter.dart` (new)
2. `lib/zmedia_player.dart` (modify)
3. `lib/src/core/media_player.dart` (modify)

### Implementation

#### Create Crash Reporter Interface

```dart
// lib/src/core/crash_reporter.dart

/// Abstract crash reporter for integration with various services
abstract class CrashReporter {
  /// Report an error with context
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  });
  
  /// Log a message for debugging
  void log(String message, {Map<String, dynamic>? context});
  
  /// Set user identifier for crash reports
  void setUserIdentifier(String userId);
  
  /// Set custom key-value pairs
  void setCustomKey(String key, dynamic value);
}

/// Built-in console logger (for development)
class ConsoleOnlyCrashReporter implements CrashReporter {
  @override
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  }) {
    debugPrint('🔴 ${fatal ? 'FATAL ' : ''}ERROR: $error');
    if (stackTrace != null) {
      debugPrint('Stack: $stackTrace');
    }
    if (context != null) {
      debugPrint('Context: $context');
    }
  }
  
  @override
  void log(String message, {Map<String, dynamic>? context}) {
    debugPrint('📝 LOG: $message');
    if (context != null) {
      debugPrint('Context: $context');
    }
  }
  
  @override
  void setUserIdentifier(String userId) {
    debugPrint('👤 User: $userId');
  }
  
  @override
  void setCustomKey(String key, dynamic value) {
    debugPrint('🔑 $key: $value');
  }
}

/// Firebase Crashlytics implementation example
/// Uncomment and add firebase_crashlytics dependency to use
/*
class FirebaseCrashReporter implements CrashReporter {
  @override
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  }) {
    FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: fatal,
      information: context?.entries.map((e) => '${e.key}: ${e.value}').toList() ?? [],
    );
  }
  
  @override
  void log(String message, {Map<String, dynamic>? context}) {
    FirebaseCrashlytics.instance.log(message);
  }
  
  @override
  void setUserIdentifier(String userId) {
    FirebaseCrashlytics.instance.setUserIdentifier(userId);
  }
  
  @override
  void setCustomKey(String key, dynamic value) {
    FirebaseCrashlytics.instance.setCustomKey(key, value);
  }
}
*/
```

#### Integrate into MediaPlayer

```dart
// lib/src/core/media_player.dart

class MediaPlayer {
  /// Global crash reporter (set once at app startup)
  static CrashReporter? crashReporter;
  
  /// Enable crash reporting (call at app startup)
  static void enableCrashReporting(CrashReporter reporter) {
    crashReporter = reporter;
    crashReporter?.log('MediaPlayer crash reporting enabled');
  }
  
  // Wrap critical operations
  Future<void> load(MediaItem item) async {
    _throwIfDisposed();
    
    try {
      crashReporter?.setCustomKey('media_id', item.id);
      crashReporter?.setCustomKey('media_url', item.url);
      crashReporter?.setCustomKey('drm_enabled', item.drmConfig != null);
      
      _currentItem = item;
      _markActivity();
      
      final result = await _channel.invokeMethod('load', {
        'playerId': playerId,
        'mediaItem': item.toMap(),
      });
      
      crashReporter?.log('Media loaded successfully', context: {
        'mediaId': item.id,
        'duration': item.duration?.inSeconds,
      });
      
    } catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'load',
        'mediaId': item.id,
        'url': item.url,
        'playerId': playerId,
      });
      
      _handleLoadError('Failed to load media: $e');
      rethrow;
    }
  }
  
  Future<void> play() async {
    _throwIfDisposed();
    
    try {
      await _channel.invokeMethod('play', {'playerId': playerId});
      _markActivity();
      crashReporter?.log('Playback started', context: {
        'mediaId': _currentItem?.id,
      });
    } catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'play',
        'playerId': playerId,
        'state': _currentState.state.name,
      });
      rethrow;
    }
  }
  
  // Add to other critical methods: pause, stop, seekTo, etc.
}
```

#### Export in Main Package

```dart
// lib/zmedia_player.dart

// Core
export 'src/core/media_player.dart';
export 'src/core/media_controller.dart';
export 'src/core/media_config.dart';
export 'src/core/crash_reporter.dart'; // Add this

// ... rest of exports
```

#### Usage Example

```dart
// In your app's main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Setup crash reporting
  final crashReporter = ConsoleOnlyCrashReporter(); // Or FirebaseCrashReporter()
  MediaPlayer.enableCrashReporting(crashReporter);
  
  // Optional: Set user info
  crashReporter.setUserIdentifier('user_123');
  
  runApp(MyApp());
}
```

---

## Fix #3: ProGuard Rules for Android

### Problem
Missing ProGuard rules will break release builds on Android.

### Files to Create
1. `android/proguard-rules.pro` (new)
2. `android/build.gradle` (modify)

### Implementation

#### Create ProGuard Rules

```proguard
# android/proguard-rules.pro

# ZMedia Player
-keep class com.zionmedianetwork.zmedia_player.** { *; }
-keepclassmembers class com.zionmedianetwork.zmedia_player.** {
    public *;
    protected *;
}

# ExoPlayer / Media3
-keep class com.google.android.exoplayer2.** { *; }
-keep interface com.google.android.exoplayer2.** { *; }
-keepclassmembers class com.google.android.exoplayer2.** {
    *;
}
-dontwarn com.google.android.exoplayer2.**

# DRM
-keep class com.google.android.exoplayer2.drm.** { *; }
-keep interface com.google.android.exoplayer2.drm.** { *; }
-dontwarn com.google.android.exoplayer2.drm.**

# Google Cast
-keep class com.google.android.gms.cast.** { *; }
-keep interface com.google.android.gms.cast.** { *; }
-dontwarn com.google.android.gms.cast.**

# Flutter
-keep class io.flutter.** { *; }
-keepclassmembers class io.flutter.** {
    *;
}
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Platform Views
-keep class io.flutter.plugin.platform.** { *; }
-keepclassmembers class io.flutter.plugin.platform.** {
    *;
}

# Method Channel
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel.Result *;
}

# Prevent obfuscation of method channel methods
-keepclassmembers class com.zionmedianetwork.zmedia_player.ZMediaPlayerPlugin {
    public void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel.Result);
}

# AndroidX
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# Kotlin
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.Metadata {
    *;
}

# Keep native methods
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep constructors called from native
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet);
}
```

#### Update build.gradle

```gradle
// android/build.gradle

android {
    // ... existing config
    
    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
        debug {
            minifyEnabled false
        }
    }
}
```

#### Test ProGuard Build

```bash
# In example app
cd example
flutter build apk --release

# Test the release APK
flutter install --release

# Check for any crashes or missing functionality
```

---

## Fix #4: Typed Exception Hierarchy

### Problem
Inconsistent error handling makes debugging difficult.

### Files to Create/Modify
1. `lib/src/core/exceptions.dart` (new)
2. `lib/zmedia_player.dart` (modify exports)
3. `lib/src/core/media_player.dart` (modify error handling)

### Implementation

#### Create Exception Hierarchy

```dart
// lib/src/core/exceptions.dart

/// Base exception for all media player errors
sealed class MediaPlayerException implements Exception {
  const MediaPlayerException(this.message, {this.details});
  
  final String message;
  final Map<String, dynamic>? details;
  
  @override
  String toString() {
    if (details != null && details!.isNotEmpty) {
      return 'MediaPlayerException: $message\nDetails: $details';
    }
    return 'MediaPlayerException: $message';
  }
}

/// Media could not be loaded
class MediaLoadException extends MediaPlayerException {
  const MediaLoadException(
    String message, {
    this.url,
    this.statusCode,
    Map<String, dynamic>? details,
  }) : super(message, details: details);
  
  final String? url;
  final int? statusCode;
  
  @override
  String toString() => 'MediaLoadException: $message (URL: $url, Status: $statusCode)';
}

/// Network-related errors
class NetworkException extends MediaPlayerException {
  const NetworkException(
    String message, {
    this.isOffline = false,
    this.isTimeout = false,
    Map<String, dynamic>? details,
  }) : super(message, details: details);
  
  final bool isOffline;
  final bool isTimeout;
  
  @override
  String toString() {
    if (isOffline) return 'NetworkException: No internet connection';
    if (isTimeout) return 'NetworkException: Request timed out - $message';
    return 'NetworkException: $message';
  }
}

/// DRM-related errors
class DrmException extends MediaPlayerException {
  const DrmException(
    String message, {
    this.drmType,
    this.errorCode,
    this.isLicenseError = false,
    this.isCertificateError = false,
    Map<String, dynamic>? details,
  }) : super(message, details: details);
  
  final String? drmType;
  final String? errorCode;
  final bool isLicenseError;
  final bool isCertificateError;
  
  @override
  String toString() {
    final type = drmType ?? 'Unknown';
    if (isLicenseError) {
      return 'DrmException ($type): License error - $message (Code: $errorCode)';
    }
    if (isCertificateError) {
      return 'DrmException ($type): Certificate error - $message';
    }
    return 'DrmException ($type): $message (Code: $errorCode)';
  }
}

/// Playback errors (decoding, rendering, etc.)
class PlaybackException extends MediaPlayerException {
  const PlaybackException(
    String message, {
    this.errorCode,
    Map<String, dynamic>? details,
  }) : super(message, details: details);
  
  final String? errorCode;
  
  @override
  String toString() => 'PlaybackException: $message (Code: $errorCode)';
}

/// Player is in invalid state for requested operation
class InvalidStateException extends MediaPlayerException {
  const InvalidStateException(
    String message, {
    this.currentState,
    this.requiredState,
    Map<String, dynamic>? details,
  }) : super(message, details: details);
  
  final String? currentState;
  final String? requiredState;
  
  @override
  String toString() => 
    'InvalidStateException: $message (Current: $currentState, Required: $requiredState)';
}

/// Player has been disposed
class PlayerDisposedException extends MediaPlayerException {
  const PlayerDisposedException([
    String message = 'Player has been disposed',
  ]) : super(message);
}

/// Configuration error
class ConfigurationException extends MediaPlayerException {
  const ConfigurationException(
    String message, {
    this.parameter,
    this.value,
    Map<String, dynamic>? details,
  }) : super(message, details: details);
  
  final String? parameter;
  final dynamic value;
  
  @override
  String toString() => 
    'ConfigurationException: $message (Parameter: $parameter, Value: $value)';
}

/// Platform-specific error
class PlatformException extends MediaPlayerException {
  const PlatformException(
    String message, {
    this.platform,
    this.code,
    Map<String, dynamic>? details,
  }) : super(message, details: details);
  
  final String? platform;
  final String? code;
  
  @override
  String toString() => 
    'PlatformException ($platform): $message (Code: $code)';
}
```

#### Update MediaPlayer Error Handling

```dart
// lib/src/core/media_player.dart

import 'exceptions.dart';

class MediaPlayer {
  void _throwIfDisposed() {
    if (_isDisposed) {
      throw const PlayerDisposedException();
    }
  }
  
  Future<void> load(MediaItem item) async {
    _throwIfDisposed();
    
    try {
      _currentItem = item;
      _markActivity();
      
      await _channel.invokeMethod('load', {
        'playerId': playerId,
        'mediaItem': item.toMap(),
      });
      
    } on PlatformException catch (e) {
      // Convert platform exceptions to typed exceptions
      if (e.code == 'NETWORK_ERROR') {
        final isOffline = e.message?.contains('offline') ?? false;
        final isTimeout = e.message?.contains('timeout') ?? false;
        throw NetworkException(
          e.message ?? 'Network error',
          isOffline: isOffline,
          isTimeout: isTimeout,
          details: e.details as Map<String, dynamic>?,
        );
      } else if (e.code == 'DRM_ERROR') {
        throw DrmException(
          e.message ?? 'DRM error',
          errorCode: e.code,
          details: e.details as Map<String, dynamic>?,
        );
      } else {
        throw MediaLoadException(
          e.message ?? 'Failed to load media',
          url: item.url,
          details: e.details as Map<String, dynamic>?,
        );
      }
    } catch (e) {
      throw MediaLoadException(
        'Failed to load media: $e',
        url: item.url,
      );
    }
  }
  
  void _validatePlaylistOperation() {
    _throwIfDisposed();
    if (_currentPlaylist == null) {
      throw const InvalidStateException(
        'No playlist set',
        requiredState: 'Playlist loaded',
        currentState: 'No playlist',
      );
    }
  }
}
```

#### Export Exceptions

```dart
// lib/zmedia_player.dart

// Core
export 'src/core/media_player.dart';
export 'src/core/media_controller.dart';
export 'src/core/media_config.dart';
export 'src/core/crash_reporter.dart';
export 'src/core/exceptions.dart'; // Add this

// ... rest
```

#### Usage in App

```dart
// Example error handling in your app
try {
  await controller.load(mediaItem);
  await controller.play();
} on DrmException catch (e) {
  if (e.isLicenseError) {
    showError('Content protection error. Please check your subscription.');
  } else if (e.isCertificateError) {
    showError('Security error. Please update the app.');
  } else {
    showError('Unable to play protected content: ${e.message}');
  }
} on NetworkException catch (e) {
  if (e.isOffline) {
    showError('No internet connection. Please check your network.');
  } else if (e.isTimeout) {
    showError('Connection timed out. Please try again.');
  } else {
    showError('Network error: ${e.message}');
  }
} on MediaLoadException catch (e) {
  showError('Unable to load video: ${e.message}');
  crashReporter.reportError(e, StackTrace.current);
} on PlayerDisposedException catch (e) {
  // Player was disposed, ignore or reinitialize
  debugPrint('Player disposed: $e');
} on MediaPlayerException catch (e) {
  // Catch-all for other media player errors
  showError('Playback error: ${e.message}');
  crashReporter.reportError(e, StackTrace.current);
}
```

---

## Fix #5: Offline DRM Decision & Documentation

### Problem
Offline DRM marked as TODO, unclear if it's a blocker.

### Options

#### Option A: Implement Offline DRM (4-6 weeks)

**If offline DRM is required**, implement using ExoPlayer's `OfflineLicenseHelper`:

```kotlin
// Create new file: android/src/main/kotlin/.../OfflineDrmHandler.kt

class OfflineDrmHandler(
    private val context: Context,
    private val drmConfig: Map<String, Any>
) {
    private lateinit var offlineLicenseHelper: OfflineLicenseHelper
    
    fun initialize() {
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
        
        val drmSessionManager = DefaultDrmSessionManager.Builder()
            .setUuidAndExoMediaDrmProvider(C.WIDEVINE_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
            .build(DefaultHttpDataSource.Factory())
        
        offlineLicenseHelper = OfflineLicenseHelper(
            drmSessionManager,
            DrmSessionEventListener.EventDispatcher()
        )
    }
    
    suspend fun downloadLicense(
        contentId: String,
        licenseUrl: String
    ): ByteArray = withContext(Dispatchers.IO) {
        try {
            val keySetId = offlineLicenseHelper.downloadLicense(
                MediaItem.Builder()
                    .setUri(contentId)
                    .setDrmConfiguration(
                        MediaItem.DrmConfiguration.Builder(C.WIDEVINE_UUID)
                            .setLicenseUri(licenseUrl)
                            .build()
                    )
                    .build()
            )
            return@withContext keySetId
        } catch (e: Exception) {
            throw DrmException("Failed to download offline license: ${e.message}")
        }
    }
    
    fun renewLicense(keySetId: ByteArray) {
        offlineLicenseHelper.renewLicense(keySetId)
    }
    
    fun releaseLicense(keySetId: ByteArray) {
        offlineLicenseHelper.releaseLicense(keySetId)
    }
}
```

#### Option B: Document as Future Feature (Recommended for now)

**If offline DRM is not immediately needed**, document clearly:

```markdown
# docs/api-reference/drm.md

## Offline DRM Support

### Current Status

**Offline license support is not yet implemented.**

### Workarounds

For offline viewing of DRM content:

1. **Stream-only approach**: Require internet connection for DRM content
2. **Non-DRM offline**: Use non-protected content for offline mode
3. **Token-based short-term licenses**: Use short-lived licenses (24-48 hours)

### Timeline

Offline DRM support is planned for v0.2.0 (Q1 2026).

### Technical Details

Offline DRM requires:
- Android: ExoPlayer's `OfflineLicenseHelper`
- iOS: AVAssetDownloadTask with FairPlay
- License storage and renewal logic
- Expiration handling

### Tracking

Follow progress: [GitHub Issue #XX]

### Alternatives

For production apps requiring offline DRM now:
- Use better_player package (has offline DRM)
- Wait for v0.2.0
- Contribute implementation (see CONTRIBUTING.md)
```

#### Implementation Decision Tree

```
Do you need offline DRM for launch?
│
├─ YES → Implement Option A (4-6 weeks delay)
│        - Required for Netflix-like apps
│        - Content download for offline viewing
│        - Premium feature set
│
└─ NO → Choose Option B (Document as future)
         - Streaming-only apps (YouTube, Twitch)
         - Live streaming platforms
         - MVP/Beta launch
         
         Can add in v0.2.0 without breaking changes
```

---

## Testing Your Fixes

### 1. Memory Leak Testing

```dart
// test/memory_leak_test.dart

void main() {
  test('No memory leak with repeated dispose', () async {
    for (int i = 0; i < 100; i++) {
      final controller = MediaController.create();
      await controller.initialize();
      await controller.dispose();
    }
    
    // Check that instance map is empty
    expect(MediaPlayer.instanceCount, 0);
  });
  
  test('Stale instances cleaned up', () async {
    final controllers = List.generate(
      10,
      (i) => MediaController.create(),
    );
    
    for (final controller in controllers) {
      await controller.initialize();
    }
    
    // Wait for cleanup (15 minutes in production, reduce for test)
    await Future.delayed(Duration(seconds: 20));
    
    // Instances should be cleaned
    expect(MediaPlayer.instanceCount, lessThan(5));
    
    // Dispose remaining
    for (final controller in controllers) {
      await controller.dispose();
    }
  });
}
```

### 2. Crash Reporting Testing

```dart
// test/crash_reporting_test.dart

void main() {
  test('Crash reporter captures exceptions', () async {
    final mockReporter = MockCrashReporter();
    MediaPlayer.enableCrashReporting(mockReporter);
    
    final controller = MediaController.create();
    await controller.initialize();
    
    // Trigger error
    try {
      await controller.load(MediaItem(
        id: 'test',
        url: 'invalid://url',
        title: 'Test',
      ));
    } catch (e) {
      // Expected
    }
    
    // Verify crash was reported
    expect(mockReporter.errors.length, greaterThan(0));
    expect(mockReporter.errors.first, isA<MediaLoadException>());
  });
}

class MockCrashReporter implements CrashReporter {
  final List<dynamic> errors = [];
  final List<String> logs = [];
  
  @override
  void reportError(error, stack, {context, fatal = false}) {
    errors.add(error);
  }
  
  @override
  void log(String message, {context}) {
    logs.add(message);
  }
  
  @override
  void setUserIdentifier(String userId) {}
  
  @override
  void setCustomKey(String key, value) {}
}
```

### 3. ProGuard Testing

```bash
# Build release APK
cd example
flutter build apk --release

# Install and test all features
flutter install --release
adb shell am start -n com.zionmedianetwork.zmedia_player_example/.MainActivity

# Check for crashes
adb logcat | grep -E "(FATAL|AndroidRuntime|ZMediaPlayer)"

# Test each feature:
# - Basic playback ✓
# - DRM content ✓
# - Notifications ✓
# - PiP ✓
# - Casting ✓
```

### 4. Exception Handling Testing

```dart
// test/exception_handling_test.dart

void main() {
  test('Typed exceptions thrown correctly', () async {
    final controller = MediaController.create();
    await controller.initialize();
    
    // Test NetworkException
    expect(
      () => controller.load(offlineMediaItem),
      throwsA(isA<NetworkException>().having(
        (e) => e.isOffline,
        'isOffline',
        true,
      )),
    );
    
    // Test DrmException
    expect(
      () => controller.load(invalidDrmMediaItem),
      throwsA(isA<DrmException>().having(
        (e) => e.isLicenseError,
        'isLicenseError',
        true,
      )),
    );
    
    // Test PlayerDisposedException
    await controller.dispose();
    expect(
      () => controller.play(),
      throwsA(isA<PlayerDisposedException>()),
    );
  });
}
```

---

## Deployment Checklist

After implementing all 5 fixes:

- [ ] All existing tests still pass
- [ ] New tests for fixes added and passing
- [ ] Memory leak test passes (100 iterations)
- [ ] ProGuard release build works on physical device
- [ ] Crash reporter logs visible in your dashboard
- [ ] Exception handling works in example app
- [ ] Documentation updated with offline DRM status
- [ ] Code review completed
- [ ] Performance benchmarks still meet targets
- [ ] Ready for beta testing

---

## Estimated Timeline

| Fix | Effort | Testing | Total |
|-----|--------|---------|-------|
| #1 Memory Leaks | 4 hours | 2 hours | 6 hours |
| #2 Crash Reporting | 3 hours | 1 hour | 4 hours |
| #3 ProGuard | 2 hours | 2 hours | 4 hours |
| #4 Typed Exceptions | 4 hours | 2 hours | 6 hours |
| #5 Offline DRM Doc | 1 hour | 0.5 hour | 1.5 hours |
| **Total** | **14 hours** | **7.5 hours** | **~3 days** |

---

## Getting Help

If you encounter issues:

1. Check the main analysis document: `PRODUCTION_READINESS_ANALYSIS.md`
2. Review test failures carefully
3. Use the crash reporter to track issues
4. Refer to platform-specific debugging:
   - Android: `adb logcat`
   - iOS: Xcode console

---

**Next Steps:** After completing these fixes, proceed with P1 recommendations from the main analysis document.


# DRM (Digital Rights Management) - API Reference

## Overview

ZMedia Player provides comprehensive DRM support for protected content playback on both iOS and Android platforms.

**Current Status:** ✅ **Online DRM Fully Supported**  
**Offline DRM:** 📅 **Planned for v0.2.0** (see [Roadmap](#offline-drm-roadmap))

---

## Supported DRM Systems

### Android
- **Widevine** (Google) - Level 1, Level 3
- **PlayReady** (Microsoft)
- **ClearKey** (for testing)

### iOS
- **FairPlay** (Apple)
- **FairPlay Streaming (FPS)**

### Cross-Platform
- **EZDRM** - Simplified DRM integration service

---

## Online DRM (Current - v0.1.x)

### Basic Usage

```dart
import 'package:zmedia_player/zmedia_player.dart';

// Widevine (Android)
final mediaItem = MediaItem(
  id: 'drm-video',
  url: 'https://example.com/video.mpd',
  title: 'Protected Video',
  drmConfig: DrmConfig.widevine(
    licenseUrl: 'https://license.example.com/widevine',
    headers: {
      'Authorization': 'Bearer your-token',
    },
  ),
);

// FairPlay (iOS)
final mediaItem = MediaItem(
  id: 'drm-video',
  url: 'https://example.com/video.m3u8',
  title: 'Protected Video',
  drmConfig: DrmConfig.fairplay(
    licenseUrl: 'https://license.example.com/fairplay',
    certificateUrl: 'https://license.example.com/cert.cer',
  ),
);

// Load and play
await controller.load(mediaItem);
await controller.play();
```

### EZDRM Integration

```dart
final ezdrmConfig = EzdrmConfig.widevine(
  customerId: 'your-customer-id',
  apiKey: 'your-api-key',
  contentId: 'content-123',
);

final mediaItem = MediaItem(
  id: 'ezdrm-video',
  url: 'https://example.com/video.mpd',
  title: 'EZDRM Protected',
  drmConfig: DrmConfig.ezdrm(
    ezdrmConfig: ezdrmConfig,
  ),
);
```

### Custom Headers and Authentication

```dart
final drmConfig = DrmConfig.widevine(
  licenseUrl: 'https://license.example.com/widevine',
  headers: {
    'Authorization': 'Bearer ${userToken}',
    'X-Custom-Header': 'custom-value',
  },
  customData: {
    'userId': 'user-123',
    'sessionId': 'session-456',
  },
);
```

### License Renewal

```dart
final drmConfig = DrmConfig.widevine(
  licenseUrl: 'https://license.example.com/widevine',
  autoRenewLicense: true, // Automatically renew expiring licenses
);
```

---

## DRM Session Monitoring

### Listen to DRM Events

```dart
controller.player.drmSessionStream.listen((session) {
  print('DRM State: ${session.state}');
  
  switch (session.state) {
    case DrmSessionState.acquiringLicense:
      showLoading('Acquiring license...');
      break;
    case DrmSessionState.licensed:
      hideLoading();
      break;
    case DrmSessionState.error:
      showError('DRM Error: ${session.errorMessage}');
      break;
  }
});
```

### Check License Status

```dart
final session = await controller.getDrmSession();
if (session.license?.isExpired ?? false) {
  print('License expired, renewing...');
}
```

---

## Error Handling

### DRM-Specific Exceptions

```dart
try {
  await controller.load(mediaItem);
} on DrmException catch (e) {
  if (e.isLicenseError) {
    // License acquisition failed
    showError('License error. Check your subscription.');
  } else if (e.isCertificateError) {
    // Certificate validation failed (FairPlay)
    showError('Certificate error. Update the app.');
  } else {
    // Other DRM errors
    showError('DRM error: ${e.message}');
  }
  
  // Log for debugging
  print('DRM Type: ${e.drmType}');
  print('Error Code: ${e.errorCode}');
  print('Details: ${e.details}');
}
```

---

## Platform-Specific Configuration

### Android (Widevine)

```dart
// Widevine L1 (hardware-backed, highest security)
final drmConfig = DrmConfig.widevine(
  licenseUrl: 'https://license.example.com/widevine',
  // ExoPlayer automatically uses highest available security level
);
```

**Requirements:**
- Device must support Widevine
- Add to `AndroidManifest.xml` (automatically handled):
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  ```

### iOS (FairPlay)

```dart
final drmConfig = DrmConfig.fairplay(
  licenseUrl: 'https://license.example.com/fairplay/license',
  certificateUrl: 'https://license.example.com/fairplay/cert.cer',
  contentId: 'content-123', // Optional, for custom content identification
);
```

**Requirements:**
- Valid FairPlay Streaming (FPS) certificate from Apple
- Add to `Info.plist` (automatically handled by plugin):
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  ```

---

## Testing DRM

### ClearKey (Testing Only)

```dart
// NEVER use in production!
final testConfig = DrmConfig(
  scheme: DrmScheme.clearkey,
  licenseUrl: 'data:text/plain;base64,...',
  // Clear keys for testing
);
```

### Test Streams

```dart
// Widevine test stream (Android)
const testUrl = 'https://storage.googleapis.com/wvmedia/cenc/h264/tears/tears.mpd';
const testLicense = 'https://proxy.uat.widevine.com/proxy';

// FairPlay test stream (iOS)
const testUrl = 'https://devstreaming-cdn.apple.com/videos/streaming/...';
const testLicense = 'https://fps.example.com/license';
const testCert = 'https://fps.example.com/cert.cer';
```

---

## Offline DRM Roadmap

### ⚠️ Current Status: Not Available

Offline DRM (download and offline playback of DRM-protected content) is **not currently supported** in v0.1.x.

### 📅 Planned for v0.2.0 (Q1 2026)

**Estimated Timeline:** 4-6 weeks development  
**Target Release:** January-February 2026

#### Planned Features

1. **Download Management**
   ```dart
   // Future API (not yet available)
   final downloadId = await controller.downloadDrmContent(
     mediaItem: mediaItem,
     quality: DownloadQuality.high,
   );
   ```

2. **License Persistence**
   - Store licenses locally for offline playback
   - Automatic license renewal when online
   - Expiration tracking

3. **Storage Management**
   - Manage downloaded content
   - Storage quota limits
   - Cleanup expired licenses

4. **Platform Support**
   - Android: `OfflineLicenseHelper` (ExoPlayer)
   - iOS: `AVAssetDownloadTask` (AVFoundation)

### Workarounds (Current)

If you need offline DRM functionality now, consider these alternatives:

#### Option 1: Server-Side Download
- Download content to your backend
- Serve via your own CDN with authentication
- Users stream from your servers

#### Option 2: Use Non-DRM for Offline
```dart
// For offline content, use non-DRM videos
if (isOfflineMode) {
  mediaItem = MediaItem(
    url: localFilePath,
    // No DRM config
  );
} else {
  mediaItem = MediaItem(
    url: streamUrl,
    drmConfig: drmConfig, // DRM for streaming only
  );
}
```

#### Option 3: Temporary Licenses
- Use short-lived online licenses
- Re-acquire license when playing offline (requires brief connectivity)

### Tracking

Follow offline DRM progress:
- **GitHub Issue:** [#TODO: Create issue]
- **Milestone:** v0.2.0
- **Labels:** `enhancement`, `drm`, `offline`

### Request Early Access

If offline DRM is critical for your use case:
1. Comment on the GitHub issue
2. Describe your use case
3. Vote for priority
4. Consider sponsoring development

---

## Best Practices

### 1. License Caching
```dart
// Licenses are automatically cached in memory
// Clear cache on app restart or user logout
await controller.clearDrmCache();
```

### 2. Error Recovery
```dart
try {
  await controller.load(mediaItem);
} on DrmException catch (e) {
  if (e.isLicenseError) {
    // Retry with exponential backoff
    await Future.delayed(Duration(seconds: 2));
    await controller.load(mediaItem); // Retry
  }
}
```

### 3. Security
```dart
// NEVER hardcode tokens or keys
final drmConfig = DrmConfig.widevine(
  licenseUrl: 'https://license.example.com/widevine',
  headers: {
    'Authorization': 'Bearer ${await getTokenSecurely()}',
  },
);

// Use secure storage for sensitive data
```

### 4. User Experience
```dart
// Show appropriate messages
controller.player.drmSessionStream.listen((session) {
  if (session.state == DrmSessionState.acquiringLicense) {
    showMessage('Verifying content rights...');
  }
});
```

---

## Troubleshooting

### Common Issues

#### "License acquisition failed"
- **Cause:** Invalid license URL or authentication
- **Solution:** Verify license server URL and credentials

#### "Certificate validation failed" (iOS only)
- **Cause:** Invalid or expired FairPlay certificate
- **Solution:** Download new certificate from Apple

#### "DRM not supported on this device"
- **Cause:** Device doesn't support required DRM level
- **Solution:** Check device compatibility, use fallback content

#### "License expired"
- **Cause:** License validity period ended
- **Solution:** Enable `autoRenewLicense: true` or re-acquire license

### Debug Logging

```dart
// Enable DRM debug logs
MediaPlayer.enableCrashReporting(
  ConsoleOnlyCrashReporter(), // Logs all errors to console
);

// Check DRM session details
final session = await controller.getDrmSession();
print('DRM Session: ${session.toMap()}');
```

---

## API Reference

### DrmConfig Class

```dart
class DrmConfig {
  final DrmScheme scheme;
  final String licenseUrl;
  final String? certificateUrl;
  final Map<String, String>? headers;
  final String? token;
  final String? keyId;
  final String? contentId;
  final bool allowOffline; // Reserved for future use
  final int? offlineLicenseDuration; // Reserved for future use
  final bool autoRenewLicense;
  final Map<String, dynamic>? customData;
  final EzdrmConfig? ezdrmConfig;
}
```

### DrmScheme Enum

```dart
enum DrmScheme {
  token,      // Custom token-based
  widevine,   // Google Widevine (Android)
  fairplay,   // Apple FairPlay (iOS)
  ezdrm,      // EZDRM service
  playready,  // Microsoft PlayReady
  clearkey,   // Testing only
}
```

### DrmSession Class

```dart
class DrmSession {
  final String id;
  final DrmSessionState state;
  final DrmLicense? license;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### DrmSessionState Enum

```dart
enum DrmSessionState {
  idle,              // Not initialized
  acquiringLicense,  // Acquiring license
  licensed,          // License acquired
  renewing,          // Renewing license
  error,             // Error occurred
  closed,            // Session closed
}
```

---

## Migration Guide

### From Other Players

#### From BetterPlayer
```dart
// BetterPlayer
BetterPlayerDataSource(
  BetterPlayerDataSourceType.network,
  videoUrl,
  drmConfiguration: BetterPlayerDrmConfiguration(...),
);

// ZMedia Player
MediaItem(
  url: videoUrl,
  drmConfig: DrmConfig.widevine(...),
);
```

#### From video_player
```dart
// video_player (no DRM support)
VideoPlayerController.network(videoUrl);

// ZMedia Player
final controller = MediaController(MediaPlayer());
await controller.load(MediaItem(
  url: videoUrl,
  drmConfig: drmConfig,
));
```

---

## Performance Considerations

### License Acquisition Time
- Typical: 100-500ms
- Show loading indicator during acquisition
- Cache licenses when possible

### Memory Usage
- DRM sessions: ~1-2MB per active session
- Automatic cleanup after playback ends

### Battery Impact
- Hardware DRM (Widevine L1, FairPlay): Minimal impact
- Software DRM: Slightly higher CPU usage

---

## Security Audit

✅ **Best Practices Implemented:**
- Secure key exchange via HTTPS
- Certificate pinning support
- No keys stored in plain text
- Automatic license rotation
- Secure memory handling

⚠️ **Recommendations:**
- Use hardware-backed DRM when available (Widevine L1)
- Implement certificate pinning for production
- Rotate licenses regularly
- Monitor for unusual license requests

---

## Additional Resources

### Documentation
- [DRM Guide](../implementation/security.md)
- [Security Best Practices](../implementation/security.md)
- [Testing Guide](../implementation/testing.md)

### External Links
- [Widevine Documentation](https://www.widevine.com/)
- [FairPlay Streaming](https://developer.apple.com/streaming/fps/)
- [EZDRM Service](https://www.ezdrm.com/)

### Support
- [GitHub Issues](https://github.com/your-repo/issues)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/zmedia-player)
- [Discord Community](https://discord.gg/your-server)

---

## Changelog

### v0.1.0 (Current)
- ✅ Widevine support (Android)
- ✅ FairPlay support (iOS)
- ✅ EZDRM integration
- ✅ Custom headers and authentication
- ✅ License renewal
- ✅ DRM session monitoring
- ✅ Comprehensive error handling

### v0.2.0 (Planned - Q1 2026)
- 📅 Offline DRM support
- 📅 Download management
- 📅 License persistence
- 📅 Storage management

---

**Note:** This documentation reflects the current state of DRM support. Offline DRM features are planned for v0.2.0. See the [Roadmap](#offline-drm-roadmap) section for details.

*Last Updated: October 21, 2025*

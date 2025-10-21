# DRM (Digital Rights Management) Guide

## Overview

ZMedia Player supports industry-standard DRM technologies to play protected content on both Android and iOS platforms. This guide covers implementation, configuration, and best practices for DRM-protected media playback.

## Supported DRM Systems

### Android
- **Widevine DRM** - Google's DRM system, widely adopted by streaming services
- **PlayReady** - Microsoft's DRM solution
- **ClearKey** - For testing and development

### iOS
- **FairPlay Streaming (FPS)** - Apple's DRM system for iOS devices

### Cross-Platform
- **EZDRM Integration** - Simplified DRM setup through EZDRM service

## Quick Start

### 1. Basic DRM Setup

```dart
import 'package:zmedia_player/zmedia_player.dart';

// For Android Widevine
final androidDrmConfig = DrmConfig.widevine(
  licenseUrl: 'https://your-license-server.com/widevine',
  headers: {
    'X-Custom-Header': 'value',
  },
);

// For iOS FairPlay
final iosDrmConfig = DrmConfig.fairplay(
  licenseUrl: 'https://your-license-server.com/fairplay',
  certificateUrl: 'https://your-server.com/certificate.cer',
);

// Create MediaItem with DRM
final mediaItem = MediaItem(
  id: 'protected_video',
  title: 'Protected Content',
  url: 'https://your-cdn.com/video.mpd',  // or .m3u8 for iOS
  drmConfig: Platform.isAndroid ? androidDrmConfig : iosDrmConfig,
);

// Load and play
await controller.load(mediaItem);
await controller.play();
```

### 2. EZDRM Integration

EZDRM simplifies DRM implementation with a unified API:

```dart
// Android Widevine via EZDRM
final ezdrmConfigAndroid = EzdrmConfig.widevine(
  customerId: 'YOUR_EZDRM_CUSTOMER_ID',
  apiKey: 'YOUR_EZDRM_API_KEY',
  contentId: 'unique_content_id',
);

final drmConfig = DrmConfig.ezdrm(
  ezdrmConfig: ezdrmConfigAndroid,
  allowOffline: true,
);

// iOS FairPlay via EZDRM
final ezdrmConfigIOS = EzdrmConfig.fairplay(
  customerId: 'YOUR_EZDRM_CUSTOMER_ID',
  apiKey: 'YOUR_EZDRM_API_KEY',
  contentId: 'unique_content_id',
);
```

## Platform-Specific Setup

### Android Setup

1. **Add dependencies** in `android/build.gradle`:

```gradle
dependencies {
    // ExoPlayer with Widevine support (already included)
    implementation 'com.google.android.exoplayer:exoplayer:2.18.1'
}
```

2. **ProGuard rules** (if using code obfuscation) in `android/app/proguard-rules.pro`:

```proguard
# Keep DRM classes
-keep class com.google.android.exoplayer2.drm.** { *; }
-keep class com.google.android.exoplayer2.source.dash.** { *; }
```

3. **Permissions** (automatically included):

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS Setup

1. **Info.plist Configuration**:

Add the following to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

2. **Capabilities**:

Enable "Background Modes" in Xcode:
- Go to Signing & Capabilities
- Add Background Modes
- Enable "Audio, AirPlay, and Picture in Picture"

3. **FairPlay Certificate**:

Your FairPlay certificate must be:
- In DER format
- Accessible via HTTPS
- Valid and not expired

## Advanced Configuration

### Token-Based Authentication

```dart
final drmConfig = DrmConfig.token(
  licenseUrl: 'https://your-license-server.com/license',
  token: 'your_jwt_token',
  headers: {
    'X-Session-ID': 'session_123',
  },
);
```

### Custom License Request Headers

```dart
final drmConfig = DrmConfig(
  scheme: DrmScheme.widevine,
  licenseUrl: 'https://license-server.com/license',
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'X-User-ID': 'user_123',
    'X-Device-ID': 'device_456',
  },
  customData: {
    'userId': 'user_123',
    'contentId': 'movie_789',
  },
);
```

### Offline License Acquisition (Coming Soon)

```dart
final drmConfig = DrmConfig.widevine(
  licenseUrl: 'https://license-server.com/license',
  allowOffline: true,
  offlineLicenseDuration: Duration(days: 30).inSeconds,
);
```

## Monitoring DRM Sessions

Listen to DRM session state changes:

```dart
controller.player.drmSessionStream.listen((session) {
  print('DRM Session State: ${session.state}');
  
  switch (session.state) {
    case DrmSessionState.acquiringLicense:
      print('Acquiring license from server...');
      break;
    case DrmSessionState.licensed:
      print('License acquired successfully');
      if (session.license != null) {
        print('License expires: ${session.license!.expirationTime}');
      }
      break;
    case DrmSessionState.error:
      print('DRM Error: ${session.errorMessage}');
      break;
    default:
      break;
  }
});
```

## Testing DRM

### Test Content

#### Widevine (Android)
```dart
// Google's Widevine test content
final testItem = MediaItem(
  id: 'widevine_test',
  title: 'Widevine Test',
  url: 'https://storage.googleapis.com/wvmedia/cenc/h264/tears/tears.mpd',
  drmConfig: DrmConfig.widevine(
    licenseUrl: 'https://proxy.uat.widevine.com/proxy?provider=widevine_test',
  ),
);
```

#### ClearKey (Testing)
```dart
// ClearKey for testing both platforms
final testItem = MediaItem(
  id: 'clearkey_test',
  title: 'ClearKey Test',
  url: 'https://media.axprod.net/TestVectors/v7-Clear/Manifest_1080p.mpd',
  drmConfig: DrmConfig(
    scheme: DrmScheme.clearkey,
    licenseUrl: 'https://drm-clearkey-test.axtest.net/AcquireLicense',
  ),
);
```

### Checking DRM Support

```dart
// This would query native platform for DRM capabilities
bool isWidevineSupported = Platform.isAndroid; // Simplified
bool isFairPlaySupported = Platform.isIOS; // Simplified

print('Widevine: $isWidevineSupported');
print('FairPlay: $isFairPlaySupported');
```

## Troubleshooting

### Common Issues

#### Android Widevine

**Issue**: "Failed to create DRM session manager"
- **Solution**: Ensure your license URL is correct and the server is responding with proper Widevine licenses
- **Check**: Test on a physical device (emulators may have limited DRM support)

**Issue**: "Device does not support Widevine"
- **Solution**: Verify device has Widevine L1 or L3 support
- **Check**: Most modern Android devices (5.0+) support Widevine

#### iOS FairPlay

**Issue**: "Certificate not loaded"
- **Solution**: Verify certificate URL is accessible and certificate is in correct DER format
- **Check**: Certificate must be served over HTTPS

**Issue**: "License request failed"
- **Solution**: Ensure your FairPlay license server is properly configured
- **Check**: Review server logs for SPC (Server Playback Context) processing errors

### Debug Logging

Enable debug logging to troubleshoot DRM issues:

**Android**: Check `adb logcat` for `DrmHandler` logs
```bash
adb logcat | grep DrmHandler
```

**iOS**: Check Xcode console for `DrmHandler` logs

## Security Best Practices

### 1. Secure License URLs
- Always use HTTPS for license servers
- Implement certificate pinning for production apps
- Use short-lived tokens for authentication

### 2. Token Management
```dart
// Refresh tokens before they expire
Future<String> getValidToken() async {
  final token = await tokenService.getCurrentToken();
  if (tokenService.isExpiring(token)) {
    return await tokenService.refreshToken();
  }
  return token;
}

final drmConfig = DrmConfig.token(
  licenseUrl: 'https://license-server.com/license',
  token: await getValidToken(),
);
```

### 3. Content ID Handling
- Use unique content IDs per media item
- Avoid exposing sensitive data in content IDs
- Implement proper content ID validation on server side

### 4. Error Handling
```dart
try {
  await controller.load(mediaItemWithDrm);
  await controller.play();
} on MediaPlayerException catch (e) {
  if (e.message.contains('DRM')) {
    // Handle DRM-specific errors
    showError('Content protection error. Please try again.');
  }
}
```

## Production Deployment

### Checklist

- [ ] Test DRM playback on physical devices (both Android and iOS)
- [ ] Verify license server is production-ready
- [ ] Implement proper error handling and user messaging
- [ ] Test with various network conditions
- [ ] Implement analytics for DRM failures
- [ ] Set up monitoring for license server availability
- [ ] Document your DRM configuration for team
- [ ] Review security audit for license delivery
- [ ] Test token refresh mechanism
- [ ] Verify offline license renewal (if applicable)

## API Reference

### DrmConfig

Main configuration class for DRM:

```dart
DrmConfig({
  required DrmScheme scheme,
  required String licenseUrl,
  String? certificateUrl,
  Map<String, String>? headers,
  String? token,
  String? keyId,
  String? contentId,
  bool allowOffline = false,
  int? offlineLicenseDuration,
  bool autoRenewLicense = true,
  Map<String, dynamic>? customData,
  EzdrmConfig? ezdrmConfig,
})
```

### DrmScheme

Available DRM schemes:

- `DrmScheme.widevine` - Google Widevine (Android)
- `DrmScheme.fairplay` - Apple FairPlay (iOS)
- `DrmScheme.playready` - Microsoft PlayReady (Android)
- `DrmScheme.clearkey` - ClearKey (Testing)
- `DrmScheme.token` - Token-based custom DRM
- `DrmScheme.ezdrm` - EZDRM service

### DrmSession

Current DRM session information:

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

### DrmSessionState

Session states:

- `DrmSessionState.idle` - Not initialized
- `DrmSessionState.acquiringLicense` - Requesting license
- `DrmSessionState.licensed` - License acquired successfully
- `DrmSessionState.renewing` - Renewing license
- `DrmSessionState.error` - Error occurred
- `DrmSessionState.closed` - Session closed

## Support & Resources

### Useful Links

- **Widevine Documentation**: https://developers.google.com/widevine
- **FairPlay Streaming**: https://developer.apple.com/streaming/fps/
- **EZDRM**: https://www.ezdrm.com/
- **ExoPlayer DRM**: https://exoplayer.dev/drm.html

### Getting Help

If you encounter issues with DRM:

1. Check the example app's DRM demo page
2. Review this documentation
3. Check device DRM capabilities
4. Verify license server configuration
5. Enable debug logging
6. Open an issue on GitHub with:
   - Platform (Android/iOS)
   - Device model and OS version
   - DRM scheme used
   - Error logs
   - Steps to reproduce

## Conclusion

ZMedia Player provides comprehensive DRM support for protected content playback. By following this guide, you can implement secure, platform-native DRM in your Flutter application. For production deployments, ensure thorough testing across target devices and network conditions.


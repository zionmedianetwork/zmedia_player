# DRM (Digital Rights Management) - API Reference

## Overview

ZMedia Player provides comprehensive DRM support for protected content playback on both iOS and Android platforms.

**Current Status:** Online DRM is wired on both platforms — Widevine via Media3's
`DefaultDrmSessionManager` (Android) and FairPlay via `AVContentKeySession` (iOS). The Dart API
and native wiring are complete; **end-to-end decryption still warrants on-device verification**
with your own protected stream + license server (there are no native automated tests yet).
**Offline DRM:** not implemented on either platform — see [Offline DRM](#offline-drm) below.

---

## Supported DRM Systems

### Android
- **Widevine** (Google) — Level 1 (hardware-backed) and Level 3 (software), gated by
  `DrmConfig.minWidevineSecurityLevel` if you opt in
- **PlayReady** (Microsoft) — the `DrmScheme.playready` enum value exists and native code
  attempts to use it, but it only works on the rare Android device that ships a system
  PlayReady CDM. `DrmHandler.isPlayReadySupported()` gates every use of it and fails the
  session with `"PlayReady DRM is not supported on this device"` otherwise — this has been
  verified failing (`UnsupportedSchemeException`) on a real device. Do not rely on PlayReady
  working on a typical Android phone.
- **ClearKey** (for testing)

### iOS
- **FairPlay** (Apple) — the *only* DRM scheme iOS's native `DrmHandler` accepts. Any other
  `DrmScheme` (including `playready` and `widevine`) is rejected outright with
  `"Only FairPlay DRM is supported on iOS"` before it ever reaches DRM setup — **there is no
  PlayReady path on iOS at all**, not even a partial one.
- **FairPlay Streaming (FPS)**

### Cross-Platform
- **EZDRM** - Simplified DRM integration service

---

## Online DRM

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

`headers` and `customData` are not the same scope. `headers` applies to every DRM-related HTTP
request (Android: every request through the shared `HttpDataSource.Factory`, including
provisioning; iOS: both the FairPlay certificate fetch and the license `POST`). `customData` is
narrower — it is applied only to the license/key request itself: Android via
`HttpMediaDrmCallback.setKeyRequestProperty`, iOS as headers on the license `POST` only (not the
certificate `GET`). Values are converted for the wire: `String` passes through unchanged,
`bool`/`int`/`double` use their own string representation, nested `Map`/`List` values are
JSON-encoded, and `null`/unsupported values are skipped rather than sent as the literal string
`"null"`.

Both are copied by `DrmConfig.toMap()` rather than passed out by reference, so a caller that
mutates the serialized payload cannot mutate the config (and cannot corrupt the next
serialization of it). The copy is shallow, and `null` still serializes as a present key with a
`null` value. The `headers`/`customData` *fields* are not copied at construction — `DrmConfig`'s
constructor is `const` — so if you keep a reference to the map you passed in, you can still
mutate the config through it; pass a map you do not retain when that matters. See
[Models](models.md#tomap-returns-copies-not-live-references).

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
// DRM session state is exposed as a broadcast stream.
controller.player.drmSessionStream.listen((session) {
  if (session.license?.isExpired ?? false) {
    print('License expired, renewing...');
  }
});
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
  // Media3 automatically uses the highest security level the device offers
);
```

To instead *require* a minimum security level and fail closed rather than silently falling
back to unprotected/lower-security playback, set `minWidevineSecurityLevel` (Android/Widevine
only — see `WidevineSecurityLevel` in [Models](models.md#drm)):

```dart
final drmConfig = DrmConfig.widevine(
  licenseUrl: 'https://license.example.com/widevine',
  minWidevineSecurityLevel: WidevineSecurityLevel.l1, // hardware-backed only
);
```

Native `DrmHandler.validateDrmConfig()` checks the device's actual `MediaDrm` security level
before creating a DRM session, and refuses to create one — failing the load — if the device's
level is below the requested minimum, or if it cannot be determined at all (fail-closed).

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
- License, certificate, and media URLs must all use HTTPS — `InputValidator`
  (`lib/src/security/input_validation.dart`) enforces this in Dart before a
  DRM-protected `MediaItem` ever reaches native code, rejecting anything
  else. Because of that, FairPlay content needs **no** App Transport
  Security changes in `Info.plist`: you do not need
  `NSAllowsArbitraryLoads`, and this plugin does not read, add, or modify
  `Info.plist` on your behalf — that claim in earlier versions of this doc
  was incorrect. If your app *also* serves non-DRM content over plain HTTP
  elsewhere, see the ATS guidance in `docs/implementation/security.md`
  instead of disabling ATS globally.

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

## Offline DRM

Offline DRM — downloading DRM-protected content and playing it back later without a network
connection and without re-acquiring a license each time — is **not implemented on either
platform**. Concretely, this package has none of:

- Persistent Widevine licenses (Android's `OfflineLicenseHelper` is not used anywhere in this
  codebase)
- FairPlay persistable content keys (iOS's persistable `AVContentKeyResponse` path is not used)
- A download manager, download queue, or any storage-quota/expiration handling for downloaded
  DRM content

`DrmSession`/`DrmLicense` model a `renewalUrl` field and a `renewing` state, but nothing in
this package drives automatic license renewal either — see the note on `DrmConfig.renewalUrl`
in [Best Practices](#best-practices) below. Every DRM session in this package is online-only:
a license is acquired for the current playback session and is not persisted.

### Workarounds

If you need offline playback of DRM-protected content today, consider:

#### Option 1: Server-side download
Download content to your backend, serve it from your own CDN with your own authentication,
and skip package-level DRM entirely for that copy.

#### Option 2: Non-DRM content for local/offline playback
For content you can legitimately serve without DRM once downloaded, this package does support
local file playback via a `file://` URL — see [Local file playback](models.md#mediaitem) and
`LocalMediaUtils.fileUri`. A DRM-configured item cannot use this path: DRM requires an HTTPS
media URL, so a `file://` `MediaItem` with a `drmConfig` is rejected by validation.

```dart
final MediaItem item;
if (isOfflineMode) {
  item = MediaItem(
    id: mediaId,
    title: title,
    url: LocalMediaUtils.fileUri(localFilePath), // no drmConfig
  );
} else {
  item = MediaItem(
    id: mediaId,
    title: title,
    url: streamUrl,
    drmConfig: drmConfig, // DRM for streaming only
  );
}
```

#### Option 3: Short-lived online licenses
Re-acquire a license each time playback starts, accepting that this requires connectivity at
that moment even if the media bytes themselves are cached (see
[Advanced Features](advanced-features.md#caching--offline) for what *is* cacheable —
progressive, non-DRM media only).

---

## Best Practices

### 1. Licenses are session-scoped, not cached by this package

There is no `clearDrmCache()` method and no license-caching layer in this package — each DRM
session is acquired for the current playback session via the native player's own DRM session
manager (`DefaultDrmSessionManager` on Android, `AVContentKeySession` on iOS) and is not
persisted or reused across app restarts. If you need to force a fresh license, `stop()` and
`load()` the item again; there is nothing else to clear.

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
- **Solution:** Re-acquire the license (there is no built-in auto-renewal; see the note above `DrmConfig`)

### Debug Logging

```dart
// Enable DRM debug logs
MediaPlayer.enableCrashReporting(
  ConsoleOnlyCrashReporter(), // Logs all errors to console
);

// Inspect DRM session details as they change
controller.player.drmSessionStream.listen((session) {
  print('DRM Session: ${session.toMap()}');
});
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
  final Map<String, dynamic>? customData;
  final EzdrmConfig? ezdrmConfig;
  final CertificatePinningConfig? certificatePinning;
  final WidevineSecurityLevel? minWidevineSecurityLevel; // Android/Widevine only
}
```

### DrmScheme Enum

```dart
enum DrmScheme {
  token,      // Custom token-based
  widevine,   // Google Widevine (Android)
  fairplay,   // Apple FairPlay (iOS)
  ezdrm,      // EZDRM service
  playready,  // Microsoft PlayReady (Android only, and only on the rare device with a system
              // PlayReady CDM; no iOS path at all — see Supported DRM Systems above)
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
  id: 'video-1',
  title: 'Video',
  url: videoUrl,
  drmConfig: DrmConfig.widevine(licenseUrl: licenseUrl),
);
```

#### From video_player
```dart
// video_player (no DRM support)
VideoPlayerController.networkUrl(Uri.parse(videoUrl));

// ZMedia Player
final controller = MediaController.create();
await controller.load(MediaItem(
  id: 'video-1',
  title: 'Video',
  url: videoUrl,
  drmConfig: drmConfig,
));
```

---

## Security

**Implemented:**
- License and certificate requests enforce HTTPS (`InputValidator` rejects anything else
  before a DRM-protected `MediaItem` reaches native code)
- Optional certificate pinning for the DRM license server (`DrmConfig.certificatePinning`)
- No DRM key material is persisted to disk by this package — see [Offline DRM](#offline-drm)
- Opt-in fail-closed minimum Widevine security level (`DrmConfig.minWidevineSecurityLevel`,
  Android only)

**Not implemented — do not assume these exist:**
- Automatic license renewal/rotation. `DrmSessionState.renewing` and `DrmLicense.renewalUrl`
  are modeled but nothing in this package drives renewal; re-acquire a license the same way
  you acquired it the first time (`stop()` + `load()`).
- License caching/clearing (see [Best Practices](#best-practices) above).

**Recommendations:**
- Use hardware-backed DRM when available (Widevine L1) — set `minWidevineSecurityLevel` if you
  need to enforce it rather than just prefer it
- Implement certificate pinning for production license servers
- Monitor for unusual license request patterns on your own license server

---

## Additional Resources

### Documentation
- [Security](../implementation/security.md)
- [Testing Guide](../implementation/testing.md)

### External Links
- [Widevine Documentation](https://www.widevine.com/)
- [FairPlay Streaming](https://developer.apple.com/streaming/fps/)
- [EZDRM Service](https://www.ezdrm.com/)

### Support
- [GitHub Issues](https://github.com/zionmedianetwork/zmedia_player/issues)
- [GitHub Discussions](https://github.com/zionmedianetwork/zmedia_player/discussions)

---

**Note:** This documentation reflects the current state of DRM support. Offline DRM is not
implemented — see [Offline DRM](#offline-drm) above.

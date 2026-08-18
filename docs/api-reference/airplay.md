# iOS AirPlay Implementation Guide

## Why Device Discovery Works Differently on iOS

### The Key Difference

**Android (Chromecast):**
- Apps can enumerate available devices
- Apps can show a custom device list
- Users select from app's UI

**iOS (AirPlay):**
- Apps **cannot** enumerate devices programmatically
- System manages device discovery automatically
- Users select via system AirPlay picker (AVRoutePickerView)

### Technical Limitation

Apple **intentionally restricts** programmatic access to AirPlay device lists for privacy and security reasons. The `AVAudioSession` and `AVPlayer` APIs do NOT expose methods to:
- List available AirPlay receivers
- Query device names before connection
- Programmatically trigger device selection

### What IS Possible

**Detect if AirPlay is available** (system has discovered devices)
**Detect when AirPlay connection changes** (connected/disconnected)
**Get info about currently connected device** (after user selects it)
**Show native AirPlay picker button** (`AVRoutePickerView`)

## Implementation in zmediaplayer

### Current Behavior

`startCastDiscovery()` / `controller.player.castDevicesStream` on iOS do **not** return a
placeholder device to tap. `AirPlayHandler.getAvailableDevices()` (native) can only ever return
the *currently connected* AirPlay device (if any) — an empty list otherwise, exactly reflecting
Apple's restriction that apps cannot enumerate or trigger the picker programmatically:

```dart
// Only present once AirPlay is actually connected — never a "tap to select" placeholder
{
  "id": "<route uid>",
  "name": "<route port name>",
  "type": "airplay",
  "model": "",
  "manufacturer": "Apple",
  "isConnected": true
}
```

The device-list stream is not the way to let a user *initiate* an AirPlay connection on iOS —
use the native `AirPlayButton` for that (see below); the cast-device stream is only useful here
for reflecting an *already-connected* device's info back into your own UI.

### How Users Cast to MacBook (iOS)

#### Step 1: Enable AirPlay Receiver on Mac
```
System Settings → General → AirDrop & Handoff → Enable "AirPlay Receiver"
```

#### Step 2: Ensure Same Wi-Fi Network
Both iPhone and Mac must be on the same network.

#### Step 3: Use Native Player Controls
The AirPlay button () appears automatically in the native video player when:
- AirPlay receivers are available on the network
- Video is playing
- Audio session is configured for AirPlay (done automatically by zmediaplayer)

#### Step 4: Select Device
Tap the AirPlay button → Select MacBook from system picker

## Implementation Details

### AirPlayHandler.swift

```swift
private func getAvailableDevices() -> [[String: Any]] {
    var devices: [[String: Any]] = []

    // iOS cannot enumerate AirPlay devices programmatically — they're discovered
    // and shown by the system's AVRoutePickerView (the native AirPlayButton).
    // Only report the currently connected device, if any.
    if let currentDevice = getCurrentDevice() {
        devices.append(currentDevice)
    }

    return devices
}
```

### Key Configuration

The following are configured in `AirPlayHandler.swift` to enable AirPlay:

1. **Audio Session:**
   ```swift
   try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
   ```

2. **Route Change Notifications:**
   - Monitors `AVAudioSession.routeChangeNotification`
   - Detects when AirPlay connects/disconnects
   - Updates Flutter via `onCastStatusChanged`

3. **AVPlayer Configuration:**
   - `allowsExternalPlayback = true`
   - `usesExternalPlaybackWhileExternalScreenIsActive = true`

### Info.plist Requirements

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Required to discover and connect to AirPlay devices on your local network</string>

<key>NSBonjourServices</key>
<array>
    <string>_airplay._tcp</string>
    <string>_raop._tcp</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

## Native AVRoutePickerView: already implemented

Unlike the placeholder-device flow above, this package **ships** a real `AVRoutePickerView`
platform view — `AirPlayButton` (`lib/src/widgets/airplay_button.dart`). It renders the native
route picker directly (no informative-dialog detour) and is the recommended way to expose
AirPlay to users on iOS:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

if (Platform.isIOS)
  AirPlayButton(
    size: 32.0,
    tintColor: Colors.white,
    activeTintColor: Colors.blue,      // shown while AirPlay is connected
    prioritizesVideoDevices: true,
  ),
```

On Android this widget renders as `SizedBox.shrink()` (nothing) — it is iOS-only, matching
AirPlay's own platform scope. `MediaControls`/`MaterialMediaControls` already include an
`AirPlayButton` in their cast slot on iOS; see
[Advanced Features → Casting](advanced-features.md#casting-chromecast--airplay).

### Native implementation

The platform view is backed by `zmedia_player/airplay_button` (registered by
`AirPlayButtonFactory` in the iOS native plugin), which wraps `AVRoutePickerView` directly —
no custom device list, matching Apple's model described above.

## Best Practices

### DO:
- Show informative messages about how AirPlay works on iOS
- Guide users to the native AirPlay button in player controls
- Detect and display currently connected AirPlay device
- Handle AirPlay connection state changes

### DON'T:
- Try to enumerate devices programmatically
- Promise device list functionality on iOS
- Create custom device pickers (won't show actual devices)
- Try to programmatically trigger AirPlay connection

## Troubleshooting

### "No devices found"

**Check:**
1. Mac has "AirPlay Receiver" enabled
2. Both devices on same Wi-Fi network
3. Firewall isn't blocking Bonjour/mDNS
4. Info.plist has all required keys

### "Can't see MacBook in list"

**Expected:** iOS doesn't show device list in app - users must use native AirPlay button in video player controls.

### "Want custom AirPlay button"

**Solution:** Use the `AirPlayButton` widget this package already ships (see
[Native AVRoutePickerView: already implemented](#native-avroutepickerview-already-implemented)
above) — no need to build a platform view yourself.

## Summary

iOS AirPlay is **fundamentally different** from Android Chromecast. The current implementation:

Properly configures audio session for AirPlay
Detects connection state changes
Provides clear user guidance
Works with native player controls

Cannot show device list (Apple limitation)
Cannot programmatically trigger picker (Apple limitation)

This is **not a bug** - it's how Apple designed AirPlay to work for all iOS apps.

# iOS AirPlay Implementation Guide

## Why Device Discovery Works Differently on iOS

### The Key Difference

**Android (Chromecast):**
- ✅ Apps can enumerate available devices
- ✅ Apps can show a custom device list
- ✅ Users select from app's UI

**iOS (AirPlay):**
- ❌ Apps **cannot** enumerate devices programmatically
- ✅ System manages device discovery automatically
- ✅ Users select via system AirPlay picker (AVRoutePickerView)

### Technical Limitation

Apple **intentionally restricts** programmatic access to AirPlay device lists for privacy and security reasons. The `AVAudioSession` and `AVPlayer` APIs do NOT expose methods to:
- List available AirPlay receivers
- Query device names before connection
- Programmatically trigger device selection

### What IS Possible

✅ **Detect if AirPlay is available** (system has discovered devices)
✅ **Detect when AirPlay connection changes** (connected/disconnected)
✅ **Get info about currently connected device** (after user selects it)
✅ **Show native AirPlay picker button** (`AVRoutePickerView`)

## Implementation in zmediaplayer

### Current Behavior

When `startCastDiscovery()` is called on iOS:

1. **Returns a placeholder device:**
   ```dart
   {
     "id": "airplay_system",
     "name": "AirPlay & Bluetooth",
     "type": "airplay",
     "isConnected": false,
     "requiresUserInteraction": true,
     "description": "Tap to select AirPlay or Bluetooth device"
   }
   ```

2. **When user taps this device:**
   - Shows an informative dialog
   - Explains how AirPlay works on iOS
   - Provides step-by-step setup instructions

### How Users Cast to MacBook (iOS)

#### Step 1: Enable AirPlay Receiver on Mac
```
System Settings → General → AirDrop & Handoff → Enable "AirPlay Receiver"
```

#### Step 2: Ensure Same Wi-Fi Network
Both iPhone and Mac must be on the same network.

#### Step 3: Use Native Player Controls
The AirPlay button (📡) appears automatically in the native video player when:
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

    // If AirPlay is active, return current device
    if let currentDevice = getCurrentDevice() {
        devices.append(currentDevice)
    } else {
        // Always show placeholder indicating system picker is required
        devices.append([
            "id": "airplay_system",
            "name": "AirPlay & Bluetooth",
            "type": "airplay",
            "isConnected": false,
            "requiresUserInteraction": true,
            "description": "Tap to select AirPlay or Bluetooth device"
        ])
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

## Alternative: Native AVRoutePickerView

For a better iOS experience, you could add a native `AVRoutePickerView` widget:

### Concept Implementation

```dart
// Platform view for native AirPlay button
class AirPlayButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return SizedBox.shrink();

    return SizedBox(
      width: 40,
      height: 40,
      child: UiKitView(
        viewType: 'airplay_route_picker',
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}
```

### Native Implementation

```swift
class AVRoutePickerViewFactory: NSObject, FlutterPlatformViewFactory {
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return AVRoutePickerViewController(frame: frame)
    }
}

class AVRoutePickerViewController: NSObject, FlutterPlatformView {
    private let routePicker: AVRoutePickerView

    init(frame: CGRect) {
        routePicker = AVRoutePickerView(frame: frame)
        routePicker.tintColor = .systemBlue
    }

    func view() -> UIView {
        return routePicker
    }
}
```

## Best Practices

### ✅ DO:
- Show informative messages about how AirPlay works on iOS
- Guide users to the native AirPlay button in player controls
- Detect and display currently connected AirPlay device
- Handle AirPlay connection state changes

### ❌ DON'T:
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

**Solution:** Implement `AVRoutePickerView` as a platform view (see Alternative section above).

## Summary

iOS AirPlay is **fundamentally different** from Android Chromecast. The current implementation:

✅ Properly configures audio session for AirPlay
✅ Detects connection state changes
✅ Provides clear user guidance
✅ Works with native player controls

❌ Cannot show device list (Apple limitation)
❌ Cannot programmatically trigger picker (Apple limitation)

This is **not a bug** - it's how Apple designed AirPlay to work for all iOS apps.

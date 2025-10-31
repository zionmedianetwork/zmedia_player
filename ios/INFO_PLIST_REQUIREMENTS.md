# iOS Info.plist Requirements for Phase 3 Features

This document outlines the required Info.plist keys and capabilities for Phase 3 features in the Flutter Media Player plugin.

## Background Modes

Add the following to your app's `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>video</string>
</array>
```

**Purpose**: Enables audio and video playback to continue when the app is in the background. Required for:
- Media notifications to work when app is backgrounded
- AirPlay to continue working in background
- Picture-in-Picture mode

## Audio Session

```xml
<key>UIRequiresPersistentWiFi</key>
<false/>
```

**Purpose**: Allows the app to maintain WiFi connection while in background. Optional but recommended for streaming media.

## AirPlay

AirPlay works automatically with `AVPlayer`. No additional Info.plist keys required for basic functionality.

However, you may want to add:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses the local network to discover and connect to AirPlay devices.</string>
```

**Purpose**: Required on iOS 14+ for local network discovery (Bonjour services).

## Picture-in-Picture

PiP is automatically enabled when:
1. Background modes include `audio`
2. Your `AVPlayer` is configured for external playback

No additional Info.plist keys required.

## Full Example Info.plist Additions

Add these keys to your iOS app's `Info.plist` file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing keys... -->

    <!-- Phase 3: Background audio/video playback -->
    <key>UIBackgroundModes</key>
    <array>
        <string>audio</string>
        <string>video</string>
    </array>

    <!-- Phase 3: Local network for AirPlay discovery (iOS 14+) -->
    <key>NSLocalNetworkUsageDescription</key>
    <string>This app uses the local network to discover and connect to AirPlay devices for media streaming.</string>

    <!-- Optional: Bonjour services for AirPlay -->
    <key>NSBonjourServices</key>
    <array>
        <string>_airplay._tcp</string>
        <string>_raop._tcp</string>
    </array>

</dict>
</plist>
```

## Example App Info.plist Location

For the example app, add these keys to:
```
example/ios/Runner/Info.plist
```

## Implementing in Your App

When integrating this plugin into your own Flutter app, add the above keys to your app's Info.plist file at:
```
ios/Runner/Info.plist
```

## Capabilities in Xcode

In addition to Info.plist changes, you should enable the following capabilities in Xcode:

1. Open your project in Xcode
2. Select your target (Runner)
3. Go to "Signing & Capabilities" tab
4. Add the following capabilities if not already present:
   - **Background Modes**
     - ✓ Audio, AirPlay, and Picture in Picture
   - **Network** (for AirPlay discovery)

## Testing Checklist

After adding these permissions:

- [ ] Media notifications appear when app is backgrounded
- [ ] Media controls in Control Center work correctly
- [ ] Lock screen controls appear and function
- [ ] AirPlay icon appears in player controls
- [ ] AirPlay device discovery works
- [ ] Picture-in-Picture button appears (iPadOS and iOS 14+)
- [ ] PiP mode works when switching apps

## iOS Version Requirements

- **Notifications (MPNowPlayingInfoCenter)**: iOS 9.0+
- **AirPlay**: iOS 9.0+
- **Picture-in-Picture**: iOS 9.0+ (iPad), iOS 14.0+ (iPhone)

## Notes

- PiP on iPhone requires iOS 14.0+
- PiP on iPad is available from iOS 9.0+
- Local network permission prompt will appear first time app tries to discover AirPlay devices on iOS 14+
- Background audio/video is essential for notifications and AirPlay to work properly

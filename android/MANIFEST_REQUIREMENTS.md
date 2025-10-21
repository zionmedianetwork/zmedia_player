# Android AndroidManifest.xml Requirements for Phase 3 Features

This document outlines the required permissions and configurations for Phase 3 features in the Flutter Media Player plugin.

## Required Permissions

Add the following permissions to your app's `AndroidManifest.xml`:

```xml
<!-- Internet permission for streaming media -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- Network state permission for adaptive streaming -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- WiFi state permission for network quality monitoring -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

<!-- Foreground service permission for media playback notifications (Android 9+) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />

<!-- Media projection permission for casting (Android 5.0+) -->
<uses-permission android:name="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" />

<!-- Wake lock to keep device awake during playback -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

## Application Configuration

Update your `<application>` tag to include:

```xml
<application
    ...
    android:usesCleartextTraffic="true">
    
    <!-- Your existing activities... -->
    
    <!-- Phase 3: PiP Support -->
    <!-- Add to your main activity: -->
    <activity
        android:name=".MainActivity"
        android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout"
        android:supportsPictureInPicture="true"
        android:resizeableActivity="true">
        <!-- Your existing intent filters... -->
    </activity>
    
</application>
```

## Feature Declarations

Declare the features your app uses:

```xml
<!-- Picture-in-Picture support (Android 8.0+) -->
<uses-feature
    android:name="android.software.picture_in_picture"
    android:required="false" />

<!-- Google Cast support -->
<uses-feature
    android:name="com.google.android.gms.cast.framework"
    android:required="false" />
```

## Full Example AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.zionmedianetwork.zmedia_player_example">

    <!-- Phase 3: Required Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    
    <!-- Phase 3: Optional Features -->
    <uses-feature
        android:name="android.software.picture_in_picture"
        android:required="false" />
    <uses-feature
        android:name="com.google.android.gms.cast.framework"
        android:required="false" />

    <application
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:label="Flutter Media Player Example"
        android:usesCleartextTraffic="true">
        
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize"
            android:supportsPictureInPicture="true"
            android:resizeableActivity="true">
            
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        
        <!-- Phase 3: Google Cast Options Provider (if using Chromecast) -->
        <meta-data
            android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
            android:value="com.zionmedianetwork.zmedia_player.CastOptionsProvider" />
        
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
            
    </application>
</manifest>
```

## Google Cast Configuration

For Chromecast support, you need to create a `CastOptionsProvider` class. This is already included in the plugin at:

```
android/src/main/kotlin/com/zionmedianetwork/zmedia_player/CastOptionsProvider.kt
```

Make sure the `<meta-data>` tag in your manifest points to the correct package path.

## PiP Activity Configuration

For Picture-in-Picture to work properly:

1. Add `android:supportsPictureInPicture="true"` to your activity
2. Add `android:resizeableActivity="true"` to your activity
3. Include configuration changes: `"orientation|screenSize|smallestScreenSize|screenLayout"`

## Testing Checklist

After adding these permissions:

- [ ] Media notifications appear during playback
- [ ] Notification controls (play/pause/next/previous) work
- [ ] PiP button appears in controls (Android 8.0+)
- [ ] PiP mode works when minimizing app
- [ ] Cast button appears in player
- [ ] Chromecast device discovery works
- [ ] Can connect to Chromecast device
- [ ] Media plays on connected Chromecast

## Android Version Requirements

- **Notifications (MediaSession)**: Android 5.0 (API 21)+
- **Picture-in-Picture**: Android 8.0 (API 26)+
- **Chromecast**: Android 5.0 (API 21)+

## Notes

- `usesCleartextTraffic="true"` allows HTTP traffic for development/testing
- For production, use HTTPS and remove or set to `false`
- Foreground service permission is required for persistent media notifications
- PiP requires `resizeableActivity="true"` on Android 7.0+
- Google Cast Framework requires Google Play Services


# Advanced Features

Notifications, Picture-in-Picture, casting, list playback, caching, and fullscreen display.
For live streaming see [Live Streaming](live-streaming.md); for DRM see [DRM](drm.md).

## Media notifications

Lock-screen / Control Center controls backed by `NotificationService`.

```dart
final notifications = NotificationService(const NotificationConfig(
  enabled: true,
  channelId: 'media_playback',
  showPlayPause: true,
  showNext: true,
  showPrevious: true,
));

// Pass the player so lock-screen state stays in sync with playback:
await notifications.initialize(controller.playerId, mediaPlayer: controller.player);

await notifications.show(
  mediaItem: item,
  state: controller.state,
  playerId: controller.playerId,
);

notifications.actionStream.listen((action) {
  switch (action) {
    case 'play': controller.play(); break;
    case 'pause': controller.pause(); break;
    case 'next': controller.skipToNext(); break;
    case 'previous': controller.skipToPrevious(); break;
    case 'seekForward': controller.seekForward(); break;
    case 'seekBackward': controller.seekBackward(); break;
  }
});

await notifications.dismiss(controller.playerId);
```

- Passing `mediaPlayer:` lets the service mirror playback state to the Now Playing info.
- If `MediaItem.artworkUrl` is null, artwork is generated from a video frame (iOS
  `AVAssetImageGenerator`, Android `MediaMetadataRetriever`).
- iOS background audio requires `UIBackgroundModes: audio`; Android 13+ requires the
  `POST_NOTIFICATIONS` runtime permission.

## Picture-in-Picture

```dart
if (await controller.checkPipAvailability()) {
  await controller.enterPictureInPicture();
}
await controller.exitPictureInPicture();
controller.pipStatusStream.listen((s) => print('PiP active: ${s.isActive}'));
```

- iOS: physical device (`AVPictureInPictureController`).
- Android: API 26+. Relay `onPictureInPictureModeChanged` from your Activity to the plugin.
- `checkPipAvailability()` returns false on unsupported devices.

## Casting (Chromecast / AirPlay)

```dart
await controller.startCastDiscovery();
controller.player.castDevicesStream.listen((devices) => setState(() => _devices = devices));

await controller.connectAndLoadMedia(device); // or connectToCastDevice(device)
controller.castStatusStream.listen((s) => print(s.state));
await controller.disconnectFromCastDevice();
```

For an iOS-native AirPlay route picker, use the `AirPlayButton` widget (iOS only). Chromecast
needs Google Play Services and a device on the same Wi-Fi; AirPlay needs an AirPlay target.

## List playback

`MediaListPlayer` plays/pauses based on scroll visibility.

```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => MediaListPlayer(
    controller: controllers[i], // one controller per row; dispose them all
    aspectRatio: 16 / 9,
    showControls: true,
  ),
);
```

Use distinct `playerId`s for concurrent players; native events route by `playerId`.

## Caching / offline

```dart
final cache = CacheService(const CacheConfig(
  maxCacheSize: 200 * 1024 * 1024,
  cacheExpiration: Duration(days: 7),
  enabled: true,
));
await cache.cacheMedia(mediaItem.url);
final cached = await cache.isCached(mediaItem.url);
await cache.clearCache();
```

## Fullscreen & display

- Wrappers: `FullscreenMediaPlayer`, `MaterialFullscreenPlayer`, `CupertinoFullscreenPlayer`.
- Share a single `MediaController` across the inline and fullscreen routes so playback continues seamlessly.
- Display flags on `MediaConfig`:
  - `respectSafeArea: true` insets the video below the status bar/notch.
  - `immersiveLandscape: true` hides the system status bar in landscape (restored on portrait/dispose).

### Orientation control

`FullscreenMediaPlayer` no longer forces landscape. Three optional, non-breaking
parameters let you choose the orientation behavior (omit them all to keep the legacy
landscape-locked default):

```dart
FullscreenMediaPlayer(
  controller: controller,
  // Orientations applied while fullscreen is active.
  // Omit (or pass null) to keep the default [landscapeLeft, landscapeRight].
  preferredOrientations: const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ],
  // Live rotation lock: when the listenable's value is true the device is pinned
  // to portraitUp; flipping it back to false re-applies preferredOrientations.
  rotationLocked: rotationLockNotifier, // ValueListenable<bool>?
  // Orientations restored on exit (default: all four). A portrait-locked app can
  // restore just portraitUp so it never briefly unlocks landscape on pop.
  exitOrientations: const [DeviceOrientation.portraitUp],
)
```

- `preferredOrientations` — portrait fullscreen, free rotation, or any custom set.
- `rotationLocked` — bind to a settings toggle; the widget re-applies orientations
  live when the value changes (it subscribes/unsubscribes automatically).
- `exitOrientations` — what to restore when the route pops.

### Android native view (Hybrid Composition)

On Android the inline/fullscreen video surface is composited with **true Hybrid
Composition** (`PlatformViewsService.initExpensiveAndroidView`) rather than a Virtual
Display `AndroidView`. This eliminates the `VirtualDisplayController` resize race that
could throw an NPE (`getRenderTargetWidth → getWidth()` on a released surface) or render
black on fullscreen exit. No consumer action is required — this is internal to
`MediaPlayerWidget`.

## Bandwidth & buffering

```dart
controller.player.bandwidthStream.listen((bps) => print('$bps bps'));
controller.player.bufferHealthStream.listen((h) => print(h.status));
```

`BufferingService` and `NetworkResilienceService` expose buffer-health and network-status
streams for custom indicators. `AnalyticsService` collects QoE metrics (`QoEMetrics`).

## Custom controls

Subclass `CustomControlsBase` and implement `buildControls(context, ControlsState)`, then pass
your widget to `MediaPlayerWidget(customControls: …)`. See the example app's
"Fully Custom Controls & Overlay" page.

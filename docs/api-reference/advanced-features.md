# Advanced Features

Notifications, Picture-in-Picture, casting, list playback, caching, and fullscreen display.
For live streaming see [Live Streaming](live-streaming.md); for DRM see [DRM](drm.md).

## Media notifications

Lock-screen / Control Center controls backed by `NotificationService`.

> **Required: subscribe to `actionEventStream`.** `NotificationService` only renders
> the lock-screen / Control Center UI and forwards taps as events on
> `actionEventStream` — it does **not** call `play()`/`pause()`/`skipToNext()`/
> `seekTo()` etc. on your behalf. If your app shows a notification without listening
> to `actionEventStream` and routing each event to the controller (as in the snippet
> below), the notification will render correctly but every button on it will do
> nothing when tapped. This is easy to miss because there is no error: the
> notification looks complete, and only manual testing reveals the dead buttons.
> **This is the package's contract, not a bug**: `NotificationService` renders and
> forwards; your host app performs the actual playback calls.

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

notifications.actionEventStream.listen((event) {
  switch (event.action) {
    case 'play': controller.play(); break;
    case 'pause': controller.pause(); break;
    case 'next': controller.skipToNext(); break;
    case 'previous': controller.skipToPrevious(); break;
    case 'seekForward': controller.seekForward(); break;
    case 'seekBackward': controller.seekBackward(); break;
    case NotificationActions.seekTo:
      // Dragging the lock-screen / Control Center scrub bar. event.position
      // is only ever non-null for this action — your app must call seekTo()
      // itself; NotificationService does not.
      if (event.position != null) controller.seekTo(event.position!);
      break;
  }
});

await notifications.dismiss(controller.playerId);
```

- Passing `mediaPlayer:` lets the service mirror playback state to the Now Playing info.
- If `MediaItem.artworkUrl` is null, artwork is generated from a video frame (iOS
  `AVAssetImageGenerator`, Android `MediaMetadataRetriever`).
- iOS background audio requires `UIBackgroundModes: audio`; Android 13+ requires the
  `POST_NOTIFICATIONS` runtime permission.
- `actionEventStream` emits `NotificationActionEvent` (`action` + an optional
  `position`). The older `Stream<String> actionStream` still works and receives every
  action (including `"seekTo"`) but is `@Deprecated` because it cannot carry
  `position` — dragging the scrub bar is unactionable through it. Prefer
  `actionEventStream` in new code.

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

`MediaListPlayer` wraps one host-supplied `MediaController` per row — the host creates and
disposes every controller, so a long scroll can accumulate as many live native decoder
sessions as rows have ever been visible. For feeds where that needs to be bounded, use
`MediaFeed` instead (below).

## Media Feed

`MediaFeed` owns a small, package-managed `MediaPlayerPool` internally instead of taking a
host-owned `MediaController` per item. It owns `itemCount` media *descriptors*, not
controllers, and reassigns a bounded pool of controllers across items as they scroll into and
out of view — the host never sees or disposes a `MediaController` directly.

```dart
MediaFeed(
  itemCount: items.length,
  itemAt: (index) => items[index],
  itemBuilder: (context, state) {
    if (!state.isActive) {
      return const ColoredBox(color: Colors.black12); // placeholder — no pool slot yet
    }
    return state.videoSurface; // MediaPlayerWidget-backed surface for this slot
  },
  config: const MediaFeedConfig(
    visibilityThreshold: 0.6,
    autoPlay: true,
    autoPause: true,       // VOD: pause off-screen and keep the slot; live: release the slot
    pauseOthersOnPlay: true,
    prewarmWindow: 1,      // load() (never play()) this many neighbours on each side
    activationDebounce: Duration(milliseconds: 500),
  ),
  maxPoolSize: MediaPlayerPool.defaultMaxSize, // 3 — a conservative, profiled default
);
```

- `MediaFeedItemState` (passed to `itemBuilder`) exposes `isActive`, `isVisible`, and action
  callbacks (`play`, `pause`, …) that are `null` when the index does not currently hold a pool
  slot — there is nothing to act on yet.
- `MediaFeedConfig.autoPlayPolicy` (a `MediaFeedAutoPlayPolicy`) can refuse autoplay based on
  `NetworkStatus` — `null` (default) autoplays regardless of network, matching prior behavior;
  pass the ready-made `conservativeAutoPlayPolicy` to refuse on a metered or poor/offline
  connection.
- Pool slots are keyed by `MediaItem.id` by default; supply `keyAt` if the same id can appear
  at two simultaneously-active indices.
- `MediaListPlayer` is unaffected by `MediaFeed`'s existence and remains the right choice for a
  single host-owned controller inside a scrollable — `MediaFeed` is additive, for the case
  where the package should own the whole feed's controller lifetime.
- `MediaPlayerPool` can also be used directly (advanced use — sharing one pool across more than
  one `MediaFeed`, or a fake controller factory in tests) and is a `ChangeNotifier`.

## Caching / offline

Only progressive (single-file) media can be cached — HLS/DASH manifests are not
supported by `CacheService`.

```dart
final cache = CacheService(const CacheConfig(
  maxCacheSize: 200 * 1024 * 1024,
  cacheExpiration: Duration(days: 7),
  enabled: true,
));
await cache.initialize();

// Download once (requires network). Safe to call again: it's a no-op if the
// item is already cached.
await cache.downloadAndCache(mediaItem);

final cached = await cache.isCached(mediaItem.id);

// Later — with or without network — build a MediaItem that points at the
// on-disk copy and play it through the normal load path.
final cachedItem = await cache.getCachedMediaItem(mediaItem.id);
if (cachedItem != null) {
  await controller.load(cachedItem);
}

await cache.clearCache();
```

`getCachedMediaItem` returns `null` once the entry has expired
(`cacheExpiration`) or been evicted for space — fall back to downloading
`mediaItem` again in that case. DRM-protected items cannot be played from a
cached copy: DRM requires an HTTPS media URL, and the cached copy is always a
`file://` URI, so it's rejected by validation — offline DRM playback isn't
supported.

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

## Errors

`MediaController.errorStream` (and `MediaController.error`, the most recently observed value)
surface typed playback errors through the facade without reaching into `controller.player`:

```dart
controller.errorStream.listen((error) {
  if (error is DrmException) {
    showError('DRM error: ${error.message}');
  } else {
    showError(error.message);
  }
});

// Or read the last error without subscribing:
if (controller.error != null) {
  showError(controller.error!.message);
}
```

This mirrors `MediaPlayer.errorStream`; `MediaController` clears its cached `error` once the
condition that caused it is no longer current.

## Screen capture protection

`MediaConfig.secureSurface` (default `false`) is deliberately asymmetric across platforms:

```dart
final controller = MediaController.create(
  config: const MediaConfig(secureSurface: true),
);

// Toggle after construction:
await controller.setSecureSurface(false);

// iOS only ever emits here — Android's block leaves nothing to detect.
controller.screenCaptureStream.listen((status) {
  if (status.isCaptured) showCaptureWarningOverlay();
});
```

- **Android:** `enabled: true` adds `FLAG_SECURE` to the host window — a hard OS-level block.
  Screenshots and screen recordings of that window fail outright, and `screenCaptureStream`
  never emits there (there is nothing to report).
- **iOS:** there is no equivalent OS-level block available to a third-party app.
  `enabled: true` instead starts observing `UIScreen.isCaptured` and reports changes via
  `screenCaptureStream` — detection only. The host app is responsible for reacting to a `true`
  value (e.g. pausing, or showing a warning overlay) for as long as it stays `true`.

## Custom controls

Subclass `CustomControlsBase` and implement `buildControls(context, ControlsState)`, then pass
your widget to `MediaPlayerWidget(customControls: …)`. See the example app's
"Fully Custom Controls & Overlay" page.

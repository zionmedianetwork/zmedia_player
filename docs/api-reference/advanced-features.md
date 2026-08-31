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
  // Seek controls are opt-in (both default to false) and are only rendered when
  // the current item is actually seekable — see the seek-control notes below.
  showSeekForward: true,
  showSeekBackward: true,
  seekInterval: 10, // display-only: labels the buttons / iOS preferredIntervals
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
    // NotificationActions.seekForward / .seekBackward ('seekForward' /
    // 'seekBackward'). seekInterval is a label only — pass the matching
    // Duration yourself so the button's "10s" is truthful.
    case NotificationActions.seekForward:
      controller.seekForward(const Duration(seconds: 10));
      break;
    case NotificationActions.seekBackward:
      controller.seekBackward(const Duration(seconds: 10));
      break;
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
- `NotificationConfig.showSeekForward` / `.showSeekBackward` gate the seek controls on
  **both** platforms, with one shared contract: **a seek control is offered if and only if
  the flag is `true` AND the current item is seekable** (`MediaPlayer.isSeekable` — i.e. not
  a live stream without DVR). Both default to `false`, so seek controls are opt-in. On
  Android the flag adds a `NotificationCompat.Action` (`"Forward 10s"` / `"Back 10s"`) and
  advertises `ACTION_FAST_FORWARD` / `ACTION_REWIND` on the media session, so Bluetooth /
  Android Auto / Wear surfaces offer it too; on iOS it enables
  `MPRemoteCommandCenter.skipForwardCommand` / `.skipBackwardCommand`. The gating is
  re-evaluated on every notification update, so toggling DVR on a live stream mid-playback
  adds or removes the controls without re-initializing. Tapping one emits
  `NotificationActions.seekForward` / `.seekBackward` on `actionEventStream`.
- `NotificationConfig.seekInterval` (default `10`) is **display-only on both platforms**: it
  sets the Android button labels and iOS's `skipForwardCommand.preferredIntervals`. Neither
  platform seeks the player itself — your `actionEventStream` handler must apply the same
  interval (`controller.seekForward(const Duration(seconds: 10))`), exactly as it must call
  `play()`/`pause()` itself for the other controls.
- `NotificationConfig.priority`, `.dismissible`, and `.customActions` are **Android only**
  (`MPRemoteCommandCenter` on iOS has no equivalent concept for any of the three — no priority/
  importance, no user-dismissible surface an app controls, and only a fixed set of semantic
  commands rather than arbitrary app-supplied actions). `priority` defaults to `null` ("no
  explicit priority requested"), which native resolves to `IMPORTANCE_LOW`/`PRIORITY_LOW`; set
  it explicitly (e.g. `NotificationPriority.high`) for a louder/heads-up notification.
  `customActions` render as additional buttons beyond the built-in
  play/pause/next/previous/stop/seek set and dispatch their `NotificationAction.id` back through
  `actionEventStream`, same as any other action.

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
- `PipConfig.actions` (**Android only**) renders each `PipAction` as an
  `android.app.RemoteAction` in the system PiP window, capped at 3 visible actions; tapping one
  delivers a `PipActionEvent` on `controller.player.pipActionStream`. AVKit exposes no API for
  custom PiP action buttons, so this has no iOS equivalent. `PipConfig.showPlaybackControls`
  gates whether `actions` renders at all on Android; on iOS it only partially maps to
  `AVPictureInPictureController.requiresLinearPlayback` (iOS 14+) — it hides skip-forward/
  skip-back and the scrub bar, but the system Play/Pause control can never be hidden.

```dart
controller.player.pipActionStream.listen((event) {
  // event.actionId matches a PipAction.id declared in PipConfig.actions (Android only)
});
```

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

`MediaConfig.castConfig` (a `CastConfig`) actually reaches native: `enabled`/`enableChromecast`
gate Chromecast setup on Android, `enabled`/`enableAirPlay` gate `AVPlayer
.allowsExternalPlayback` on iOS, `chromecastAppId` overrides the receiver app ID on Android
(falls back to Google's Default Media Receiver `CC1AD845` when unset), and `discoveryTimeout`
bounds Android Chromecast discovery. There is no DLNA support in this package.

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
- **No host-side call serialization is needed.** A fast A→B→A→B swipe produces overlapping
  `play`/`pause` on the same controller; each `MediaController` queues its own operations and
  runs them in submission order, so the losing call still takes effect rather than being
  rejected. Do not wrap these calls in a per-`playerId` promise chain of your own — see
  [Operation ordering](player-api.md#operation-ordering-serialization-queue).

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

### Gesture ownership

> **A gesture is handled by the topmost widget in the controls overlay that claims it, and only
> reaches the package's built-in tap detector when no overlay widget claimed it — regardless of
> whether the overlay is currently visible.**

`MediaPlayerWidget` keeps the controls overlay mounted and hit-testable at all times and stacks
its own transparent, full-surface tap detector **below** it. (The detector exists so taps are not
swallowed by the native platform view — `AndroidView`/`UiKitView` — and it keeps
`HitTestBehavior.opaque` for exactly that reason; opacity only affects what is *below* it.)

Before 0.3.1 the overlay and the detector were mutually exclusive: the overlay was not built at
all while `controller.controlsVisible` was `false`, and the opaque detector took over. Any gesture
a host declared inside `customControls` therefore stopped working the moment the overlay
auto-hid — a double-tap seek zone would silently become play/pause.

What this means when you write custom controls:

```dart
@override
Widget buildControls(BuildContext context, ControlsState state) {
  return Stack(
    children: [
      // Gesture zones: intentionally live in BOTH visibility states.
      // `translucent` claims the double tap but still lets a single tap reach
      // the package detector below, so tap-to-toggle keeps working.
      Positioned.fill(
        child: Row(children: [
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () => state.controller.seekBackward(),
            child: const SizedBox.expand(),
          )),
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () => state.controller.seekForward(),
            child: const SizedBox.expand(),
          )),
        ]),
      ),

      // Chrome: must be explicitly made inert while hidden — zero opacity
      // does NOT stop hit testing.
      IgnorePointer(
        ignoring: !state.isVisible,
        child: Opacity(
          opacity: state.animationValue,
          child: MyControlBar(controller: state.controller),
        ),
      ),
    ],
  );
}
```

Checklist:

- **You own visibility.** The package no longer fades or unmounts `customControls`; read
  `state.isVisible` / `state.animation` (or `controller.controlsVisible` directly). Returning
  `const SizedBox.shrink()` while hidden reproduces the old "unmounted" behaviour exactly.
- **Wrap non-gesture chrome in `IgnorePointer(ignoring: !state.isVisible)`.** Otherwise an
  invisible button still eats the tap that was supposed to reveal the controls.
- **Gate full-bleed scrims too.** A `Container` with a `color` is opaque to hit testing and will
  absorb every pointer; use `IgnorePointer` around it (the example app's `BrandedControls` does).
- **`enableBuiltInGestures: false`** opts out entirely: no detector is mounted, none of `onTap` /
  `onTapDown` / `onDoubleTap` / `onDoubleTapDown` / `onLongPress` / `onLongPressStart` are ever
  invoked by the package, and pointers your overlay does not claim go straight to the native
  platform view.

`onTap` / `onTapDown` / `onDoubleTap` / `onDoubleTapDown` fire consistently in both visibility
states: while the built-in overlay is visible, `MediaPlayerWidget` forwards them to
`MediaControls.onBackgroundTap` / `onBackgroundTapDown` / `onBackgroundDoubleTap` /
`onBackgroundDoubleTapDown`, so a tap on empty overlay space behaves exactly as it does when the
overlay is hidden — including `localPosition`, because the overlay's background detector fills
the same box as the tap detector beneath it. Buttons rendered on top of that background still
take precedence.

Long press is the one gesture that is **not** forwarded to the built-in overlay's background:
while the default `MediaControls` are visible they absorb it, so `onLongPress` /
`onLongPressStart` fire only while the overlay is hidden (or, with `customControls`, whenever
your overlay does not claim the press).

## Gesture callbacks

`MediaPlayerWidget` forwards three gestures, and each comes in two flavours: a bare
`VoidCallback` and a position-carrying counterpart.

| Bare | Position-carrying | Details type |
|---|---|---|
| `onTap` | `onTapDown` | `TapDownDetails` |
| `onDoubleTap` | `onDoubleTapDown` | `TapDownDetails` |
| `onLongPress` | `onLongPressStart` | `LongPressStartDetails` |

Four rules apply uniformly to all three gestures:

1. **Both may be supplied, and both fire**, in `GestureDetector`'s own order: the
   position-carrying variant first (on pointer-down / press recognition), the bare
   variant second (on gesture recognition).
2. **Supplying *either* variant means the host has taken over that gesture**, so the
   widget's built-in default for it does not run. The built-in defaults are: single tap
   toggles the controls overlay, double tap toggles play/pause. Long press has no
   built-in default.
3. **`details.localPosition` is relative to the player widget's own box** — the box
   `MediaPlayerWidget` occupies after any `aspectRatio` sizing, which is also the box
   the video surface, subtitle overlay and controls overlay fill. Divide by the
   widget's own width (`context.size?.width`, or a wrapping `LayoutBuilder`'s
   `constraints.maxWidth`), not the screen width. `details.globalPosition` is
   screen-relative and is what you want for positioning something in an `Overlay` or a
   route-level `Stack`.
4. **A callback runs only if no overlay widget claimed the gesture first** — see
   [Gesture ownership](#gesture-ownership) above. Overlay *visibility* is not what decides
   this. For tap and double tap the behaviour is identical in both states, `localPosition`
   included; long press is the one exception (the visible built-in overlay absorbs it).

### Direction-aware double-tap seek

The near-universal video-player convention — double-tap the left half to go back,
the right half to go forward:

```dart
LayoutBuilder(
  builder: (context, constraints) => MediaPlayerWidget(
    controller: controller,
    onDoubleTapDown: (details) {
      final isLeftHalf = details.localPosition.dx < constraints.maxWidth / 2;
      final target = isLeftHalf
          ? controller.position - const Duration(seconds: 10)
          : controller.position + const Duration(seconds: 10);
      controller.seekTo(target < Duration.zero ? Duration.zero : target);
    },
  ),
)
```

Because only `onDoubleTapDown` is supplied, the built-in double-tap-to-play/pause is
suppressed (rule 2); single tap still toggles the controls overlay because no tap
callback was supplied. To keep play/pause *and* add position logic, supply both:
`onDoubleTapDown` runs first with the position, then `onDoubleTap`.

This works with the **default** controls as well as with `customControls`, and whether the
overlay happens to be visible or hidden at the moment of the tap. When it is visible, the
overlay's own full-area background detector claims the pointer and re-emits it through
`MediaControls.onBackgroundDoubleTapDown`; that detector fills the entire overlay, which fills
the player's own box, so the `localPosition` your callback receives has the same origin and the
same denominator on both paths — one `constraints.maxWidth / 2` check is correct everywhere.

### `MediaControls` background callbacks

If you build directly with `MediaControls` (rather than letting `MediaPlayerWidget` construct
it), the same pairing is available on its background gesture layer:

| Bare | Position-carrying |
|---|---|
| `onBackgroundTap` | `onBackgroundTapDown` |
| `onBackgroundDoubleTap` | `onBackgroundDoubleTapDown` |

Rules 1 and 2 apply here too: both variants fire, position-carrying first, and supplying either
one suppresses the overlay's own default (a background tap restarting the auto-hide countdown).
Buttons rendered above the background always win the gesture first.

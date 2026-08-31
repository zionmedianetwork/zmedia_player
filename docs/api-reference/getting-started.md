# Getting Started

Install ZMedia Player, set up a player, and play your first media item.

## Install

```yaml
dependencies:
  zmedia_player:
    git:
      url: https://github.com/zionmedianetwork/zmedia_player.git
```

**Requirements:** Flutter `>=3.19.0` (verified on 3.44.3 / Dart 3.12), iOS 13.0+, Android minSdk 23.

## Platform setup

### Android

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

- Picture-in-Picture: API 26+ (relay `onPictureInPictureModeChanged` from your Activity).
- Notifications on Android 13+: request the `POST_NOTIFICATIONS` runtime permission.

### iOS

Minimum iOS 13.0. The plugin supports **Swift Package Manager and CocoaPods**. To build via SPM:

```bash
flutter config --enable-swift-package-manager
```

For background audio, add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

HTTPS media needs no App Transport Security changes at all. If you must serve
plain **HTTP** media, scope the exception to the specific domain(s) you
control rather than disabling ATS globally with `NSAllowsArbitraryLoads`
(see `docs/implementation/security.md`):

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>your-http-media-domain.example.com</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
    </dict>
  </dict>
</dict>
```

You must add this to your own `Info.plist` — the plugin does not read, add,
or modify `Info.plist` on your behalf.

## Your first player

```dart
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final MediaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      config: const MediaConfig(autoPlay: true),
    );
    _controller.load(const MediaItem(
      id: '1',
      title: 'Big Buck Bunny',
      url: 'https://www.w3schools.com/html/mov_bbb.mp4',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: MediaPlayerWidget(controller: _controller, showControls: true),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // always dispose — releases native resources
    super.dispose();
  }
}
```

## Sizing the player

`MediaPlayerWidget` sizes itself from its `aspectRatio` (defaulting to the video's natural
ratio, 16:9 when unknown), so it works inside any layout out of the box — the `AspectRatio`
above is optional, not required.

Pass `expandToFill: true` to fill the parent instead. That mode **requires a parent that hands
the widget a definite size** (bounded with a non-zero minimum in both axes): `Positioned.fill`
inside a `Stack`, `SizedBox.expand`, `Expanded`, or a `Scaffold` body. Given loose constraints
(a *non-positioned* `Stack` child) or an unbounded axis (an unbounded `Column`/`ListView`), the
widget falls back to an aspect-ratio-derived size rather than collapsing to zero, and reports a
debug-only `FlutterError` telling you to fix the constraints. See
[Fullscreen & display → Sizing](advanced-features.md#sizing-aspectratio-and-expandtofill).

> **Reusing the widget across players.** `MediaPlayerWidget` may be handed a
> different `MediaController` while it is mounted — no
> `key: ValueKey(controller.player.playerId)` is needed. A swap to a different
> `playerId` releases the outgoing player's native view and creates a new one
> for the incoming player; a swap to the same `playerId` keeps the existing
> surface. See
> [Advanced Features → Swapping the controller of a mounted `MediaPlayerWidget`](advanced-features.md#swapping-the-controller-of-a-mounted-mediaplayerwidget).

## Two ways to drive playback

- **`MediaController`** — a `ChangeNotifier` facade. Reactive getters (`isPlaying`,
  `position`, …), auto-hiding controls, and operation serialization: every call is queued
  per controller and runs in submission order, so interleaved `pause()`/`play()` never
  fails on timing (see
  [Operation ordering](player-api.md#operation-ordering-serialization-queue)). Use it for
  UI. Reach the lower layer via `controller.player`.
- **`MediaPlayer`** — the engine. Stream-first, singleton per `playerId`. Use it for custom
  integrations or when you want raw streams.

`MediaController.create()` calls `initialize()` for you. If you construct a `MediaPlayer`
directly, call `await player.initialize()` before loading.

## Reacting to state

```dart
// Option A: rebuild on any change (controller is a ChangeNotifier)
AnimatedBuilder(
  animation: _controller,
  builder: (context, _) => Text(_controller.isPlaying ? 'Playing' : 'Paused'),
);

// Option B: listen to a specific stream
_controller.player.positionStream.listen((pos) => print(pos));
```

## Next steps

- [Player API](player-api.md) — every method and getter
- [Models](models.md) — `MediaItem`, `Playlist`, `MediaConfig`, DRM, and more
- [Events & Streams](events.md) — all streams and callbacks
- [Advanced Features](advanced-features.md) — PiP, casting, notifications, caching
- [DRM](drm.md) · [Live Streaming](live-streaming.md) · [AirPlay & Chromecast](airplay.md)

// Gesture tests for MediaPlayerWidget.  Two related concerns share this file
// because they exercise the same widget through the same helpers:
//
// * Issue #83 — position-carrying gesture callbacks.  `onDoubleTap` carried no
//   tap position, so direction-aware double-tap seek was impossible through
//   the public API.  The widget now exposes three pairs:
//
//     onTap       (VoidCallback) / onTapDown        (GestureTapDownCallback)
//     onDoubleTap (VoidCallback) / onDoubleTapDown  (GestureTapDownCallback)
//     onLongPress (VoidCallback) / onLongPressStart (GestureLongPressStartCallback)
//
// * Issue #84 — gesture ownership between host `customControls` and the
//   package's own full-surface tap detector.
//
// The rules asserted below, in one place:
//
//   1. Both variants of a gesture may be supplied and BOTH fire, in
//      GestureDetector's own order: the position-carrying variant first, the
//      bare one second.
//   2. Supplying EITHER variant means the host owns the gesture, so the
//      package default (single tap -> toggleControls, double tap ->
//      togglePlayPause) is suppressed.
//   3. `details.localPosition` is measured from the top-left of the player's
//      own box -- the box MediaPlayerWidget occupies after any aspect-ratio
//      sizing, which is also the box the video surface / controls overlay
//      fill.  That is what a host needs for left-half / right-half zones;
//      `globalPosition` stays screen-relative.
//   4. A callback only runs if no widget in the controls overlay claimed the
//      gesture first.  The overlay is ALWAYS mounted and stacked ABOVE the
//      package detector; visibility is not what decides ownership.  The
//      built-in MediaControls are made non-hit-testable while hidden, and
//      while visible they forward background taps/double taps -- position
//      included -- straight back to the host callbacks, so tap and double tap
//      behave identically in both states.  `enableBuiltInGestures: false`
//      removes the detector (and the overlay's background forwarding)
//      entirely.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Shared channel mock
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

late List<MethodCall> _calls;

void _setUpMockChannel() {
  _calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    _calls.add(call);
    return null;
  });
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

bool get _playInvoked => _calls.any((c) => c.method == 'play');

// ---------------------------------------------------------------------------
// Host-supplied controls with a left-hand double-tap "seek zone", mirroring
// the setup described in issue #84.  Deliberately does NOT paint a scrim, so
// everything outside the zone falls through to the package detector below.
// ---------------------------------------------------------------------------

class _ZoneControls extends StatelessWidget {
  const _ZoneControls({
    required this.controller,
    required this.onZoneDoubleTap,
    required this.onZoneTap,
  });

  final MediaController controller;
  final VoidCallback onZoneDoubleTap;
  final VoidCallback onZoneTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 160,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onZoneTap,
            onDoubleTap: onZoneDoubleTap,
            child: const SizedBox.expand(
              key: Key('host-seek-zone'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Same idea, but using `HitTestBehavior.translucent` — the pattern the
/// example app's `BrandedControls` uses.  The zone claims the double tap while
/// still letting the pointer reach the package detector underneath, so a
/// single tap keeps toggling the overlay.
class _TranslucentZoneControls extends StatelessWidget {
  const _TranslucentZoneControls({required this.onZoneDoubleTap});

  final VoidCallback onZoneDoubleTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 160,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: onZoneDoubleTap,
            child: const SizedBox.expand(key: Key('host-seek-zone')),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps a 640x360 (exactly 16:9, so the implicit AspectRatio is a no-op and
/// the widget box == the player box) [MediaPlayerWidget] with the default
/// controls overlay, and returns its controller.
Future<MediaController> _pump(
  WidgetTester tester, {
  required String playerId,
  bool showControls = true,
  Widget Function(MediaController controller)? customControls,
  bool enableBuiltInGestures = true,
  VoidCallback? onTap,
  GestureTapDownCallback? onTapDown,
  VoidCallback? onDoubleTap,
  GestureTapDownCallback? onDoubleTapDown,
}) async {
  final controller = MediaController.create(playerId: playerId);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 640,
            height: 360,
            child: MediaPlayerWidget(
              controller: controller,
              showControls: showControls,
              customControls: customControls?.call(controller),
              enableBuiltInGestures: enableBuiltInGestures,
              onTap: onTap,
              onTapDown: onTapDown,
              onDoubleTap: onDoubleTap,
              onDoubleTapDown: onDoubleTapDown,
            ),
          ),
        ),
      ),
    ),
  );

  // Let initState's post-frame callback run (player initialize).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  return controller;
}

const Size _playerSize = Size(400, 300);

/// Pumps a bare [MediaPlayerWidget] of exactly [_playerSize] with
/// `showControls: false`, so the package tap detector is the ONLY
/// `GestureDetector` in the tree and can be located unambiguously.
Future<MediaController> _pumpPlayer(
  WidgetTester tester, {
  required String playerId,
  VoidCallback? onTap,
  GestureTapDownCallback? onTapDown,
  VoidCallback? onDoubleTap,
  GestureTapDownCallback? onDoubleTapDown,
  VoidCallback? onLongPress,
  GestureLongPressStartCallback? onLongPressStart,
  double? aspectRatio,
  Size size = _playerSize,
}) async {
  final controller = MediaController.create(playerId: playerId);

  final player = MediaPlayerWidget(
    controller: controller,
    showControls: false,
    // expandToFill avoids the implicit 16:9 AspectRatio wrapper so the player
    // box is exactly `size` -- unless a test explicitly asks for aspect-ratio
    // sizing, in which case the parent must leave the height unbounded so the
    // AspectRatio actually gets to size the widget (it no-ops under tight
    // constraints).
    expandToFill: aspectRatio == null,
    aspectRatio: aspectRatio,
    onTap: onTap,
    onTapDown: onTapDown,
    onDoubleTap: onDoubleTap,
    onDoubleTapDown: onDoubleTapDown,
    onLongPress: onLongPress,
    onLongPressStart: onLongPressStart,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: aspectRatio == null
              ? SizedBox(width: size.width, height: size.height, child: player)
              : SizedBox(width: size.width, child: player),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  // Controls are disabled entirely, so the tap-detector overlay must be the
  // only gesture detector present.
  expect(controller.controlsVisible, isFalse);
  expect(find.byType(GestureDetector), findsOneWidget,
      reason: 'The tap-detector overlay must be the only GestureDetector in '
          'the tree for these tests to be unambiguous');

  return controller;
}

Future<void> _cleanUp(MediaController controller, WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
  // Drain the controller's auto-hide / position timers.
  await tester.pump(const Duration(seconds: 5));
}

/// The GestureDetectors under test may declare both `onTap` and `onDoubleTap`,
/// so a single tap is only recognised once the double-tap window has elapsed.
Future<void> _singleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  // Between kDoubleTapMinTime (40ms) and kDoubleTapTimeout (300ms).
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Centre of the player, i.e. right on top of the built-in play/pause button.
Offset _playerCentre(WidgetTester tester) =>
    tester.getCenter(find.byType(MediaPlayerWidget));

/// A point inside the host-defined seek zone (left edge of the player).
Offset _zoneCentre(WidgetTester tester) =>
    tester.getCenter(find.byKey(const Key('host-seek-zone')));

/// A point on empty overlay background: vertically centred (so it clears the
/// top and bottom bars) but hard against the left edge (so it clears the
/// centre control row, which is horizontally centred and sized to its
/// children).  Used to prove that the *same pixels* behave identically whether
/// the overlay is visible or hidden.
Offset _backgroundPoint(WidgetTester tester) {
  final rect = tester.getRect(find.byType(MediaPlayerWidget));
  return Offset(rect.left + 24, rect.center.dy);
}

/// Top-left of the tap-detector overlay == top-left of the player's own box.
/// Only valid for trees pumped by [_pumpPlayer].
Offset _playerBoxTopLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(GestureDetector));

Size _playerBoxSize(WidgetTester tester) =>
    tester.getSize(find.byType(GestureDetector));

/// Reveals the built-in overlay and lets its fade-in settle.
Future<void> _showOverlay(
    MediaController controller, WidgetTester tester) async {
  controller.showControls();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Warm the static MediaPlayer cleanup timer so it is not flagged as
    // created-during-a-test.
    _setUpMockChannel();
    MediaController.create(playerId: 'warmup-gestures-static-timer').dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  // =========================================================================
  group('onDoubleTapDown — position reporting', () {
    testWidgets('fires with a left-half localPosition for a left-half tap',
        (tester) async {
      TapDownDetails? received;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dtd-left',
        onDoubleTapDown: (d) => received = d,
      );

      final topLeft = _playerBoxTopLeft(tester);
      final size = _playerBoxSize(tester);
      const localTap = Offset(80, 150); // left quarter
      await _doubleTapAt(tester, topLeft + localTap);

      expect(received, isNotNull,
          reason: 'onDoubleTapDown must fire on a double tap');
      expect(received!.localPosition.dx, closeTo(localTap.dx, 0.01));
      expect(received!.localPosition.dy, closeTo(localTap.dy, 0.01));
      expect(received!.localPosition.dx < size.width / 2, isTrue,
          reason: 'A tap at dx=80 of a 400pt-wide player is the left half — '
              'this is exactly the check a direction-aware seek performs');

      await _cleanUp(controller, tester);
    });

    testWidgets('fires with a right-half localPosition for a right-half tap',
        (tester) async {
      TapDownDetails? received;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dtd-right',
        onDoubleTapDown: (d) => received = d,
      );

      final topLeft = _playerBoxTopLeft(tester);
      final size = _playerBoxSize(tester);
      const localTap = Offset(320, 150); // right quarter
      await _doubleTapAt(tester, topLeft + localTap);

      expect(received, isNotNull);
      expect(received!.localPosition.dx, closeTo(localTap.dx, 0.01));
      expect(received!.localPosition.dy, closeTo(localTap.dy, 0.01));
      expect(received!.localPosition.dx >= size.width / 2, isTrue,
          reason: 'A tap at dx=320 of a 400pt-wide player is the right half');

      await _cleanUp(controller, tester);
    });

    testWidgets('globalPosition is screen-relative, localPosition is not',
        (tester) async {
      TapDownDetails? received;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dtd-coords',
        onDoubleTapDown: (d) => received = d,
      );

      final topLeft = _playerBoxTopLeft(tester);
      const localTap = Offset(120, 90);
      final globalTap = topLeft + localTap;
      await _doubleTapAt(tester, globalTap);

      expect(received, isNotNull);
      expect(received!.globalPosition.dx, closeTo(globalTap.dx, 0.01));
      expect(received!.globalPosition.dy, closeTo(globalTap.dy, 0.01));
      expect(received!.localPosition, isNot(equals(received!.globalPosition)),
          reason: 'The player is centered in the test window, so the two '
              'coordinate spaces must differ — proving localPosition really '
              'is box-relative and not just a copy of globalPosition');

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'localPosition is relative to the widget\'s own box under '
        'aspect-ratio sizing', (tester) async {
      TapDownDetails? received;
      // 400pt-wide slot with unbounded height and a 2:1 aspect ratio -> the
      // widget sizes itself to 400x200, and the tap-detector overlay fills
      // exactly that box.
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dtd-aspect',
        size: const Size(400, 400),
        aspectRatio: 2.0,
        onDoubleTapDown: (d) => received = d,
      );

      expect(_playerBoxSize(tester), const Size(400, 200));
      expect(_playerBoxSize(tester),
          tester.getSize(find.byType(MediaPlayerWidget)),
          reason: 'The tap-detector box must coincide with the widget box, so '
              'a host can safely use `context.size` / LayoutBuilder '
              'constraints as the denominator for half-screen zones');
      expect(_playerBoxTopLeft(tester),
          tester.getTopLeft(find.byType(MediaPlayerWidget)));

      final boxTopLeft = _playerBoxTopLeft(tester);
      const localTap = Offset(50, 40);
      await _doubleTapAt(tester, boxTopLeft + localTap);

      expect(received, isNotNull);
      expect(received!.localPosition.dx, closeTo(localTap.dx, 0.01));
      expect(received!.localPosition.dy, closeTo(localTap.dy, 0.01),
          reason: 'localPosition must be measured from the player box origin, '
              'not the enclosing 400x400 slot');

      await _cleanUp(controller, tester);
    });
  });

  // =========================================================================
  group('double tap — callback precedence', () {
    testWidgets('bare onDoubleTap alone still fires (source compatibility)',
        (tester) async {
      var fired = 0;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dt-bare',
        onDoubleTap: () => fired++,
      );

      await _doubleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));

      expect(fired, 1,
          reason: 'The pre-existing VoidCallback API must be '
              'unchanged for hosts that never migrate');
      expect(_playInvoked, isFalse,
          reason: 'A host onDoubleTap suppresses the built-in play/pause');

      await _cleanUp(controller, tester);
    });

    testWidgets('both variants fire, onDoubleTapDown first', (tester) async {
      final order = <String>[];
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dt-both',
        onDoubleTapDown: (_) => order.add('down'),
        onDoubleTap: () => order.add('tap'),
      );

      await _doubleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));

      expect(order, ['down', 'tap'],
          reason: 'Documented rule 1: both fire, position-carrying first');

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'onDoubleTapDown alone suppresses the built-in play/pause default',
        (tester) async {
      var fired = 0;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dt-suppress',
        onDoubleTapDown: (_) => fired++,
      );

      await _doubleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));

      expect(fired, 1);
      expect(_playInvoked, isFalse,
          reason: 'Documented rule 2: supplying EITHER variant means the host '
              'owns the gesture, so _handleDoubleTap must not also run');

      await _cleanUp(controller, tester);
    });

    testWidgets('with no host callback the built-in play/pause default fires',
        (tester) async {
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-dt-default',
      );

      await _doubleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(_playInvoked, isTrue,
          reason: 'Default double-tap behaviour (togglePlayPause -> play) must '
              'be untouched when the host supplies neither variant');

      await _cleanUp(controller, tester);
    });
  });

  // =========================================================================
  group('single tap — onTapDown / onTap', () {
    testWidgets('onTapDown fires with a box-relative localPosition',
        (tester) async {
      TapDownDetails? received;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-td-pos',
        onTapDown: (d) => received = d,
      );

      final topLeft = _playerBoxTopLeft(tester);
      const localTap = Offset(300, 200);
      await _singleTapAt(tester, topLeft + localTap);

      expect(received, isNotNull);
      expect(received!.localPosition.dx, closeTo(localTap.dx, 0.01));
      expect(received!.localPosition.dy, closeTo(localTap.dy, 0.01));

      await _cleanUp(controller, tester);
    });

    testWidgets('bare onTap alone still fires (source compatibility)',
        (tester) async {
      var fired = 0;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-tap-bare',
        onTap: () => fired++,
      );

      await _singleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));

      expect(fired, 1);
      expect(controller.controlsVisible, isFalse,
          reason: 'A host onTap suppresses the built-in toggleControls');

      await _cleanUp(controller, tester);
    });

    testWidgets('both variants fire, onTapDown first', (tester) async {
      final order = <String>[];
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-tap-both',
        onTapDown: (_) => order.add('down'),
        onTap: () => order.add('tap'),
      );

      await _singleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));

      expect(order, ['down', 'tap']);

      await _cleanUp(controller, tester);
    });

    testWidgets('onTapDown alone suppresses the built-in toggleControls',
        (tester) async {
      var fired = 0;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-tap-suppress',
        onTapDown: (_) => fired++,
      );

      await _singleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));

      expect(fired, 1);
      expect(controller.controlsVisible, isFalse,
          reason: 'Documented rule 2 applied to the tap gesture');

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'with no host callback the built-in toggleControls default fires',
        (tester) async {
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-tap-default',
      );

      await _singleTapAt(
          tester, tester.getCenter(find.byType(GestureDetector)));

      expect(controller.controlsVisible, isTrue,
          reason: 'Default single-tap behaviour must be untouched');

      await _cleanUp(controller, tester);
    });
  });

  // =========================================================================
  group('long press — onLongPressStart / onLongPress', () {
    testWidgets('onLongPressStart fires with a box-relative localPosition',
        (tester) async {
      LongPressStartDetails? received;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-lp-pos',
        onLongPressStart: (d) => received = d,
      );

      final topLeft = _playerBoxTopLeft(tester);
      const localPress = Offset(340, 60);
      await tester.longPressAt(topLeft + localPress);
      await tester.pump(const Duration(milliseconds: 100));

      expect(received, isNotNull);
      expect(received!.localPosition.dx, closeTo(localPress.dx, 0.01));
      expect(received!.localPosition.dy, closeTo(localPress.dy, 0.01));
      expect(received!.globalPosition.dx,
          closeTo((topLeft + localPress).dx, 0.01));

      await _cleanUp(controller, tester);
    });

    testWidgets('bare onLongPress alone still fires (source compatibility)',
        (tester) async {
      var fired = 0;
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-lp-bare',
        onLongPress: () => fired++,
      );

      await tester.longPressAt(tester.getCenter(find.byType(GestureDetector)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(fired, 1);

      await _cleanUp(controller, tester);
    });

    testWidgets('both variants fire, onLongPressStart first', (tester) async {
      final order = <String>[];
      final controller = await _pumpPlayer(
        tester,
        playerId: 'gest-lp-both',
        onLongPressStart: (_) => order.add('start'),
        onLongPress: () => order.add('press'),
      );

      await tester.longPressAt(tester.getCenter(find.byType(GestureDetector)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(order, ['start', 'press']);

      await _cleanUp(controller, tester);
    });
  });
  // -------------------------------------------------------------------------
  group('#84 — customControls gestures survive the overlay auto-hiding', () {
    testWidgets(
        'host double-tap zone fires while the overlay is HIDDEN '
        '(the exact reported regression)', (tester) async {
      var zoneDoubleTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-hidden-zone',
        customControls: (c) => _ZoneControls(
          controller: c,
          onZoneTap: () {},
          onZoneDoubleTap: () => zoneDoubleTaps++,
        ),
      );

      // Overlay starts hidden — this is the state that used to break.
      expect(controller.controlsVisible, isFalse);

      await _doubleTapAt(tester, _zoneCentre(tester));

      expect(
        zoneDoubleTaps,
        1,
        reason: 'the host zone must own the double tap even when the overlay '
            'is hidden; before the fix the package detector swallowed it',
      );
      // The package's built-in double tap (togglePlayPause) must not also have
      // run, and the tap must not have toggled the overlay.
      expect(controller.controlsVisible, isFalse);

      await _cleanUp(controller, tester);
    });

    testWidgets('host double-tap zone fires while the overlay is VISIBLE',
        (tester) async {
      var zoneDoubleTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-visible-zone',
        customControls: (c) => _ZoneControls(
          controller: c,
          onZoneTap: () {},
          onZoneDoubleTap: () => zoneDoubleTaps++,
        ),
      );

      controller.showControls();
      await tester.pump();
      expect(controller.controlsVisible, isTrue);

      await _doubleTapAt(tester, _zoneCentre(tester));

      expect(zoneDoubleTaps, 1);

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'the same gesture on the same pixels behaves identically in both '
        'visibility states', (tester) async {
      var zoneDoubleTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-both-states',
        customControls: (c) => _ZoneControls(
          controller: c,
          onZoneTap: () {},
          onZoneDoubleTap: () => zoneDoubleTaps++,
        ),
      );

      final zone = _zoneCentre(tester);

      // Hidden
      expect(controller.controlsVisible, isFalse);
      await _doubleTapAt(tester, zone);
      expect(zoneDoubleTaps, 1);

      // Visible
      controller.showControls();
      await tester.pump();
      await _doubleTapAt(tester, zone);
      expect(zoneDoubleTaps, 2);

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'a tap OUTSIDE the host zone still reaches the built-in detector and '
        'reveals the overlay', (tester) async {
      var zoneTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-outside-zone',
        customControls: (c) => _ZoneControls(
          controller: c,
          onZoneTap: () => zoneTaps++,
          onZoneDoubleTap: () {},
        ),
      );

      expect(controller.controlsVisible, isFalse);

      await _singleTapAt(tester, _playerCentre(tester));

      expect(zoneTaps, 0, reason: 'the centre is outside the host zone');
      expect(
        controller.controlsVisible,
        isTrue,
        reason: 'unclaimed pointers must still fall through to the package '
            'detector below the overlay',
      );

      await _cleanUp(controller, tester);
    });
  });

  // -------------------------------------------------------------------------
  group('translucent host zones (the example app\'s pattern)', () {
    testWidgets(
        'double tap goes to the zone, single tap falls through to the package '
        '— in both visibility states', (tester) async {
      var zoneDoubleTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-translucent-zone',
        customControls: (c) => _TranslucentZoneControls(
          onZoneDoubleTap: () => zoneDoubleTaps++,
        ),
      );

      final zone = _zoneCentre(tester);

      // Hidden: double tap is claimed by the zone, not by the package.
      expect(controller.controlsVisible, isFalse);
      await _doubleTapAt(tester, zone);
      expect(zoneDoubleTaps, 1);
      expect(controller.controlsVisible, isFalse);

      // Hidden: a single tap on the very same pixels still reaches the
      // package detector below the translucent zone.
      await _singleTapAt(tester, zone);
      expect(zoneDoubleTaps, 1);
      expect(controller.controlsVisible, isTrue);

      // Visible: identical outcome for the double tap.
      await _doubleTapAt(tester, zone);
      expect(zoneDoubleTaps, 2);

      await _cleanUp(controller, tester);
    });
  });

  // -------------------------------------------------------------------------
  group('package control variants track MediaController.controlsVisible', () {
    testWidgets(
        'MaterialMediaControls used as customControls starts hidden and is '
        'revealed by a tap', (tester) async {
      final controller =
          MediaController.create(playerId: 'g84-material-visibility');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 360,
                child: MediaPlayerWidget(
                  controller: controller,
                  customControls: MaterialMediaControls(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The overlay is mounted, but its chrome must not be showing: it now
      // mirrors controller.controlsVisible instead of its own local flag,
      // which used to default to "visible".
      expect(controller.controlsVisible, isFalse);
      expect(find.byIcon(Icons.play_arrow), findsNothing);

      // Its opaque root owns the tap and routes it through the controller.
      await _singleTapAt(tester, _playerCentre(tester));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.controlsVisible, isTrue);

      await _cleanUp(controller, tester);
    });
  });

  // -------------------------------------------------------------------------
  group('built-in controls stay inert while hidden', () {
    testWidgets(
        'a tap on the (hidden) play/pause button position toggles the overlay '
        'instead of activating the button', (tester) async {
      final controller = await _pump(tester, playerId: 'g84-builtin-hidden');

      expect(controller.controlsVisible, isFalse);
      // The built-in controls are mounted but gated.
      expect(find.byType(MediaControls), findsOneWidget);

      final ignorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(MediaControls),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignorePointer.ignoring, isTrue);

      // Centre of the player == centre of the built-in play/pause button.
      await _singleTapAt(tester, _playerCentre(tester));

      expect(
        controller.controlsVisible,
        isTrue,
        reason: 'the tap must have reached the detector, not the hidden button',
      );

      await _cleanUp(controller, tester);
    });

    testWidgets('hidden built-in controls become hit-testable once shown',
        (tester) async {
      final controller = await _pump(tester, playerId: 'g84-builtin-shown');

      controller.showControls();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final ignorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(MediaControls),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignorePointer.ignoring, isFalse);

      await _cleanUp(controller, tester);
    });

    testWidgets('hidden built-in controls are not exposed to screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = await _pump(tester, playerId: 'g84-builtin-semantics');

      expect(controller.controlsVisible, isFalse);
      expect(
        find.bySemanticsLabel('Play'),
        findsNothing,
        reason: 'hidden controls must stay out of the semantics tree, exactly '
            'as when they were not built at all',
      );

      controller.showControls();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.bySemanticsLabel('Play'), findsWidgets);

      await _cleanUp(controller, tester);
      semantics.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('tap over the video area still toggles the overlay', () {
    testWidgets('hidden → tap → visible (default controls)', (tester) async {
      final controller = await _pump(tester, playerId: 'g84-toggle-default');

      expect(controller.controlsVisible, isFalse);
      await _singleTapAt(tester, _playerCentre(tester));
      expect(controller.controlsVisible, isTrue);

      await _cleanUp(controller, tester);
    });

    testWidgets('works with showControls: false too', (tester) async {
      final controller = await _pump(
        tester,
        playerId: 'g84-toggle-no-controls',
        showControls: false,
      );

      expect(find.byType(MediaControls), findsNothing);
      await _singleTapAt(tester, _playerCentre(tester));
      expect(controller.controlsVisible, isTrue);

      await _cleanUp(controller, tester);
    });
  });

  // -------------------------------------------------------------------------
  group('onTap / onDoubleTap fire identically in both visibility states', () {
    testWidgets('onTap fires when hidden and when visible', (tester) async {
      var taps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-ontap-both',
        onTap: () => taps++,
      );

      final point = _backgroundPoint(tester);

      // Hidden
      expect(controller.controlsVisible, isFalse);
      await _singleTapAt(tester, point);
      expect(taps, 1);
      // A host-supplied onTap replaces the toggle behaviour.
      expect(controller.controlsVisible, isFalse);

      // Visible
      controller.showControls();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _singleTapAt(tester, point);
      expect(
        taps,
        2,
        reason: 'the visible built-in overlay must forward background taps to '
            'the same host callback',
      );

      await _cleanUp(controller, tester);
    });

    testWidgets('onDoubleTap fires when hidden and when visible',
        (tester) async {
      var doubleTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-ondoubletap-both',
        onDoubleTap: () => doubleTaps++,
      );

      final point = _backgroundPoint(tester);

      // Hidden
      await _doubleTapAt(tester, point);
      expect(doubleTaps, 1);

      // Visible
      controller.showControls();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _doubleTapAt(tester, point);
      expect(doubleTaps, 2);

      await _cleanUp(controller, tester);
    });
  });

  // -------------------------------------------------------------------------
  group('enableBuiltInGestures opt-out', () {
    test('defaults to true', () {
      final controller = MediaController.create(playerId: 'g84-default-flag');
      final widget = MediaPlayerWidget(controller: controller);
      expect(widget.enableBuiltInGestures, isTrue);
      controller.dispose();
    });

    testWidgets('false → the package neither toggles controls nor calls onTap',
        (tester) async {
      var taps = 0;
      var doubleTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-optout',
        showControls: false,
        enableBuiltInGestures: false,
        onTap: () => taps++,
        onDoubleTap: () => doubleTaps++,
      );

      await _singleTapAt(tester, _playerCentre(tester));
      await _doubleTapAt(tester, _playerCentre(tester));

      expect(taps, 0);
      expect(doubleTaps, 0);
      expect(controller.controlsVisible, isFalse);

      await _cleanUp(controller, tester);
    });

    testWidgets('false → host customControls gestures still work',
        (tester) async {
      var zoneDoubleTaps = 0;
      final controller = await _pump(
        tester,
        playerId: 'g84-optout-zone',
        enableBuiltInGestures: false,
        customControls: (c) => _ZoneControls(
          controller: c,
          onZoneTap: () {},
          onZoneDoubleTap: () => zoneDoubleTaps++,
        ),
      );

      await _doubleTapAt(tester, _zoneCentre(tester));
      expect(zoneDoubleTaps, 1);
      expect(controller.controlsVisible, isFalse);

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'false → the built-in overlay no longer runs its own double-tap '
        'handling', (tester) async {
      final controller = await _pump(
        tester,
        playerId: 'g84-optout-builtin',
        enableBuiltInGestures: false,
      );

      controller.showControls();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final controls = tester.widget<MediaControls>(find.byType(MediaControls));
      expect(controls.onBackgroundTap, isNull);
      expect(controls.onBackgroundDoubleTap, isNull);

      await _cleanUp(controller, tester);
    });
  });
  // =========================================================================
  // #83 x #84: after the overlay became always-mounted and topmost, the
  // position-carrying callbacks had to survive the OVERLAY path too, not just
  // the tap-detector path -- otherwise direction-aware double-tap seek stayed
  // impossible with the default controls.  MediaControls.onBackgroundTapDown /
  // onBackgroundDoubleTapDown close that gap.
  group('position-carrying callbacks through the visible built-in overlay', () {
    testWidgets(
        'onDoubleTapDown reports the SAME box-relative localPosition whether '
        'the overlay is hidden or visible', (tester) async {
      final received = <Offset>[];
      final controller = await _pump(
        tester,
        playerId: 'g83-overlay-dtd-parity',
        onDoubleTapDown: (d) => received.add(d.localPosition),
      );

      final rect = tester.getRect(find.byType(MediaPlayerWidget));
      final point = _backgroundPoint(tester);
      final expectedLocal = point - rect.topLeft;

      // Hidden: IgnorePointer lets the pointer through to the package
      // detector below the overlay.
      expect(controller.controlsVisible, isFalse);
      await _doubleTapAt(tester, point);
      expect(received, hasLength(1),
          reason: 'onDoubleTapDown must fire while the overlay is hidden');
      expect(received[0].dx, closeTo(expectedLocal.dx, 0.01));
      expect(received[0].dy, closeTo(expectedLocal.dy, 0.01));

      // Visible: the overlay's own background detector claims the pointer and
      // forwards it through onBackgroundDoubleTapDown.
      await _showOverlay(controller, tester);
      await _doubleTapAt(tester, point);
      expect(received, hasLength(2),
          reason: 'the visible built-in overlay must forward the '
              'position-carrying double tap to the same host callback');
      expect(received[1], received[0],
          reason: 'the overlay background detector fills the same box as the '
              'tap detector below it, so localPosition must be identical -- '
              'a host can use one denominator for both states');
      expect(received[1].dx, closeTo(expectedLocal.dx, 0.01));
      expect(received[1].dy, closeTo(expectedLocal.dy, 0.01));

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'left-half vs right-half zones resolve correctly over the VISIBLE '
        'overlay (the actual goal of issue #83)', (tester) async {
      final sides = <String>[];
      final controller = await _pump(
        tester,
        playerId: 'g83-overlay-dtd-zones',
        onDoubleTapDown: (d) =>
            sides.add(d.localPosition.dx < 640 / 2 ? 'left' : 'right'),
      );

      await _showOverlay(controller, tester);
      final rect = tester.getRect(find.byType(MediaPlayerWidget));

      await _doubleTapAt(tester, Offset(rect.left + 24, rect.center.dy));
      await _doubleTapAt(tester, Offset(rect.right - 24, rect.center.dy));

      expect(sides, ['left', 'right'],
          reason: 'localPosition over the visible overlay must be measured '
              'from the player box origin, so half-screen seek zones work');

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'onTapDown fires over the visible overlay with a '
        'box-relative localPosition', (tester) async {
      final received = <Offset>[];
      final controller = await _pump(
        tester,
        playerId: 'g83-overlay-td',
        onTapDown: (d) => received.add(d.localPosition),
      );

      final rect = tester.getRect(find.byType(MediaPlayerWidget));
      final point = _backgroundPoint(tester);
      final expectedLocal = point - rect.topLeft;

      await _singleTapAt(tester, point);
      expect(received, hasLength(1));

      await _showOverlay(controller, tester);
      await _singleTapAt(tester, point);
      expect(received, hasLength(2));
      expect(received[1], received[0]);
      expect(received[1].dx, closeTo(expectedLocal.dx, 0.01));
      expect(received[1].dy, closeTo(expectedLocal.dy, 0.01));

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'onDoubleTapDown alone suppresses the built-in play/pause on the '
        'overlay path too', (tester) async {
      var fired = 0;
      final controller = await _pump(
        tester,
        playerId: 'g83-overlay-suppress',
        onDoubleTapDown: (_) => fired++,
      );

      await _showOverlay(controller, tester);
      _calls.clear();
      await _doubleTapAt(tester, _backgroundPoint(tester));

      expect(fired, 1);
      expect(_playInvoked, isFalse,
          reason: 'rule 2 must hold identically on the overlay path: '
              'onBackgroundDoubleTap is left null so _handleDoubleTap cannot '
              'also run');

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'the overlay receives the position-carrying callbacks and '
        'mirrors the suppression rule', (tester) async {
      final controller = await _pump(
        tester,
        playerId: 'g83-overlay-wiring',
        onTapDown: (_) {},
        onDoubleTapDown: (_) {},
      );
      await _showOverlay(controller, tester);

      final controls = tester.widget<MediaControls>(find.byType(MediaControls));
      expect(controls.onBackgroundTapDown, isNotNull);
      expect(controls.onBackgroundDoubleTapDown, isNotNull);
      expect(controls.onBackgroundTap, isNull);
      expect(controls.onBackgroundDoubleTap, isNull,
          reason: 'supplying onDoubleTapDown alone means the host owns the '
              'gesture, so the package default must not be forwarded either');

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'with no host callback the overlay still gets the built-in '
        'play/pause default', (tester) async {
      final controller = await _pump(tester, playerId: 'g83-overlay-default');
      await _showOverlay(controller, tester);

      final controls = tester.widget<MediaControls>(find.byType(MediaControls));
      expect(controls.onBackgroundTapDown, isNull);
      expect(controls.onBackgroundDoubleTapDown, isNull);
      expect(controls.onBackgroundDoubleTap, isNotNull);

      _calls.clear();
      await _doubleTapAt(tester, _backgroundPoint(tester));
      expect(_playInvoked, isTrue);

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'enableBuiltInGestures: false nulls the position-carrying forwarding '
        'too', (tester) async {
      final controller = await _pump(
        tester,
        playerId: 'g83-overlay-optout',
        enableBuiltInGestures: false,
        onTapDown: (_) {},
        onDoubleTapDown: (_) {},
      );
      await _showOverlay(controller, tester);

      final controls = tester.widget<MediaControls>(find.byType(MediaControls));
      expect(controls.onBackgroundTapDown, isNull);
      expect(controls.onBackgroundDoubleTapDown, isNull);
      expect(controls.onBackgroundTap, isNull);
      expect(controls.onBackgroundDoubleTap, isNull);

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'onDoubleTapDown fires with position through customControls that do '
        'not claim the gesture', (tester) async {
      TapDownDetails? received;
      final controller = await _pump(
        tester,
        playerId: 'g83-custom-dtd',
        customControls: (c) => _ZoneControls(
          controller: c,
          onZoneTap: () {},
          onZoneDoubleTap: () {},
        ),
        onDoubleTapDown: (d) => received = d,
      );

      final rect = tester.getRect(find.byType(MediaPlayerWidget));
      // Well clear of the 160pt-wide host zone on the left.
      final point = Offset(rect.left + 500, rect.center.dy);
      await _doubleTapAt(tester, point);

      expect(received, isNotNull);
      expect(received!.localPosition.dx, closeTo(500, 0.01));
      expect(received!.localPosition.dy, closeTo(rect.height / 2, 0.01));

      await _cleanUp(controller, tester);
    });
  });
}

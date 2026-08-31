// Regression + contract tests for MediaPlayerWidget gesture ownership.
//
// Issue #84: the package's own full-surface tap detector was only mounted
// while `controller.controlsVisible == false`, and the controls overlay was
// only *built* while it was `true`.  The two were mutually exclusive, so any
// gesture a host declared inside `customControls` silently stopped working the
// moment the overlay auto-hid — the opaque detector took over and, e.g., a
// double tap that used to seek suddenly toggled play/pause instead.
//
// The fix:
//   * the controls overlay is always mounted (built-in controls are gated with
//     ExcludeSemantics + IgnorePointer + zero opacity while hidden, so they
//     stay exactly as inert as when they were unmounted);
//   * the built-in tap detector is stacked BELOW the overlay, so it only sees
//     pointers no overlay widget claimed;
//   * `enableBuiltInGestures: false` removes the detector entirely.
//
// Gesture-ownership rule under test: a gesture is handled by the topmost
// widget in the controls overlay that claims it, and only reaches the built-in
// tap detector when no overlay widget claimed it — regardless of whether the
// overlay is currently visible.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Shared channel mock
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

void _setUpMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async => null);
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

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

Future<MediaController> _pump(
  WidgetTester tester, {
  required String playerId,
  bool showControls = true,
  Widget Function(MediaController controller)? customControls,
  bool enableBuiltInGestures = true,
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
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
              onDoubleTap: onDoubleTap,
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

Future<void> _cleanUp(MediaController controller, WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
}

/// The GestureDetectors under test declare both `onTap` and `onDoubleTap`, so
/// a single tap is only recognised once the double-tap window has elapsed.
Future<void> _singleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
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
}

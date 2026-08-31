// Regression tests for issue #85:
//
//   expandToFill: true has no size floor — collapses to zero (black screen,
//   no exception) under loose constraints.
//
// `MediaPlayerWidget._buildPlayerContent` deliberately skips the AspectRatio
// wrapper when `expandToFill: true` (that is the point of the flag), which
// left the widget with no intrinsic size whatsoever. Wrapped in a host-side
// Stack as a NON-POSITIONED child — the normal way to overlay chrome above a
// player — the whole subtree laid out at Size(0, 0): video gone, controls
// gone, audio still playing, and *no exception of any kind*, because a
// zero-size layout throws nothing.
//
// Verified against the pre-fix implementation: the "loose constraints
// (non-positioned Stack child)" test below measured Size(0.0, 0.0) exactly as
// reported. After the fix it measures 800x450 (the 16:9 size floor).
//
// The tests assert real geometry via `tester.getSize`, and additionally pin
// the debug-only diagnostic (emitted through FlutterError.reportError) that
// turns the previously silent failure into a loud one.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Shared channel helpers (mirrors the other widget test files)
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

void _installHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async => null);
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// The default test surface (800x600 logical pixels).
const Size _surface = Size(800, 600);

/// 16:9 is the fallback aspect ratio used by `_getVideoAspectRatio()` when the
/// video's natural ratio is unknown (which is always the case in a headless
/// test, since no native view is ever created).
const double _kAspect = 16 / 9;

/// Pumps [child] inside a MaterialApp/Scaffold, capturing every
/// [FlutterErrorDetails] reported while the frames are produced.
///
/// The diagnostic emitted by the size-floor fallback goes through
/// `FlutterError.reportError`, which flutter_test would otherwise turn into a
/// test failure; capturing it lets each test assert on it explicitly (and, for
/// the "unchanged behaviour" tests, assert that nothing at all was reported).
Future<List<FlutterErrorDetails>> _pumpCapturingErrors(
  WidgetTester tester,
  Widget child, {
  int extraFrames = 3,
}) async {
  final captured = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = captured.add;
  try {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );
    for (var i = 0; i < extraFrames; i++) {
      await tester.pump();
    }
  } finally {
    FlutterError.onError = previousOnError;
  }
  return captured;
}

Future<void> _teardown(WidgetTester tester, MediaController controller) async {
  // Every MediaPlayerWidget mount schedules a didChangeDependencies -> 50ms ->
  // refreshVideoSurface -> 100ms delayed setState cascade. Drain it while the
  // tree is still mounted, then again after unmounting, so flutter_test's
  // "no pending Timer" invariant holds.
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 300));
  controller.dispose();
  await tester.pump();
  _resetHandler();
}

/// Matches the size-floor diagnostic.
Matcher _isExpandToFillDiagnostic() => isA<FlutterError>().having(
      (e) => e.toString(),
      'message',
      allOf(
        contains('expandToFill'),
        contains('Positioned.fill'),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Warm up MediaPlayer's static cleanup timer before any testWidgets run so
    // it is not flagged as "new" during a test (mirrors other widget tests).
    _installHandler();
    MediaController.create(playerId: 'warmup-expand-to-fill-static-timer')
        .dispose();
    _resetHandler();
  });

  setUp(_installHandler);
  tearDown(_resetHandler);

  // -------------------------------------------------------------------------
  // (a) Tight constraints: intended usage, must be byte-for-byte unchanged.
  // -------------------------------------------------------------------------
  group('expandToFill: true with definite constraints (unchanged)', () {
    testWidgets('Positioned.fill in a Stack fills the parent exactly',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-tight-stack');

      final errors = await _pumpCapturingErrors(
        tester,
        SizedBox(
          width: _surface.width,
          height: _surface.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                  expandToFill: true,
                ),
              ),
            ],
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MediaPlayerWidget)),
        _surface,
        reason: 'Positioned.fill gives tight constraints — expandToFill must '
            'still fill them exactly, with no aspect-ratio fallback',
      );
      expect(errors, isEmpty,
          reason: 'No diagnostic may be reported for the intended usage');

      await _teardown(tester, controller);
    });

    testWidgets('SizedBox.expand fills the parent exactly', (tester) async {
      final controller = MediaController.create(playerId: 'etf-tight-expand');

      final errors = await _pumpCapturingErrors(
        tester,
        SizedBox(
          width: 640,
          height: 480,
          child: SizedBox.expand(
            child: MediaPlayerWidget(
              controller: controller,
              showControls: false,
              expandToFill: true,
            ),
          ),
        ),
      );

      expect(
          tester.getSize(find.byType(MediaPlayerWidget)), const Size(640, 480));
      expect(errors, isEmpty);

      await _teardown(tester, controller);
    });

    testWidgets(
        'bounded constraints with a non-zero minimum still fill '
        '(ConstrainedBox minWidth/minHeight == maxWidth/maxHeight)',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-min-nonzero');

      final errors = await _pumpCapturingErrors(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 300,
              maxWidth: 300,
              minHeight: 500,
              maxHeight: 500,
            ),
            child: MediaPlayerWidget(
              controller: controller,
              showControls: false,
              expandToFill: true,
            ),
          ),
        ),
      );

      expect(
          tester.getSize(find.byType(MediaPlayerWidget)), const Size(300, 500));
      expect(errors, isEmpty);

      await _teardown(tester, controller);
    });
  });

  // -------------------------------------------------------------------------
  // (b) Loose constraints: the reported case. Was Size(0, 0).
  // -------------------------------------------------------------------------
  group('expandToFill: true with collapsible constraints (size floor)', () {
    testWidgets(
        'non-positioned Stack child gets a 16:9 size floor instead of '
        'collapsing to zero (issue #85 repro)', (tester) async {
      final controller = MediaController.create(playerId: 'etf-loose-stack');

      final errors = await _pumpCapturingErrors(
        tester,
        Center(
          child: SizedBox(
            width: _surface.width,
            height: _surface.height,
            // A non-positioned Stack child receives BoxConstraints.loose —
            // this is the exact host-side layout reported in issue #85.
            child: Stack(
              children: [
                MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                  expandToFill: true,
                ),
              ],
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(MediaPlayerWidget));
      expect(size.width, greaterThan(0.0));
      expect(size.height, greaterThan(0.0));
      expect(
        size,
        Size(_surface.width, _surface.width / _kAspect),
        reason: 'The bounded axis is filled and the other is derived from the '
            'video aspect ratio (16:9 fallback) => 800x450, not Size(0, 0)',
      );

      expect(errors, hasLength(1),
          reason: 'The debug diagnostic must be reported exactly once, not '
              'once per frame');
      expect(errors.single.exception, _isExpandToFillDiagnostic());
      expect(errors.single.library, 'zmedia_player');

      await _teardown(tester, controller);
    });

    testWidgets('loose constraints taller than 16:9 clamp to the bounded width',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-loose-tall');

      await _pumpCapturingErrors(
        tester,
        Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: Stack(
              children: [
                MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                  expandToFill: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MediaPlayerWidget)),
        Size(400, 400 / _kAspect),
        reason: '400 / (16/9) = 225 fits inside the 600 max height',
      );

      await _teardown(tester, controller);
    });

    testWidgets(
        'loose constraints wider than 16:9 re-derive from the bounded height',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-loose-wide');

      await _pumpCapturingErrors(
        tester,
        Center(
          child: SizedBox(
            width: 800,
            height: 200,
            child: Stack(
              children: [
                MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                  expandToFill: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MediaPlayerWidget)),
        Size(200 * _kAspect, 200),
        reason: '800 / (16/9) = 450 would overflow the 200 max height, so the '
            'size is re-derived from the height instead',
      );

      await _teardown(tester, controller);
    });

    // -----------------------------------------------------------------------
    // (c) Unbounded in one axis.
    // -----------------------------------------------------------------------
    testWidgets('unbounded height (Column child) gets a non-zero size',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-unbounded-h');

      final errors = await _pumpCapturingErrors(
        tester,
        SizedBox(
          width: _surface.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaPlayerWidget(
                controller: controller,
                showControls: false,
                expandToFill: true,
              ),
            ],
          ),
        ),
      );

      final size = tester.getSize(find.byType(MediaPlayerWidget));
      expect(size.height, greaterThan(0.0));
      expect(
        size,
        Size(_surface.width, _surface.width / _kAspect),
        reason: 'The bounded axis (width) plus the aspect ratio defines the '
            'unbounded axis (height)',
      );
      expect(errors, hasLength(1));
      expect(errors.single.exception, _isExpandToFillDiagnostic());

      await _teardown(tester, controller);
    });

    testWidgets('unbounded width (Row child) derives width from the height',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-unbounded-w');

      await _pumpCapturingErrors(
        tester,
        SizedBox(
          height: 270,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaPlayerWidget(
                controller: controller,
                showControls: false,
                expandToFill: true,
              ),
            ],
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MediaPlayerWidget)),
        Size(270 * _kAspect, 270),
      );

      await _teardown(tester, controller);
    });

    testWidgets('unbounded in both axes falls back to the screen width',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-unbounded-both');

      await _pumpCapturingErrors(
        tester,
        UnconstrainedBox(
          child: MediaPlayerWidget(
            controller: controller,
            showControls: false,
            expandToFill: true,
          ),
        ),
      );

      final size = tester.getSize(find.byType(MediaPlayerWidget));
      expect(size.width, greaterThan(0.0));
      expect(size.height, greaterThan(0.0));
      expect(
        size,
        Size(_surface.width, _surface.width / _kAspect),
        reason: 'Nothing in the constraints to derive from, so the MediaQuery '
            'screen width (800) is used',
      );

      await _teardown(tester, controller);
    });

    testWidgets(
        'the diagnostic is reported at most once even across many frames',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-no-spam');

      final errors = await _pumpCapturingErrors(
        tester,
        Center(
          child: SizedBox(
            width: _surface.width,
            height: _surface.height,
            child: Stack(
              children: [
                MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                  expandToFill: true,
                ),
              ],
            ),
          ),
        ),
        extraFrames: 12,
      );

      expect(errors, hasLength(1));

      await _teardown(tester, controller);
    });
  });

  // -------------------------------------------------------------------------
  // (d) expandToFill: false — untouched.
  // -------------------------------------------------------------------------
  group('expandToFill: false (unchanged)', () {
    testWidgets('loose constraints still use the natural aspect ratio',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-false-loose');

      final errors = await _pumpCapturingErrors(
        tester,
        Center(
          child: SizedBox(
            width: _surface.width,
            height: _surface.height,
            child: Stack(
              children: [
                MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MediaPlayerWidget)),
        Size(_surface.width, _surface.width / _kAspect),
      );
      expect(errors, isEmpty,
          reason: 'expandToFill: false is immune and must never warn');

      await _teardown(tester, controller);
    });

    testWidgets('tight constraints still fill them (AspectRatio honours tight)',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-false-tight');

      final errors = await _pumpCapturingErrors(
        tester,
        SizedBox(
          width: _surface.width,
          height: _surface.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                ),
              ),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.byType(MediaPlayerWidget)), _surface);
      expect(errors, isEmpty);

      await _teardown(tester, controller);
    });
  });

  // -------------------------------------------------------------------------
  // (e) Explicit aspectRatio always wins — untouched.
  // -------------------------------------------------------------------------
  group('explicit aspectRatio (unchanged)', () {
    testWidgets('aspectRatio wins over expandToFill under loose constraints',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-explicit-ar');

      final errors = await _pumpCapturingErrors(
        tester,
        Center(
          child: SizedBox(
            width: _surface.width,
            height: _surface.height,
            child: Stack(
              children: [
                MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                  expandToFill: true,
                  aspectRatio: 2.0,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MediaPlayerWidget)),
        const Size(800, 400),
        reason: 'An explicit aspectRatio: 2.0 must be used verbatim, not the '
            '16:9 fallback',
      );
      expect(errors, isEmpty,
          reason: 'An explicit aspectRatio already provides a size floor');

      await _teardown(tester, controller);
    });

    testWidgets('aspectRatio with expandToFill: false is unchanged',
        (tester) async {
      final controller = MediaController.create(playerId: 'etf-explicit-ar-2');

      final errors = await _pumpCapturingErrors(
        tester,
        Center(
          child: SizedBox(
            width: _surface.width,
            height: _surface.height,
            child: Stack(
              children: [
                MediaPlayerWidget(
                  controller: controller,
                  showControls: false,
                  aspectRatio: 4 / 3,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
          tester.getSize(find.byType(MediaPlayerWidget)), const Size(800, 600));
      expect(errors, isEmpty);

      await _teardown(tester, controller);
    });
  });
}

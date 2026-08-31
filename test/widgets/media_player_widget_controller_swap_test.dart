// Regression tests for issue #80: MediaPlayerWidget kept the old native view
// when the controller's playerId changed.
//
// Before the fix, `didUpdateWidget` rewired the ChangeNotifier subscription on
// a controller swap and then called `_refreshVideoSurface()`, which early-outs
// whenever a live native view already exists ("don't churn the surface on
// rotation").  That early-out did not distinguish "same player, new layout"
// from "different player entirely", so swapping a *live* controller for one
// wrapping a different `playerId` left the widget driving the outgoing
// player's orphaned surface.  Consumers had to key the widget on
// `controller.player.playerId` to force a remount.
//
// The fix compares `oldWidget.controller.player.playerId` against
// `widget.controller.player.playerId` in `didUpdateWidget` and, when they
// differ, runs a real teardown (`_cleanupNativeView`, the same path `dispose`
// takes) followed by a post-frame recreate bound to the new player.  The
// same-player early-out is preserved verbatim.
//
// How these tests observe the native view
// ---------------------------------------
// `defaultTargetPlatform` is `TargetPlatform.android` under flutter_test, so
// `MediaPlayerWidget` builds the real `PlatformViewLink` /
// `initExpensiveAndroidView` host.  That talks to the framework's
// `flutter/platform_views` channel, which we mock: every host creation emits a
// `create` call (whose `params` blob carries the `playerId` the surface is
// bound to) and every teardown emits a `dispose` call.  Those two calls are
// the ground truth for "was the native view recreated / released", so the
// tests assert on them directly rather than on private widget state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Channel helpers
// ---------------------------------------------------------------------------

const _pluginChannel = MethodChannel('zmedia_player');

late List<MethodCall> _pluginCalls;
late List<MethodCall> _platformViewCalls;

void _installChannels() {
  _pluginCalls = <MethodCall>[];
  _platformViewCalls = <MethodCall>[];

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pluginChannel, (MethodCall call) async {
    _pluginCalls.add(call);
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform_views,
          (MethodCall call) async {
    _platformViewCalls.add(call);
    return null;
  });
}

void _resetChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pluginChannel, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform_views, null);
}

/// Every `create` on `flutter/platform_views` for our view type, in order.
List<MethodCall> get _createCalls =>
    _platformViewCalls.where((c) => c.method == 'create').toList();

/// Every `dispose` on `flutter/platform_views`, in order.
List<MethodCall> get _disposeCalls =>
    _platformViewCalls.where((c) => c.method == 'dispose').toList();

/// Decodes the `creationParams` blob attached to a platform-view `create`
/// call.  `MediaPlayerWidget` puts `{playerId, boxFit}` in there, so this is
/// how we learn which player a freshly-created native surface is bound to.
Map<Object?, Object?> _creationParamsOf(MethodCall createCall) {
  final raw = (createCall.arguments as Map)['params'] as Uint8List;
  final decoded = const StandardMessageCodec().decodeMessage(
    ByteData.view(raw.buffer, raw.offsetInBytes, raw.lengthInBytes),
  );
  return decoded! as Map<Object?, Object?>;
}

/// The `playerId` each created native surface was bound to, in creation order.
List<String> get _createdSurfacePlayerIds => _createCalls
    .map((c) => _creationParamsOf(c)['playerId'] as String)
    .toList();

MediaItem _item(String id) => MediaItem(
      id: id,
      title: 'Item $id',
      url: 'https://example.com/$id.m3u8',
    );

/// Pumps long enough for the whole native-view creation cascade to finish:
/// `_createNativeView`'s 100ms settle delay, plus the 150ms/200ms
/// post-creation rebuilds in `_onPlatformViewCreated`, plus
/// `didChangeDependencies`' 50ms + 100ms refresh.
Future<void> _settleNativeView(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ---------------------------------------------------------------------------
// Harness: a host whose controller (and box size) can be changed in place,
// exercising MediaPlayerWidget.didUpdateWidget rather than a remount.
// ---------------------------------------------------------------------------

class _SwapHost extends StatefulWidget {
  final MediaController initialController;

  const _SwapHost({required this.initialController});

  @override
  State<_SwapHost> createState() => _SwapHostState();
}

class _SwapHostState extends State<_SwapHost> {
  late MediaController _controller = widget.initialController;
  double _width = 640;
  double _height = 360;

  void swapController(MediaController next) =>
      setState(() => _controller = next);

  void resize(double width, double height) => setState(() {
        _width = width;
        _height = height;
      });

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _width,
            height: _height,
            child: MediaPlayerWidget(
              controller: _controller,
              showControls: false,
            ),
          ),
        ),
      ),
    );
  }
}

_SwapHostState _host(WidgetTester tester) =>
    tester.state<_SwapHostState>(find.byType(_SwapHost));

/// Mounts [_SwapHost] with [controller] and waits until its native view exists.
Future<void> _pumpHost(WidgetTester tester, MediaController controller) async {
  await tester.pumpWidget(_SwapHost(initialController: controller));
  await tester.pump();
  await tester.idle();
  // Platform-view `dispose` messages are dispatched asynchronously, so a
  // previous test's teardown can land in this test's capture list.  The mount's
  // own `create` cannot have happened yet (`_createNativeView` waits 100ms
  // before building the host), so clearing here only drops the leftovers.
  _platformViewCalls.clear();
  await _settleNativeView(tester);
}

Future<void> _teardown(
  WidgetTester tester,
  List<MediaController> controllers,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Let every pending delayed setState / refresh timer fire as a no-op while
  // unmounted; flutter_test asserts no Timer is pending at test end.
  await tester.pump(const Duration(milliseconds: 600));
  await tester.idle();
  for (final c in controllers) {
    c.dispose();
  }
  await tester.pump();
  await tester.idle();
}

// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Warm up MediaPlayer's static cleanup timer outside any testWidgets run
    // so it is not reported as a leaked timer inside one.
    _installChannels();
    MediaController.create(playerId: 'warmup-swap-static-timer').dispose();
    _resetChannels();
  });

  setUp(_installChannels);
  tearDown(_resetChannels);

  // -------------------------------------------------------------------------
  group('MediaPlayerWidget — controller swap with a DIFFERENT playerId', () {
    testWidgets(
        'tears the outgoing native view down and creates a new one bound to '
        'the incoming player', (tester) async {
      final first = MediaController.create(playerId: 'swap-old');
      await first.initialize();
      await first.load(_item('episode-1'));

      await _pumpHost(tester, first);

      expect(_createdSurfacePlayerIds, ['swap-old'],
          reason: 'the initial mount must create exactly one native surface, '
              'bound to the first controller\'s player');
      expect(_disposeCalls, isEmpty);

      // --- swap in a controller over a DIFFERENT player -------------------
      final second = MediaController.create(playerId: 'swap-new');
      await second.initialize();
      await second.load(_item('episode-2'));

      _host(tester).swapController(second);
      await _settleNativeView(tester);

      expect(_disposeCalls, hasLength(1),
          reason: 'the outgoing player\'s native view must actually be '
              'released, not left orphaned');
      expect(_createdSurfacePlayerIds, ['swap-old', 'swap-new'],
          reason: 'a fresh native surface bound to the NEW playerId must be '
              'created after the swap');

      // The disposed host id must be the one created for the outgoing player.
      expect((_disposeCalls.single.arguments as Map)['id'],
          (_createCalls.first.arguments as Map)['id']);
      expect((_createCalls.last.arguments as Map)['id'],
          isNot((_createCalls.first.arguments as Map)['id']),
          reason: 'the new surface must be a new platform-view host, not the '
              'reused old one (creationParams are one-shot, so a reused '
              'element would keep the old playerId)');

      await _teardown(tester, [first, second]);
    });

    testWidgets('re-binds the plugin channel to the new playerId',
        (tester) async {
      final first = MediaController.create(playerId: 'swap-ch-old');
      await first.initialize();
      await first.load(_item('a'));

      await _pumpHost(tester, first);

      final second = MediaController.create(playerId: 'swap-ch-new');
      await second.initialize();
      await second.load(_item('b'));

      _pluginCalls.clear();
      _host(tester).swapController(second);
      await _settleNativeView(tester);

      // `_onPlatformViewCreated` re-asserts surface ownership for whichever
      // player the new host belongs to.
      final reclaimIds = _pluginCalls
          .where((c) => c.method == 'reclaimVideoSurface')
          .map((c) => (c.arguments as Map)['playerId'])
          .toSet();
      expect(reclaimIds, contains('swap-ch-new'),
          reason: 'the new native view must be claimed by the new player');
      expect(reclaimIds, isNot(contains('swap-ch-old')),
          reason: 'no post-swap traffic may target the outgoing player');

      await _teardown(tester, [first, second]);
    });

    testWidgets(
        'moves the listener: the outgoing controller no longer drives the '
        'widget, the incoming one does', (tester) async {
      final first = MediaController.create(playerId: 'swap-listen-old');
      await first.initialize();
      await first.load(_item('old-1'));

      await _pumpHost(tester, first);
      expect(_createdSurfacePlayerIds, ['swap-listen-old']);

      // Swap to a controller that has NOT loaded anything yet, so no native
      // view can be created until it does.
      final second = MediaController.create(playerId: 'swap-listen-new');
      await second.initialize();

      _host(tester).swapController(second);
      await _settleNativeView(tester);

      expect(_disposeCalls, hasLength(1),
          reason: 'the outgoing surface is released even when the incoming '
              'controller has no media yet');
      expect(_createdSurfacePlayerIds, ['swap-listen-old'],
          reason: 'no surface may be created for a controller with no media');

      // The OLD controller notifying must no longer reach the widget.
      await first.load(_item('old-2'));
      await _settleNativeView(tester);
      expect(_createdSurfacePlayerIds, ['swap-listen-old'],
          reason: 'the widget must have stopped listening to the outgoing '
              'controller; loading on it must not resurrect its surface');

      // The NEW controller notifying must reach the widget.
      await second.load(_item('new-1'));
      await _settleNativeView(tester);
      expect(_createdSurfacePlayerIds, ['swap-listen-old', 'swap-listen-new'],
          reason: 'the widget must now be listening to the incoming '
              'controller and build its surface when it loads media');

      await _teardown(tester, [first, second]);
    });

    testWidgets(
        'handles an outgoing controller that was already disposed before the '
        'swap', (tester) async {
      // The realistic teardown-then-swap ordering: a consumer disposes the
      // controller it is retiring and hands the widget a fresh one.  The swap
      // path must only touch the outgoing player through members that survive
      // disposal (`playerId` is a plain final field, `removeListener` is
      // documented as safe post-dispose), so this must not throw.
      final first = MediaController.create(playerId: 'swap-dead-old');
      await first.initialize();
      await first.load(_item('a'));

      await _pumpHost(tester, first);
      expect(_createdSurfacePlayerIds, ['swap-dead-old']);

      final second = MediaController.create(playerId: 'swap-dead-new');
      await second.initialize();
      await second.load(_item('b'));

      first.dispose();
      _host(tester).swapController(second);
      await _settleNativeView(tester);

      expect(tester.takeException(), isNull,
          reason: 'swapping away from an already-disposed controller must not '
              'throw');
      expect(_disposeCalls, hasLength(1),
          reason: 'the retired surface is still released');
      expect(_createdSurfacePlayerIds, ['swap-dead-old', 'swap-dead-new'],
          reason: 'the incoming player still gets a fresh surface');

      await _teardown(tester, [second]);
    });
  });

  // -------------------------------------------------------------------------
  group('MediaPlayerWidget — controller swap with the SAME playerId', () {
    testWidgets(
        'does NOT churn the surface when a second controller over the same '
        'player is swapped in', (tester) async {
      final first = MediaController.create(playerId: 'same-player');
      await first.initialize();
      await first.load(_item('a'));

      await _pumpHost(tester, first);
      expect(_createdSurfacePlayerIds, ['same-player']);

      // A second MediaController over the SAME MediaPlayer instance.
      final second = MediaController.create(playerId: 'same-player');
      expect(identical(first.player, second.player), isTrue,
          reason: 'MediaPlayer is a singleton per playerId, so this is the '
              'same-player / different-controller case');
      expect(identical(first, second), isFalse);

      _host(tester).swapController(second);
      await _settleNativeView(tester);

      expect(_disposeCalls, isEmpty,
          reason: 'the surface already belongs to the correct player, so it '
              'must be kept alive (no black flash)');
      expect(_createdSurfacePlayerIds, ['same-player'],
          reason: 'no additional native view may be created');

      // The new controller is still wired up: it drives the widget.
      expect(find.byType(MediaPlayerWidget), findsOneWidget);

      await _teardown(tester, [first, second]);
    });
  });

  // -------------------------------------------------------------------------
  group('MediaPlayerWidget — relayout / rotation must not churn the surface',
      () {
    testWidgets('resizing the widget with the same controller keeps the view',
        (tester) async {
      final controller = MediaController.create(playerId: 'relayout');
      await controller.initialize();
      await controller.load(_item('a'));

      await _pumpHost(tester, controller);
      expect(_createdSurfacePlayerIds, ['relayout']);

      // Landscape-ish → portrait-ish, the exact case the `_refreshVideoSurface`
      // early-out exists to protect.
      _host(tester).resize(360, 640);
      await _settleNativeView(tester);
      _host(tester).resize(800, 450);
      await _settleNativeView(tester);

      expect(_disposeCalls, isEmpty,
          reason: 'relayout must never destroy the native surface');
      expect(_createdSurfacePlayerIds, ['relayout'],
          reason: 'relayout must never recreate the native surface');

      await _teardown(tester, [controller]);
    });

    testWidgets(
        'a plain parent rebuild with the same controller keeps the view',
        (tester) async {
      final controller = MediaController.create(playerId: 'rebuild');
      await controller.initialize();
      await controller.load(_item('a'));

      await _pumpHost(tester, controller);
      expect(_createdSurfacePlayerIds, ['rebuild']);

      for (var i = 0; i < 3; i++) {
        _host(tester).rebuild();
        await tester.pump();
      }
      await _settleNativeView(tester);

      expect(_disposeCalls, isEmpty);
      expect(_createdSurfacePlayerIds, ['rebuild']);

      await _teardown(tester, [controller]);
    });

    testWidgets('a device orientation change keeps the view', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);

      final controller = MediaController.create(playerId: 'orientation');
      await controller.initialize();
      await controller.load(_item('a'));

      tester.view.physicalSize = const Size(1200, 2400);
      await _pumpHost(tester, controller);
      expect(_createdSurfacePlayerIds, ['orientation']);

      // Rotate to landscape.
      tester.view.physicalSize = const Size(2400, 1200);
      await _settleNativeView(tester);
      // ...and back.
      tester.view.physicalSize = const Size(1200, 2400);
      await _settleNativeView(tester);

      expect(_disposeCalls, isEmpty,
          reason: 'orientation change must not destroy the native surface');
      expect(_createdSurfacePlayerIds, ['orientation']);

      await _teardown(tester, [controller]);
    });
  });
}

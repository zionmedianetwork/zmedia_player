// Issue #135: ErrorOverlay must never show raw platform/exception text, must
// word a 403 as retryable, and must not show the developer "Error Code:" chip
// unless the host opts in. MediaPlayerWidget must feed it the typed exception.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');
const _raw = "The operation couldn't be completed. "
    '(CoreMediaErrorDomain error -12643.)';

Future<void> _pumpOverlay(
  WidgetTester tester,
  Object? error, {
  bool? showErrorCode,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: showErrorCode == null
          ? ErrorOverlay(error: error, animated: false)
          : ErrorOverlay(
              error: error,
              animated: false,
              showErrorCode: showErrorCode,
            ),
    ),
  ));
  await tester.pump();
}

Future<void> _inject(String method, Map<String, dynamic> args) async {
  final data =
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (ByteData? _) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ErrorOverlay copy', () {
    testWidgets('unmatched string -> generic message, raw text absent',
        (tester) async {
      await _pumpOverlay(tester, _raw);
      expect(find.text(ErrorOverlay.genericMessage), findsOneWidget);
      expect(find.textContaining('CoreMediaErrorDomain'), findsNothing);
      expect(find.textContaining('-12643'), findsNothing);
    });

    testWidgets('arbitrary object and null -> generic', (tester) async {
      await _pumpOverlay(tester, StateError('boom internals'));
      expect(find.text(ErrorOverlay.genericMessage), findsOneWidget);
      expect(find.textContaining('boom internals'), findsNothing);

      await _pumpOverlay(tester, null);
      expect(find.text(ErrorOverlay.genericMessage), findsOneWidget);
    });

    testWidgets('typed exception categories map to specific copy',
        (tester) async {
      await _pumpOverlay(tester, const NetworkException('x', isOffline: true));
      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.text('Please check your internet connection and try again.'),
          findsOneWidget);

      await _pumpOverlay(tester, const DrmException('x', isLicenseError: true));
      expect(find.text('Content License Error'), findsOneWidget);

      await _pumpOverlay(tester, const PlaybackException('x'));
      expect(find.text('Playback Failed'), findsOneWidget);

      await _pumpOverlay(
          tester, const MediaLoadException('x', statusCode: 404));
      expect(find.text('Failed to Load Media'), findsOneWidget);
      expect(
        find.text(
            'The requested media could not be found. It may have been moved or deleted.'),
        findsOneWidget,
      );
    });

    testWidgets('403 is worded as retryable (string and typed)',
        (tester) async {
      await _pumpOverlay(tester, 'HTTP 403 Forbidden');
      expect(find.text(ErrorOverlay.retryableAccessMessage), findsOneWidget);

      await _pumpOverlay(
          tester, const MediaLoadException('x', statusCode: 403));
      expect(find.text(ErrorOverlay.retryableAccessMessage), findsOneWidget);
      expect(find.textContaining("don't have permission"), findsNothing);
    });
  });

  group('ErrorOverlay showErrorCode', () {
    const error = MediaLoadException('x', statusCode: 404);

    testWidgets('defaults to false: no chip', (tester) async {
      expect(const ErrorOverlay(error: error).showErrorCode, isFalse);
      await _pumpOverlay(tester, error);
      expect(find.textContaining('Error Code'), findsNothing);
    });

    testWidgets('opt-in shows chip', (tester) async {
      await _pumpOverlay(tester, error, showErrorCode: true);
      expect(find.text('Error Code: HTTP 404'), findsOneWidget);
    });
  });

  group('MediaPlayerWidget default error overlay', () {
    setUpAll(() {
      // Warm the static MediaPlayer cleanup timer so it is not flagged as
      // created-during-a-test.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => null);
      MediaController.create(playerId: 'warmup-error-overlay').dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    Future<MediaController> pumpFailed(
        WidgetTester tester, String id, Map<String, dynamic> error) async {
      final controller = MediaController.create(playerId: id);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: MediaPlayerWidget(controller: controller),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await controller.load(const MediaItem(
        id: 'i',
        url: 'https://example.com/v.m3u8',
        title: 't',
      ));
      await _inject('onError', {'playerId': id, ...error});
      await tester.pump(const Duration(seconds: 1));
      return controller;
    }

    Future<void> unmount(WidgetTester tester, MediaController c) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(const Duration(seconds: 60));
    }

    testWidgets('uses typed error and hides the error-code chip',
        (tester) async {
      final c = await pumpFailed(tester, 'p135-typed', {
        'error': _raw,
        'category': 'HTTP',
        'httpStatusCode': 403,
      });
      expect(find.byType(ErrorOverlay), findsOneWidget);
      expect(find.text(ErrorOverlay.retryableAccessMessage), findsOneWidget);
      expect(find.textContaining('Error Code'), findsNothing);
      expect(find.textContaining('CoreMediaErrorDomain'), findsNothing);
      await unmount(tester, c);
    });

    testWidgets('uncategorized failure shows generic copy', (tester) async {
      final c = await pumpFailed(tester, 'p135-generic', {'error': _raw});
      expect(find.byType(ErrorOverlay), findsOneWidget);
      expect(find.textContaining('CoreMediaErrorDomain'), findsNothing);
      await unmount(tester, c);
    });
  });
}

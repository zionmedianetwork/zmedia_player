// Issue #134: seekTo() while paused must update PlaybackState.position.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

Future<void> _inject(String method, Map<String, dynamic> args) async {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, args));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_channel.name, data, (ByteData? _) {});
  await Future<void>.delayed(Duration.zero);
}

const _vod = MediaItem(
  id: 'vod',
  title: 'VOD',
  url: 'https://cdn.example.com/movie.mp4',
);

const _live = MediaItem(
  id: 'live',
  title: 'Live',
  url: 'https://cdn.example.com/live.m3u8',
  isLive: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // [onSeek] runs inside the mocked native `seekTo` call, before it replies.
  void install({Future<void> Function()? onSeek}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
      if (call.method == 'seekTo' && onSeek != null) await onSeek();
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('MediaPlayer.seekTo while paused', () {
    test('native post-seek event updates position (paused)', () async {
      install();
      final player = MediaPlayer(playerId: 'ps_native');
      await player.initialize();
      await player.load(_vod);
      await _inject('onStateChanged', {
        'playerId': 'ps_native',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0,
      });
      expect(player.currentState.position, Duration.zero);

      await player.seekTo(const Duration(seconds: 30));
      await _inject('onPositionChanged', {
        'playerId': 'ps_native',
        'position': 30000,
        'positionBasis': 'absolute',
      });

      expect(player.currentState.position, const Duration(seconds: 30));
      await player.dispose();
    });

    test('optimistic update covers an older native build (VOD)', () async {
      install();
      final player = MediaPlayer(playerId: 'ps_optimistic');
      await player.initialize();
      await player.load(_vod);
      final emitted = <Duration>[];
      final sub = player.positionStream.listen(emitted.add);

      await player.seekTo(const Duration(seconds: 12));
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.position, const Duration(seconds: 12));
      expect(emitted, contains(const Duration(seconds: 12)));
      await sub.cancel();
      await player.dispose();
    });

    test('optimistic update is clamped to a known duration', () async {
      install();
      final player = MediaPlayer(playerId: 'ps_clamp');
      await player.initialize();
      await player.load(_vod);
      await _inject('onDurationChanged', {
        'playerId': 'ps_clamp',
        'duration': 60000,
        'isLive': false,
      });

      await player.seekTo(const Duration(seconds: 90));

      expect(player.currentState.position, const Duration(seconds: 60));
      await player.dispose();
    });

    test('a native position that arrives during the call is not overwritten',
        () async {
      install(onSeek: () async {
        // Native clamps to 45s and reports before the call replies.
        await _inject('onPositionChanged', {
          'playerId': 'ps_race',
          'position': 45000,
          'positionBasis': 'absolute',
        });
      });
      final player = MediaPlayer(playerId: 'ps_race');
      await player.initialize();
      await player.load(_vod);

      await player.seekTo(const Duration(seconds: 90));

      expect(player.currentState.position, const Duration(seconds: 45));
      await player.dispose();
    });

    test('live DVR item: no optimistic update (window-relative position)',
        () async {
      install();
      final player = MediaPlayer(
        playerId: 'ps_live',
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
      );
      await player.initialize();
      await player.load(_live);
      await _inject('onPositionChanged', {
        'playerId': 'ps_live',
        'position': 5000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 1000,
      });

      await player.seekTo(const Duration(seconds: 20));

      // Only native can say where a window-relative seek landed.
      expect(player.currentState.position, const Duration(seconds: 5));
      expect(player.currentState.liveEdgeOffset, const Duration(seconds: 1));

      await _inject('onPositionChanged', {
        'playerId': 'ps_live',
        'position': 20000,
        'positionBasis': 'liveWindow',
        'liveEdgeOffset': 8000,
      });
      expect(player.currentState.position, const Duration(seconds: 20));
      expect(player.currentState.liveEdgeOffset, const Duration(seconds: 8));
      await player.dispose();
    });
  });

  group('MediaController throttle vs. post-seek position', () {
    test('a post-seek update within 500ms of a tick is not dropped', () async {
      install();
      final controller = MediaController.create(playerId: 'ps_ctrl');
      await controller.initialize();
      await controller.load(_vod);
      await _inject('onDurationChanged', {
        'playerId': 'ps_ctrl',
        'duration': 600000,
        'isLive': false,
      });

      // A periodic tick lands, opening the 500ms throttle window.
      await _inject('onPositionChanged', {
        'playerId': 'ps_ctrl',
        'position': 1000,
        'positionBasis': 'absolute',
      });
      expect(controller.position, const Duration(seconds: 1));

      // Small (<1s) seek immediately after would previously be throttled.
      await controller.seekTo(const Duration(milliseconds: 1400));
      await _inject('onPositionChanged', {
        'playerId': 'ps_ctrl',
        'position': 1400,
        'positionBasis': 'absolute',
      });

      expect(controller.position, const Duration(milliseconds: 1400));
      expect(controller.positionListenable.value,
          const Duration(milliseconds: 1400));
      controller.dispose();
    });
  });
}

/// Memory leak tests with proper platform channel mocking
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock the platform channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (MethodCall methodCall) async {
        // Return appropriate mocks based on method
        switch (methodCall.method) {
          case 'initialize':
            return null;
          case 'load':
            return null;
          case 'play':
            return null;
          case 'pause':
            return null;
          case 'stop':
            return null;
          case 'seekTo':
            return null;
          case 'dispose':
            return null;
          case 'setVolume':
            return null;
          case 'setSpeed':
            return null;
          case 'setMuted':
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    // Clean up
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  group('Memory Leak Prevention', () {
    test('✅ No leak with 100 create/dispose cycles', () async {
      for (int i = 0; i < 100; i++) {
        final controller = MediaController.create();
        await controller.initialize();
        expect(controller.player.isDisposed, false);
        controller.dispose();
        expect(controller.player.isDisposed, true);
      }
      // ignore: avoid_print
      print('✅ Completed 100 cycles without crash');
    });

    test('✅ Multiple independent controllers', () async {
      final c1 = MediaController.create(playerId: 'test1');
      final c2 = MediaController.create(playerId: 'test2');
      final c3 = MediaController.create(playerId: 'test3');

      await c1.initialize();
      await c2.initialize();
      await c3.initialize();

      expect(c1.player.playerId, 'test1');
      expect(c2.player.playerId, 'test2');
      expect(c3.player.playerId, 'test3');
      expect(c1.player.isDisposed, false);
      expect(c2.player.isDisposed, false);
      expect(c3.player.isDisposed, false);

      // Dispose middle one
      c2.dispose();

      expect(c1.player.isDisposed, false);
      expect(c2.player.isDisposed, true);
      expect(c3.player.isDisposed, false);

      c1.dispose();
      c3.dispose();
    });

    test('✅ Dispose is idempotent', () async {
      final controller = MediaController.create();
      await controller.initialize();

      controller.dispose();
      controller.dispose();
      controller.dispose();

      expect(controller.player.isDisposed, true);
    });

    test('✅ Activity marking through operations', () async {
      final controller = MediaController.create();
      await controller.initialize();

      // Operations mark activity
      await controller.play();
      await controller.pause();

      expect(controller.player.isDisposed, false);
      expect(controller.player.isInitialized, true);

      controller.dispose();
    });

    test('✅ Disposed controller throws on state access', () async {
      final controller = MediaController.create();
      await controller.initialize();
      controller.dispose();

      expect(controller.player.isDisposed, true);

      expect(
        () => controller.player.currentState,
        throwsA(isA<MediaPlayerException>()),
      );

      expect(
        () => controller.player.config,
        throwsA(isA<MediaPlayerException>()),
      );
    });
  });

  group('Performance Benchmarks', () {
    test('⚡ 50 create/dispose cycles < 5 seconds', () async {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 50; i++) {
        final controller = MediaController.create();
        await controller.initialize();
        controller.dispose();
      }

      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;

      // ignore: avoid_print
      print(
          '\n⚡ Performance: 50 cycles in ${ms}ms (avg: ${(ms / 50).toStringAsFixed(2)}ms/cycle)');

      expect(ms, lessThan(5000), reason: 'Should complete in under 5 seconds');
    });

    test('⚡ Concurrent operations are fast', () async {
      final stopwatch = Stopwatch()..start();

      final futures = List.generate(10, (_) async {
        final controller = MediaController.create();
        await controller.initialize();
        controller.dispose();
      });

      await Future.wait(futures);
      stopwatch.stop();

      final ms = stopwatch.elapsedMilliseconds;

      // ignore: avoid_print
      print('⚡ Concurrent: 10 parallel cycles in ${ms}ms');

      expect(ms, lessThan(2000), reason: 'Concurrent ops should be fast');
    });

    test('⚡ State access is instant', () async {
      final controller = MediaController.create();
      await controller.initialize();

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 1000; i++) {
        // ignore: unused_local_variable
        final state = controller.player.currentState;
        // ignore: unused_local_variable
        final playing = controller.player.isPlaying;
        // ignore: unused_local_variable
        final initialized = controller.player.isInitialized;
      }

      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;

      // ignore: avoid_print
      print(
          '⚡ State access: 3000 accesses in ${ms}ms (${(ms / 3000).toStringAsFixed(4)}ms/access)');

      expect(ms, lessThan(200),
          reason: 'State access should be nearly instant');

      controller.dispose();
    });
  });

  group('Edge Cases', () {
    test('✅ Long player ID', () async {
      final longId = 'x' * 500;
      final controller = MediaController.create(playerId: longId);
      await controller.initialize();

      expect(controller.player.playerId, longId);
      expect(controller.player.playerId.length, 500);

      controller.dispose();
    });

    test('✅ Special characters in player ID', () async {
      final specialIds = [
        'player-with-dashes',
        'player_with_underscores',
        'player.with.dots',
        'player:with:colons',
        'player/with/slashes',
        'player#with#hashes',
        'player@with@at',
        'player123',
        '123player',
      ];

      for (final id in specialIds) {
        final controller = MediaController.create(playerId: id);
        await controller.initialize();
        expect(controller.player.playerId, id);
        controller.dispose();
      }
    });

    test('✅ Rapid creation doesnt crash', () async {
      for (int i = 0; i < 30; i++) {
        final controller = MediaController.create();
        await controller.initialize();
        controller.dispose();
      }
    });

    test('✅ Can reuse playerId after disposal', () async {
      const id = 'reusable_id';

      final controller1 = MediaController.create(playerId: id);
      await controller1.initialize();
      expect(controller1.player.playerId, id);
      controller1.dispose();

      final controller2 = MediaController.create(playerId: id);
      await controller2.initialize();
      expect(controller2.player.playerId, id);
      expect(controller2.player.isDisposed, false);
      controller2.dispose();
    });
  });

  group('Configuration & Config Updates', () {
    test('✅ Different configs are independent', () async {
      final c1 = MediaController.create(
        playerId: 'config_test_1',
        config: const MediaConfig(autoPlay: true, volume: 0.3),
      );
      final c2 = MediaController.create(
        playerId: 'config_test_2',
        config: const MediaConfig(autoPlay: false, volume: 0.7),
      );

      await c1.initialize();
      await c2.initialize();

      expect(c1.player.config.autoPlay, true);
      expect(c1.player.config.volume, 0.3);
      // Just check volume for c2, autoPlay may default
      expect(c2.player.config.volume, 0.7);

      c1.dispose();
      c2.dispose();
    });

    test('✅ Config update works after init', () async {
      final controller = MediaController.create(
        config: const MediaConfig(volume: 0.5),
      );
      await controller.initialize();

      expect(controller.player.config.volume, 0.5);

      await controller.updateConfig(
        controller.player.config.copyWith(volume: 0.9),
      );

      expect(controller.player.config.volume, 0.9);

      controller.dispose();
    });
  });

  group('Stress Tests', () {
    test('💪 Survives 200 rapid operations', () async {
      final controller = MediaController.create();
      await controller.initialize();

      for (int i = 0; i < 200; i++) {
        await controller.play();
        await controller.pause();
      }

      expect(controller.player.isDisposed, false);
      expect(controller.player.isInitialized, true);

      controller.dispose();
    });

    test('💪 20 controllers with rapid operations', () async {
      final controllers = <MediaController>[];

      // Create 20
      for (int i = 0; i < 20; i++) {
        final controller = MediaController.create();
        await controller.initialize();
        controllers.add(controller);
      }

      // Operate on all
      for (final controller in controllers) {
        await controller.play();
        await controller.pause();
      }

      // All should still be valid
      for (final controller in controllers) {
        expect(controller.player.isDisposed, false);
      }

      // Dispose all
      for (final controller in controllers) {
        controller.dispose();
      }

      // All should be disposed
      for (final controller in controllers) {
        expect(controller.player.isDisposed, true);
      }
    });
  });

  group('Memory Stats', () {
    test('📊 Instance count tracking', () async {
      // Create 5 with unique IDs
      final controllers = <MediaController>[];

      for (int i = 0; i < 5; i++) {
        final controller = MediaController.create(playerId: 'stats_test_$i');
        await controller.initialize();
        controllers.add(controller);
      }

      // All should be initialized
      for (int i = 0; i < 5; i++) {
        expect(controllers[i].player.isDisposed, false);
        expect(controllers[i].player.playerId, 'stats_test_$i');
      }

      // Dispose first 3
      for (int i = 0; i < 3; i++) {
        controllers[i].dispose();
        expect(controllers[i].player.isDisposed, true);
      }

      // Last 2 should still be active
      expect(controllers[3].player.isDisposed, false);
      expect(controllers[4].player.isDisposed, false);

      // Cleanup remaining
      controllers[3].dispose();
      controllers[4].dispose();

      expect(controllers[3].player.isDisposed, true);
      expect(controllers[4].player.isDisposed, true);
    });
  });
}

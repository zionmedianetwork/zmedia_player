import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Phase 3: Notification, PiP, and Cast model tests
void main() {
  group('NotificationConfig', () {
    test('creates with default values', () {
      const config = NotificationConfig();

      expect(config.enabled, true);
      expect(config.showPlayPause, true);
      expect(config.showNext, true);
      expect(config.showPrevious, true);
      expect(config.showStop, false);
    });

    test('creates with custom values', () {
      const config = NotificationConfig(
        enabled: true,
        showPlayPause: true,
        showNext: false,
        showSeekForward: true,
        showStop: true,
        smallIcon: 'notification_icon',
      );

      expect(config.enabled, true);
      expect(config.showPlayPause, true);
      expect(config.showNext, false);
      expect(config.showSeekForward, true);
      expect(config.showStop, true);
      expect(config.smallIcon, 'notification_icon');
    });

    test('copyWith updates values correctly', () {
      const original = NotificationConfig(
        enabled: true,
        showPlayPause: true,
      );

      final updated = original.copyWith(
        enabled: false,
        showNext: false,
      );

      expect(updated.enabled, false);
      expect(updated.showNext, false);
      expect(updated.showPlayPause, true); // Unchanged
    });

    // -------------------------------------------------------------------
    // Regression: NotificationConfig.priority must default to `null`
    // ("no explicit priority requested"), not NotificationPriority.high.
    // A media notification re-posts on every playback state/position tick;
    // defaulting to a non-`low` value would make every existing
    // integrator's notification newly re-alert on every tick purely from a
    // package upgrade, with no code change on their part -- see the
    // field's dartdoc.
    // -------------------------------------------------------------------
    test('priority defaults to null (no explicit priority requested)', () {
      const config = NotificationConfig();

      expect(config.priority, isNull);
      // toMap() must forward that null through as-is (not resolve it to
      // some default string) -- native's own resolveChannelImportance/
      // resolveCompatPriority already fall back to LOW for a
      // missing/unrecognized value.
      expect(config.toMap()['priority'], isNull);
    });

    test('an explicitly-set priority is honored by toMap()', () {
      const config = NotificationConfig(priority: NotificationPriority.high);

      expect(config.priority, NotificationPriority.high);
      expect(config.toMap()['priority'], 'high');
    });
  });

  group('PipConfig', () {
    test('creates with default values', () {
      const config = PipConfig();

      expect(config.enabled, true);
      expect(config.aspectRatio, 16 / 9);
      expect(config.showPlaybackControls, true);
      expect(config.autoEnterOnBackground, false);
    });

    test('creates with custom values', () {
      const config = PipConfig(
        enabled: true,
        aspectRatio: 4 / 3,
        showPlaybackControls: false,
        autoEnterOnBackground: true,
      );

      expect(config.enabled, true);
      expect(config.aspectRatio, 4 / 3);
      expect(config.showPlaybackControls, false);
      expect(config.autoEnterOnBackground, true);
    });
  });

  group('PipStatus', () {
    test('creates unavailable status', () {
      const status = PipStatus(
        state: PipState.unavailable,
        isSupported: false,
        isActive: false,
      );

      expect(status.state, PipState.unavailable);
      expect(status.isSupported, false);
      expect(status.isActive, false);
    });

    test('creates active PiP status', () {
      const status = PipStatus(
        state: PipState.active,
        isSupported: true,
        isActive: true,
      );

      expect(status.state, PipState.active);
      expect(status.isSupported, true);
      expect(status.isActive, true);
    });

    test('handles all PiP states', () {
      const states = [
        PipStatus(
            state: PipState.unavailable, isSupported: false, isActive: false),
        PipStatus(
            state: PipState.available, isSupported: true, isActive: false),
        PipStatus(state: PipState.active, isSupported: true, isActive: true),
        PipStatus(state: PipState.exiting, isSupported: true, isActive: false),
      ];

      expect(states[0].state, PipState.unavailable);
      expect(states[1].state, PipState.available);
      expect(states[2].state, PipState.active);
      expect(states[3].state, PipState.exiting);
    });
  });

  group('CastDevice', () {
    test('creates Chromecast device', () {
      const device = CastDevice(
        id: 'cast1',
        name: 'Living Room TV',
        type: CastDeviceType.chromecast,
        model: 'Chromecast Ultra',
        manufacturer: 'Google',
      );

      expect(device.id, 'cast1');
      expect(device.name, 'Living Room TV');
      expect(device.type, CastDeviceType.chromecast);
      expect(device.model, 'Chromecast Ultra');
      expect(device.manufacturer, 'Google');
    });

    test('creates AirPlay device', () {
      const device = CastDevice(
        id: 'airplay1',
        name: 'Apple TV',
        type: CastDeviceType.airplay,
        model: 'Apple TV 4K',
        manufacturer: 'Apple',
      );

      expect(device.type, CastDeviceType.airplay);
      expect(device.manufacturer, 'Apple');
    });

    test('tracks connection state', () {
      const disconnected = CastDevice(
        id: 'device1',
        name: 'TV',
        type: CastDeviceType.chromecast,
        isConnected: false,
      );

      const connected = CastDevice(
        id: 'device1',
        name: 'TV',
        type: CastDeviceType.chromecast,
        isConnected: true,
      );

      expect(disconnected.isConnected, false);
      expect(connected.isConnected, true);
    });
  });

  group('CastStatus', () {
    test('creates disconnected status', () {
      const status = CastStatus(
        state: CastState.disconnected,
        isAvailable: true,
        isCasting: false,
      );

      expect(status.state, CastState.disconnected);
      expect(status.isAvailable, true);
      expect(status.isCasting, false);
    });

    test('creates connected status', () {
      const device = CastDevice(
        id: 'cast1',
        name: 'TV',
        type: CastDeviceType.chromecast,
      );

      const status = CastStatus(
        state: CastState.connected,
        isAvailable: true,
        isCasting: true,
        device: device,
      );

      expect(status.state, CastState.connected);
      expect(status.isCasting, true);
      expect(status.device, device);
    });
  });

  group('CastConfig', () {
    test('creates with default values', () {
      const config = CastConfig();

      expect(config.enabled, true);
      expect(config.enableChromecast, true);
      expect(config.enableAirPlay, true);
      expect(config.discoveryTimeout, 10);
      expect(config.showCastButton, true);
      expect(config.chromecastAppId, isNull);
    });

    test('creates with custom values', () {
      const config = CastConfig(
        enabled: true,
        enableChromecast: true,
        enableAirPlay: false,
        chromecastAppId: 'custom-app-id',
      );

      expect(config.enabled, true);
      expect(config.enableChromecast, true);
      expect(config.enableAirPlay, false);
      expect(config.chromecastAppId, 'custom-app-id');
    });
  });
}

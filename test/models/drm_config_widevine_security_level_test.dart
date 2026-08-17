import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Item 2 (gate item / B-12 wave 2): "Wire validateDrmConfig /
// getWidevineSecurityLevel into the load path with a fail-closed
// minimum-security-level policy."
//
// These tests cover the Dart-side carrier for the policy —
// DrmConfig.minWidevineSecurityLevel and its wire (de)serialization — which
// is what native DrmHandler.validateDrmConfig (Android) reads. The native
// enforcement itself has no automated test coverage (see CLAUDE.md); these
// tests only prove the Dart model correctly carries the field end to end.
// ---------------------------------------------------------------------------

void main() {
  group('WidevineSecurityLevel wire format', () {
    test('wireValue serializes to the MediaDrm-matching strings', () {
      expect(WidevineSecurityLevel.l1.wireValue, 'L1');
      expect(WidevineSecurityLevel.l2.wireValue, 'L2');
      expect(WidevineSecurityLevel.l3.wireValue, 'L3');
    });

    test('widevineSecurityLevelFromWire parses valid values', () {
      expect(widevineSecurityLevelFromWire('L1'), WidevineSecurityLevel.l1);
      expect(widevineSecurityLevelFromWire('L2'), WidevineSecurityLevel.l2);
      expect(widevineSecurityLevelFromWire('L3'), WidevineSecurityLevel.l3);
    });

    test('widevineSecurityLevelFromWire is case-insensitive and trims',
        () {
      expect(widevineSecurityLevelFromWire(' l1 '), WidevineSecurityLevel.l1);
      expect(widevineSecurityLevelFromWire('l3'), WidevineSecurityLevel.l3);
    });

    test('widevineSecurityLevelFromWire returns null for unrecognized input',
        () {
      // "Unknown" is exactly what native getWidevineSecurityLevel() returns
      // when the device's MediaDrm property read fails — this must not be
      // silently mapped onto any ranked level (see the fail-closed policy).
      expect(widevineSecurityLevelFromWire('Unknown'), isNull);
      expect(widevineSecurityLevelFromWire('bogus'), isNull);
      expect(widevineSecurityLevelFromWire(null), isNull);
      expect(widevineSecurityLevelFromWire(''), isNull);
    });
  });

  group('DrmConfig.minWidevineSecurityLevel', () {
    test('defaults to null (opt-in, no behaviour change)', () {
      const config = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://license.example.com/widevine',
      );
      expect(config.minWidevineSecurityLevel, isNull);
    });

    test('DrmConfig.widevine factory accepts minWidevineSecurityLevel', () {
      final config = DrmConfig.widevine(
        licenseUrl: 'https://license.example.com/widevine',
        minWidevineSecurityLevel: WidevineSecurityLevel.l1,
      );
      expect(config.minWidevineSecurityLevel, WidevineSecurityLevel.l1);
      expect(config.scheme, DrmScheme.widevine);
    });

    test('toMap() serializes minWidevineSecurityLevel as its wire value',
        () {
      final config = DrmConfig.widevine(
        licenseUrl: 'https://license.example.com/widevine',
        minWidevineSecurityLevel: WidevineSecurityLevel.l1,
      );
      final map = config.toMap();
      expect(map['minWidevineSecurityLevel'], 'L1');
    });

    test('toMap() omits minWidevineSecurityLevel (null) when not set', () {
      final config = DrmConfig.widevine(
        licenseUrl: 'https://license.example.com/widevine',
      );
      final map = config.toMap();
      expect(map['minWidevineSecurityLevel'], isNull);
    });

    test('fromMap() round-trips minWidevineSecurityLevel', () {
      final original = DrmConfig.widevine(
        licenseUrl: 'https://license.example.com/widevine',
        minWidevineSecurityLevel: WidevineSecurityLevel.l3,
      );
      final roundTripped = DrmConfig.fromMap(original.toMap());
      expect(roundTripped.minWidevineSecurityLevel, WidevineSecurityLevel.l3);
      expect(roundTripped.scheme, DrmScheme.widevine);
    });

    test('fromMap() with missing minWidevineSecurityLevel key defaults null',
        () {
      final map = {
        'scheme': 'widevine',
        'licenseUrl': 'https://license.example.com/widevine',
      };
      final config = DrmConfig.fromMap(map);
      expect(config.minWidevineSecurityLevel, isNull);
    });

    test('copyWith updates minWidevineSecurityLevel', () {
      final base = DrmConfig.widevine(
        licenseUrl: 'https://license.example.com/widevine',
      );
      final updated = base.copyWith(
        minWidevineSecurityLevel: WidevineSecurityLevel.l2,
      );
      expect(updated.minWidevineSecurityLevel, WidevineSecurityLevel.l2);
      // Unrelated fields are preserved.
      expect(updated.licenseUrl, base.licenseUrl);
    });
  });

  group('InputValidator.validateDrmConfig — minWidevineSecurityLevel scope',
      () {
    test('throws when set on a non-widevine scheme (fairplay)', () {
      final config = DrmConfig(
        scheme: DrmScheme.fairplay,
        licenseUrl: 'https://license.example.com/fairplay',
        certificateUrl: 'https://license.example.com/cert',
        minWidevineSecurityLevel: WidevineSecurityLevel.l1,
      );

      expect(
        () => InputValidator.validateDrmConfig(config),
        throwsA(isA<ConfigurationException>()),
        reason: 'minWidevineSecurityLevel only applies to DrmScheme.widevine '
            '— FairPlay has no equivalent concept (see WidevineSecurityLevel '
            'dartdoc)',
      );
    });

    test('throws when set on DrmScheme.token', () {
      final config = DrmConfig(
        scheme: DrmScheme.token,
        licenseUrl: 'https://license.example.com/token',
        token: 'a-token-value-long-enough',
        minWidevineSecurityLevel: WidevineSecurityLevel.l3,
      );

      expect(
        () => InputValidator.validateDrmConfig(config),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('does not throw when set on DrmScheme.widevine', () {
      final config = DrmConfig.widevine(
        licenseUrl: 'https://license.example.com/widevine',
        minWidevineSecurityLevel: WidevineSecurityLevel.l1,
      );

      expect(
        () => InputValidator.validateDrmConfig(config),
        returnsNormally,
      );
    });

    test('does not throw when unset regardless of scheme', () {
      final fairplay = DrmConfig(
        scheme: DrmScheme.fairplay,
        licenseUrl: 'https://license.example.com/fairplay',
        certificateUrl: 'https://license.example.com/cert',
      );

      expect(
        () => InputValidator.validateDrmConfig(fairplay),
        returnsNormally,
      );
    });
  });
}

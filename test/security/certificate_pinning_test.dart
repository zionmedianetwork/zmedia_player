import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Tests for CertificatePinningConfig and the DrmConfig certificatePinning field.
///
/// All test pins are synthetic 64-char hex strings used only in the test
/// environment — they are not real server pins.
void main() {
  // A pair of realistic-looking (but entirely fake) 64-char hex SHA-256 pins.
  const fakePin1 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fakePin2 =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const fakePin3 =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

  group('CertificatePinningConfig', () {
    group('isValid', () {
      test('empty pins map is valid (no pinning)', () {
        final config = CertificatePinningConfig.disabled();
        expect(config.isValid(), isTrue);
      });

      test('valid config with two pins per domain passes', () {
        final config = CertificatePinningConfig.fromPins({
          'drm.example.com': [fakePin1, fakePin2],
        });
        expect(config.isValid(), isTrue);
      });

      test('fails when domain has fewer than minimumPins entries', () {
        final config = CertificatePinningConfig(
          pins: {
            'drm.example.com': [fakePin1], // only 1, default minimum is 2
          },
          minimumPins: 2,
        );
        expect(config.isValid(), isFalse);
      });

      test('passes when minimumPins is 1 and one pin is present', () {
        final config = CertificatePinningConfig(
          pins: {
            'drm.example.com': [fakePin1],
          },
          minimumPins: 1,
        );
        expect(config.isValid(), isTrue);
      });

      test('fails when a pin is not 64 hex characters', () {
        final config = CertificatePinningConfig(
          pins: {
            'drm.example.com': ['short', fakePin2],
          },
          minimumPins: 2,
        );
        expect(config.isValid(), isFalse);
      });

      test('fails when a pin contains non-hex characters', () {
        final badPin = 'z' * 64; // 'z' is not a valid hex char
        final config = CertificatePinningConfig(
          pins: {
            'drm.example.com': [badPin, fakePin2],
          },
          minimumPins: 2,
        );
        expect(config.isValid(), isFalse);
      });

      test('mixed-case hex pins are accepted by isValid', () {
        // The regex allows a-fA-F
        final mixedPin = 'AAAA${'a' * 60}';
        final config = CertificatePinningConfig(
          pins: {
            'drm.example.com': [mixedPin, fakePin2],
          },
          minimumPins: 2,
        );
        expect(config.isValid(), isTrue);
      });
    });

    group('getPinsForDomain', () {
      late CertificatePinningConfig config;

      setUp(() {
        config = CertificatePinningConfig(
          pins: {
            'exact.example.com': [fakePin1, fakePin2],
            '*.wildcard.com': [fakePin2, fakePin3],
          },
          minimumPins: 2,
        );
      });

      test('returns pins for exact host match', () {
        final pins = config.getPinsForDomain('exact.example.com');
        expect(pins, isNotNull);
        expect(pins, containsAll([fakePin1, fakePin2]));
      });

      test('returns null for unknown host', () {
        expect(config.getPinsForDomain('unknown.com'), isNull);
      });

      test('returns wildcard pins for matching subdomain', () {
        final pins = config.getPinsForDomain('cdn.wildcard.com');
        expect(pins, isNotNull);
        expect(pins, containsAll([fakePin2, fakePin3]));
      });

      test('wildcard does NOT match the apex domain itself', () {
        // "*.wildcard.com" should not match "wildcard.com"
        // The implementation splits on '.' and requires length >= 2.
        // "wildcard.com" → parts = ["wildcard","com"] → wildcard = "*.com"
        // which is not in pins, so returns null.
        expect(config.getPinsForDomain('wildcard.com'), isNull);
      });

      test('wildcard does NOT match two-level-deep subdomain', () {
        // "*.wildcard.com" should not match "a.b.wildcard.com"
        // "a.b.wildcard.com" → parts[1..] = "b.wildcard.com" → wildcard = "*.b.wildcard.com"
        // which is not in pins.
        expect(config.getPinsForDomain('a.b.wildcard.com'), isNull);
      });

      test('hasPinsForDomain mirrors getPinsForDomain nullity', () {
        expect(config.hasPinsForDomain('exact.example.com'), isTrue);
        expect(config.hasPinsForDomain('cdn.wildcard.com'), isTrue);
        expect(config.hasPinsForDomain('unknown.net'), isFalse);
      });
    });

    group('toMap / fromMap round-trip', () {
      test('serialises and deserialises correctly', () {
        final original = CertificatePinningConfig(
          pins: {
            'drm.example.com': [fakePin1, fakePin2],
            '*.cdn.example.com': [fakePin3],
          },
          enforceExpiration: false,
          allowBackupPins: false,
          minimumPins: 1,
        );

        final map = original.toMap();
        final restored = CertificatePinningConfig.fromMap(
          Map<String, dynamic>.from(map),
        );

        expect(restored.pins['drm.example.com'], [fakePin1, fakePin2]);
        expect(restored.pins['*.cdn.example.com'], [fakePin3]);
        expect(restored.enforceExpiration, isFalse);
        expect(restored.allowBackupPins, isFalse);
        expect(restored.minimumPins, 1);
      });

      test('round-trip preserves empty pins map', () {
        final original = CertificatePinningConfig.disabled();
        final restored = CertificatePinningConfig.fromMap(
          Map<String, dynamic>.from(original.toMap()),
        );
        expect(restored.pins, isEmpty);
      });

      test('fromMap provides defaults when optional keys are absent', () {
        final restored = CertificatePinningConfig.fromMap({'pins': {}});
        expect(restored.enforceExpiration, isTrue);
        expect(restored.allowBackupPins, isTrue);
        expect(restored.minimumPins, 2);
      });
    });

    group('disabled factory', () {
      test('disabled() creates empty-pins config', () {
        final config = CertificatePinningConfig.disabled();
        expect(config.pins, isEmpty);
        expect(config.isValid(), isTrue);
      });
    });
  });

  group('DrmConfig with certificatePinning', () {
    final pinningConfig = CertificatePinningConfig.fromPins({
      'drm.example.com': [fakePin1, fakePin2],
    });

    group('Factory constructors accept certificatePinning', () {
      test('widevine factory stores pinning config', () {
        final config = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
          certificatePinning: pinningConfig,
        );
        expect(config.certificatePinning, isNotNull);
        expect(config.certificatePinning!.pins['drm.example.com'],
            contains(fakePin1));
      });

      test('fairplay factory stores pinning config', () {
        final config = DrmConfig.fairplay(
          licenseUrl: 'https://drm.example.com/license',
          certificateUrl: 'https://drm.example.com/cert.cer',
          certificatePinning: pinningConfig,
        );
        expect(config.certificatePinning, isNotNull);
      });

      test('token factory stores pinning config', () {
        final config = DrmConfig.token(
          licenseUrl: 'https://drm.example.com/license',
          token: 'jwt-token',
          certificatePinning: pinningConfig,
        );
        expect(config.certificatePinning, isNotNull);
      });

      test('ezdrm factory stores pinning config', () {
        final config = DrmConfig.ezdrm(
          ezdrmConfig: EzdrmConfig.widevine(
            customerId: 'customer123',
            apiKey: 'api-key',
            contentId: 'content456',
          ),
          certificatePinning: pinningConfig,
        );
        expect(config.certificatePinning, isNotNull);
      });

      test('factory without pinning leaves certificatePinning null', () {
        final config = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
        );
        expect(config.certificatePinning, isNull);
      });
    });

    group('toMap serialisation', () {
      test('toMap includes certificatePinning when set', () {
        final config = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
          certificatePinning: pinningConfig,
        );
        final map = config.toMap();
        expect(map['certificatePinning'], isNotNull);
        final pinMap = map['certificatePinning'] as Map<String, dynamic>;
        expect(pinMap['pins'], isA<Map>());
      });

      test('toMap has null certificatePinning when not set', () {
        final config = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
        );
        final map = config.toMap();
        expect(map['certificatePinning'], isNull);
      });
    });

    group('fromMap deserialisation', () {
      test('fromMap restores certificatePinning', () {
        final original = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
          certificatePinning: pinningConfig,
        );
        final map = original.toMap();
        // Simulate the round-trip through the platform channel by coercing to
        // Map<String, dynamic> as the native side would return.
        final restored = DrmConfig.fromMap(
          Map<String, dynamic>.from(map.map((k, v) {
            if (v is Map) {
              return MapEntry(k, Map<String, dynamic>.from(v));
            }
            return MapEntry(k, v);
          })),
        );
        expect(restored.certificatePinning, isNotNull);
        expect(
          restored.certificatePinning!.pins.containsKey('drm.example.com'),
          isTrue,
        );
      });

      test('fromMap with null certificatePinning key produces null field', () {
        final map = <String, dynamic>{
          'scheme': 'widevine',
          'licenseUrl': 'https://drm.example.com/license',
          'allowOffline': false,
          'autoRenewLicense': true,
        };
        final config = DrmConfig.fromMap(map);
        expect(config.certificatePinning, isNull);
      });
    });

    group('round-trip serialisation', () {
      test('full round-trip preserves all fields', () {
        final original = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
          headers: {'X-Custom': 'value'},
          allowOffline: true,
          certificatePinning: CertificatePinningConfig(
            pins: {
              'drm.example.com': [fakePin1, fakePin2],
              '*.cdn.example.com': [fakePin3, fakePin1],
            },
            minimumPins: 2,
          ),
        );

        final map = original.toMap();
        // Coerce nested maps (mirrors what a platform channel returns)
        final pinningMap =
            Map<String, dynamic>.from(map['certificatePinning'] as Map);
        final rawPins = Map<String, dynamic>.from(pinningMap['pins'] as Map);
        final coercedPins = rawPins.map(
          (k, v) => MapEntry(k, List<String>.from(v as List)),
        );
        pinningMap['pins'] = coercedPins;
        map['certificatePinning'] = pinningMap;

        final restored = DrmConfig.fromMap(map);

        expect(restored.scheme, original.scheme);
        expect(restored.licenseUrl, original.licenseUrl);
        expect(restored.allowOffline, original.allowOffline);
        expect(restored.headers, original.headers);
        expect(restored.certificatePinning, isNotNull);
        expect(
          restored.certificatePinning!.getPinsForDomain('drm.example.com'),
          containsAll([fakePin1, fakePin2]),
        );
        expect(
          restored.certificatePinning!
              .getPinsForDomain('assets.cdn.example.com'),
          containsAll([fakePin3, fakePin1]),
        );
      });

      test('round-trip without pinning keeps certificatePinning null', () {
        final original = DrmConfig.fairplay(
          licenseUrl: 'https://drm.example.com/license',
          certificateUrl: 'https://drm.example.com/cert.cer',
        );
        final restored = DrmConfig.fromMap(original.toMap());
        expect(restored.certificatePinning, isNull);
      });
    });

    group('copyWith', () {
      test('copyWith can add certificatePinning to an existing config', () {
        final original = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
        );
        expect(original.certificatePinning, isNull);

        final updated = original.copyWith(certificatePinning: pinningConfig);
        expect(updated.certificatePinning, isNotNull);
        // Original is unchanged
        expect(original.certificatePinning, isNull);
      });

      test('copyWith without certificatePinning preserves existing value', () {
        final original = DrmConfig.widevine(
          licenseUrl: 'https://drm.example.com/license',
          certificatePinning: pinningConfig,
        );
        final updated = original.copyWith(allowOffline: true);
        expect(updated.certificatePinning, isNotNull);
        expect(updated.allowOffline, isTrue);
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

void main() {
  group('DrmConfig', () {
    group('Factory Constructors', () {
      test('creates Widevine config correctly', () {
        final config = DrmConfig.widevine(
          licenseUrl: 'https://example.com/license',
          headers: {'Authorization': 'Bearer token'},
          allowOffline: true,
          offlineLicenseDuration: 3600,
        );

        expect(config.scheme, DrmScheme.widevine);
        expect(config.licenseUrl, 'https://example.com/license');
        expect(config.headers?['Authorization'], 'Bearer token');
        expect(config.allowOffline, true);
        expect(config.offlineLicenseDuration, 3600);
      });

      test('creates FairPlay config correctly', () {
        final config = DrmConfig.fairplay(
          licenseUrl: 'https://example.com/license',
          certificateUrl: 'https://example.com/cert.cer',
          contentId: 'content123',
          headers: {'X-Custom': 'value'},
        );

        expect(config.scheme, DrmScheme.fairplay);
        expect(config.licenseUrl, 'https://example.com/license');
        expect(config.certificateUrl, 'https://example.com/cert.cer');
        expect(config.contentId, 'content123');
        expect(config.headers?['X-Custom'], 'value');
      });

      test('creates token-based config correctly', () {
        final config = DrmConfig.token(
          licenseUrl: 'https://example.com/license',
          token: 'jwt_token',
          keyId: 'key123',
        );

        expect(config.scheme, DrmScheme.token);
        expect(config.licenseUrl, 'https://example.com/license');
        expect(config.token, 'jwt_token');
        expect(config.keyId, 'key123');
      });

      test('creates EZDRM config correctly', () {
        final ezdrmConfig = EzdrmConfig.widevine(
          customerId: 'customer123',
          apiKey: 'api_key',
          contentId: 'content456',
        );

        final config = DrmConfig.ezdrm(
          ezdrmConfig: ezdrmConfig,
          allowOffline: true,
        );

        expect(config.scheme, DrmScheme.ezdrm);
        expect(config.ezdrmConfig, ezdrmConfig);
        expect(config.allowOffline, true);
      });
    });

    group('Serialization', () {
      test('toMap() serializes all fields correctly', () {
        final config = DrmConfig(
          scheme: DrmScheme.widevine,
          licenseUrl: 'https://example.com/license',
          headers: {'key': 'value'},
          token: 'token123',
          allowOffline: true,
        );

        final map = config.toMap();

        expect(map['scheme'], 'widevine');
        expect(map['licenseUrl'], 'https://example.com/license');
        expect(map['headers'], {'key': 'value'});
        expect(map['token'], 'token123');
        expect(map['allowOffline'], true);
      });

      test('fromMap() deserializes correctly', () {
        final map = {
          'scheme': 'fairplay',
          'licenseUrl': 'https://example.com/license',
          'certificateUrl': 'https://example.com/cert.cer',
          'allowOffline': false,
        };

        final config = DrmConfig.fromMap(map);

        expect(config.scheme, DrmScheme.fairplay);
        expect(config.licenseUrl, 'https://example.com/license');
        expect(config.certificateUrl, 'https://example.com/cert.cer');
        expect(config.allowOffline, false);
      });

      test('round-trip serialization preserves data', () {
        final original = DrmConfig.widevine(
          licenseUrl: 'https://example.com/license',
          headers: {'Auth': 'Bearer token'},
          allowOffline: true,
        );

        final map = original.toMap();
        final deserialized = DrmConfig.fromMap(map);

        expect(deserialized.scheme, original.scheme);
        expect(deserialized.licenseUrl, original.licenseUrl);
        expect(deserialized.headers, original.headers);
        expect(deserialized.allowOffline, original.allowOffline);
      });
    });

    group('copyWith', () {
      test('creates modified copy with new values', () {
        final original = DrmConfig.widevine(
          licenseUrl: 'https://example.com/license',
          allowOffline: false,
        );

        final modified = original.copyWith(
          allowOffline: true,
          headers: {'New': 'Header'},
        );

        expect(modified.licenseUrl, original.licenseUrl);
        expect(modified.scheme, original.scheme);
        expect(modified.allowOffline, true);
        expect(modified.headers?['New'], 'Header');
      });

      test('preserves original values when not overridden', () {
        final original = DrmConfig.token(
          licenseUrl: 'https://example.com/license',
          token: 'original_token',
        );

        final modified = original.copyWith(
          headers: {'New': 'Header'},
        );

        expect(modified.token, 'original_token');
        expect(modified.licenseUrl, 'https://example.com/license');
      });
    });
  });

  group('EzdrmConfig', () {
    test('generates correct Widevine license URL', () {
      final config = EzdrmConfig.widevine(
        customerId: 'customer123',
        apiKey: 'api_key',
        contentId: 'content456',
      );

      expect(
        config.licenseUrl,
        contains('widevine-dash.ezdrm.com'),
      );
      expect(config.licenseUrl, contains('customer123'));
    });

    test('generates correct FairPlay license URL', () {
      final config = EzdrmConfig.fairplay(
        customerId: 'customer123',
        apiKey: 'api_key',
        contentId: 'content456',
      );

      expect(
        config.licenseUrl,
        contains('fps.ezdrm.com'),
      );
      expect(config.licenseUrl, contains('customer123'));
    });

    test('provides FairPlay certificate URL', () {
      final config = EzdrmConfig.fairplay(
        customerId: 'customer123',
        apiKey: 'api_key',
        contentId: 'content456',
      );

      expect(config.certificateUrl, isNotNull);
      expect(config.certificateUrl, contains('fps.ezdrm.com'));
    });

    test('includes correct headers', () {
      final config = EzdrmConfig.widevine(
        customerId: 'customer123',
        apiKey: 'api_key',
        contentId: 'content456',
      );

      final headers = config.headers;

      expect(headers['X-EZDRM-CUSTOMER-ID'], 'customer123');
      expect(headers['X-EZDRM-API-KEY'], 'api_key');
      expect(headers['X-EZDRM-CONTENT-ID'], 'content456');
    });

    test('serializes and deserializes correctly', () {
      final original = EzdrmConfig.widevine(
        customerId: 'customer123',
        apiKey: 'api_key',
        contentId: 'content456',
      );

      final map = original.toMap();
      final deserialized = EzdrmConfig.fromMap(map);

      expect(deserialized.customerId, original.customerId);
      expect(deserialized.apiKey, original.apiKey);
      expect(deserialized.contentId, original.contentId);
    });
  });

  group('DrmLicense', () {
    test('creates license with all properties', () {
      final expiration = DateTime.now().add(Duration(hours: 24));
      final license = DrmLicense(
        id: 'license123',
        keyData: 'encrypted_key_data',
        expirationTime: expiration,
        playbackDuration: 7200,
        status: DrmLicenseStatus.active,
      );

      expect(license.id, 'license123');
      expect(license.keyData, 'encrypted_key_data');
      expect(license.expirationTime, expiration);
      expect(license.playbackDuration, 7200);
      expect(license.status, DrmLicenseStatus.active);
    });

    test('isExpired returns true for expired license', () {
      final license = DrmLicense(
        id: 'license123',
        keyData: 'key',
        expirationTime: DateTime.now().subtract(Duration(hours: 1)),
      );

      expect(license.isExpired, true);
    });

    test('isExpired returns false for valid license', () {
      final license = DrmLicense(
        id: 'license123',
        keyData: 'key',
        expirationTime: DateTime.now().add(Duration(hours: 1)),
      );

      expect(license.isExpired, false);
    });

    test('isExpired returns false when no expiration time', () {
      final license = DrmLicense(
        id: 'license123',
        keyData: 'key',
      );

      expect(license.isExpired, false);
    });

    test('isExpiringSoon returns true within 1 hour', () {
      final license = DrmLicense(
        id: 'license123',
        keyData: 'key',
        expirationTime: DateTime.now().add(Duration(minutes: 30)),
      );

      expect(license.isExpiringSoon, true);
    });

    test('isExpiringSoon returns false when more than 1 hour', () {
      final license = DrmLicense(
        id: 'license123',
        keyData: 'key',
        expirationTime: DateTime.now().add(Duration(hours: 2)),
      );

      expect(license.isExpiringSoon, false);
    });

    test('serializes and deserializes correctly', () {
      final expiration = DateTime.now().add(Duration(hours: 24));
      final original = DrmLicense(
        id: 'license123',
        keyData: 'key_data',
        expirationTime: expiration,
        playbackDuration: 3600,
        status: DrmLicenseStatus.active,
      );

      final map = original.toMap();
      final deserialized = DrmLicense.fromMap(map);

      expect(deserialized.id, original.id);
      expect(deserialized.keyData, original.keyData);
      expect(
        deserialized.expirationTime?.millisecondsSinceEpoch,
        original.expirationTime?.millisecondsSinceEpoch,
      );
      expect(deserialized.playbackDuration, original.playbackDuration);
      expect(deserialized.status, original.status);
    });
  });

  group('DrmSession', () {
    test('creates session with all properties', () {
      final now = DateTime.now();
      final license = DrmLicense(id: 'lic1', keyData: 'key');

      final session = DrmSession(
        id: 'session123',
        state: DrmSessionState.licensed,
        license: license,
        createdAt: now,
        updatedAt: now,
      );

      expect(session.id, 'session123');
      expect(session.state, DrmSessionState.licensed);
      expect(session.license, license);
      expect(session.createdAt, now);
      expect(session.updatedAt, now);
    });

    test('copyWith creates modified copy', () {
      final original = DrmSession(
        id: 'session123',
        state: DrmSessionState.idle,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final modified = original.copyWith(
        state: DrmSessionState.acquiringLicense,
        errorMessage: 'Test error',
      );

      expect(modified.id, original.id);
      expect(modified.state, DrmSessionState.acquiringLicense);
      expect(modified.errorMessage, 'Test error');
    });

    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final original = DrmSession(
        id: 'session123',
        state: DrmSessionState.licensed,
        createdAt: now,
        updatedAt: now,
      );

      final map = original.toMap();
      final deserialized = DrmSession.fromMap(map);

      expect(deserialized.id, original.id);
      expect(deserialized.state, original.state);
      expect(
        deserialized.createdAt.millisecondsSinceEpoch,
        original.createdAt.millisecondsSinceEpoch,
      );
    });
  });
}

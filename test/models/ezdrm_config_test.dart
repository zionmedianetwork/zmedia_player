import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('EzdrmConfig.fairplay', () {
    test('requires certificateUrl — uses the provided value', () {
      const certUrl = 'https://customer.example.com/fairplay.cer';
      final config = EzdrmConfig.fairplay(
        customerId: 'cust123',
        apiKey: 'api_key',
        contentId: 'content456',
        certificateUrl: certUrl,
      );

      expect(config.certificateUrl, certUrl,
          reason: 'must return the supplied certificateUrl, not a demo URL');
      expect(
        config.certificateUrl,
        isNot(contains('eleisure')),
        reason: 'must not fall back to the demo eleisure.cer URL',
      );
    });

    test('returns a production FairPlay license URL', () {
      final config = EzdrmConfig.fairplay(
        customerId: 'cust123',
        apiKey: 'api_key',
        contentId: 'content456',
        certificateUrl: 'https://example.com/cert.cer',
      );

      expect(config.licenseUrl, contains('fps.ezdrm.com'));
      expect(config.licenseUrl, contains('cust123'));
    });

    test('certificateUrl is null for Widevine config', () {
      final config = EzdrmConfig.widevine(
        customerId: 'cust123',
        apiKey: 'api_key',
        contentId: 'content456',
      );

      expect(config.certificateUrl, isNull);
    });

    test('round-trips certificateUrl through toMap/fromMap', () {
      const certUrl = 'https://example.com/fp.cer';
      final original = EzdrmConfig.fairplay(
        customerId: 'cust',
        apiKey: 'key',
        contentId: 'content',
        certificateUrl: certUrl,
      );

      final deserialized = EzdrmConfig.fromMap(original.toMap());

      expect(deserialized.certificateUrl, certUrl);
    });
  });
}

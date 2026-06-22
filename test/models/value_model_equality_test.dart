import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Tests for Fix 3: == and hashCode on value models.
///
/// For each model:
///   - Two instances with identical values are equal.
///   - Two instances with different values are not equal.
///   - Equal objects have equal hashCodes.
///   - Objects can be deduplicated in a Set.
void main() {
  // ===========================================================================
  // QualityTrack — equality by id
  // ===========================================================================
  group('QualityTrack equality', () {
    final a = QualityTrack(
      id: 'q1080p',
      name: '1080p',
      bitrate: 5000000,
      width: 1920,
      height: 1080,
    );
    final b = QualityTrack(
      id: 'q1080p',
      name: '1080p HD', // different name, same id
      bitrate: 4500000, // different bitrate, same id
      width: 1920,
      height: 1080,
    );
    final c = QualityTrack(
      id: 'q720p',
      name: '720p',
      bitrate: 2500000,
    );

    test('same id → equal', () {
      expect(a, equals(b));
    });

    test('different id → not equal', () {
      expect(a, isNot(equals(c)));
    });

    test('same id → same hashCode', () {
      expect(a.hashCode, equals(b.hashCode));
    });

    test('identical instance is equal to itself', () {
      expect(a, equals(a));
    });

    test('deduplicated correctly in a Set', () {
      final set = {a, b, c};
      expect(set, hasLength(2),
          reason: 'a and b share the same id so the set should hold 2 items');
    });
  });

  // ===========================================================================
  // AudioTrack — equality by id
  // ===========================================================================
  group('AudioTrack equality', () {
    final a = AudioTrack(
      id: 'audio_en',
      name: 'English',
      language: 'en',
      channels: 2,
    );
    final b = AudioTrack(
      id: 'audio_en',
      name: 'English (Stereo)', // different name, same id
      language: 'en-US',
      channels: 2,
    );
    final c = AudioTrack(
      id: 'audio_fr',
      name: 'French',
      language: 'fr',
    );

    test('same id → equal', () {
      expect(a, equals(b));
    });

    test('different id → not equal', () {
      expect(a, isNot(equals(c)));
    });

    test('same id → same hashCode', () {
      expect(a.hashCode, equals(b.hashCode));
    });

    test('deduplicated correctly in a Set', () {
      final set = {a, b, c};
      expect(set, hasLength(2));
    });
  });

  // ===========================================================================
  // DrmConfig — equality by key fields
  // ===========================================================================
  group('DrmConfig equality', () {
    final widevine1 = DrmConfig.widevine(
      licenseUrl: 'https://example.com/license',
      allowOffline: false,
    );
    final widevine2 = DrmConfig.widevine(
      licenseUrl: 'https://example.com/license',
      allowOffline: false,
    );
    final fairplay = DrmConfig.fairplay(
      licenseUrl: 'https://example.com/license',
      certificateUrl: 'https://example.com/cert.cer',
    );

    test('identical fields → equal', () {
      expect(widevine1, equals(widevine2));
    });

    test('different scheme → not equal', () {
      expect(widevine1, isNot(equals(fairplay)));
    });

    test('identical fields → same hashCode', () {
      expect(widevine1.hashCode, equals(widevine2.hashCode));
    });

    test('deduplicated correctly in a Set', () {
      final set = {widevine1, widevine2, fairplay};
      expect(set, hasLength(2));
    });

    test('different licenseUrl → not equal', () {
      final other = DrmConfig.widevine(
        licenseUrl: 'https://other.com/license',
        allowOffline: false,
      );
      expect(widevine1, isNot(equals(other)));
    });

    test('different allowOffline → not equal', () {
      final other = DrmConfig.widevine(
        licenseUrl: 'https://example.com/license',
        allowOffline: true,
      );
      expect(widevine1, isNot(equals(other)));
    });
  });

  // ===========================================================================
  // EzdrmConfig — equality by all fields
  // ===========================================================================
  group('EzdrmConfig equality', () {
    final wv1 = EzdrmConfig.widevine(
      customerId: 'cust1',
      apiKey: 'key1',
      contentId: 'content1',
    );
    final wv2 = EzdrmConfig.widevine(
      customerId: 'cust1',
      apiKey: 'key1',
      contentId: 'content1',
    );
    final fp = EzdrmConfig.fairplay(
      customerId: 'cust1',
      apiKey: 'key1',
      contentId: 'content1',
      certificateUrl: 'https://example.com/cert.cer',
    );
    final different = EzdrmConfig.widevine(
      customerId: 'cust2',
      apiKey: 'key2',
      contentId: 'content2',
    );

    test('same fields → equal', () {
      expect(wv1, equals(wv2));
    });

    test('Widevine vs FairPlay (same customer) → not equal', () {
      expect(wv1, isNot(equals(fp)));
    });

    test('different customer → not equal', () {
      expect(wv1, isNot(equals(different)));
    });

    test('same fields → same hashCode', () {
      expect(wv1.hashCode, equals(wv2.hashCode));
    });

    test('deduplicated correctly in a Set', () {
      final set = {wv1, wv2, fp, different};
      expect(set, hasLength(3));
    });
  });

  // ===========================================================================
  // DrmLicense — equality by id
  // ===========================================================================
  group('DrmLicense equality', () {
    final expiry = DateTime(2026, 12, 31);
    final lic1 = DrmLicense(
      id: 'lic-abc',
      keyData: 'key1',
      expirationTime: expiry,
    );
    final lic2 = DrmLicense(
      id: 'lic-abc',
      keyData: 'totally-different-key-data', // different, same id
      expirationTime: DateTime(2027, 1, 1),
    );
    final lic3 = DrmLicense(
      id: 'lic-xyz',
      keyData: 'key3',
    );

    test('same id → equal', () {
      expect(lic1, equals(lic2));
    });

    test('different id → not equal', () {
      expect(lic1, isNot(equals(lic3)));
    });

    test('same id → same hashCode', () {
      expect(lic1.hashCode, equals(lic2.hashCode));
    });

    test('deduplicated correctly in a Set', () {
      final set = {lic1, lic2, lic3};
      expect(set, hasLength(2));
    });
  });

  // ===========================================================================
  // SubtitleConfig — equality by all fields
  // ===========================================================================
  group('SubtitleConfig equality', () {
    const cfg1 = SubtitleConfig(
      fontSize: 16.0,
      fontColor: 0xFFFFFFFF,
      showOutline: true,
      outlineColor: 0xFF000000,
      verticalPosition: 0.9,
      horizontalAlignment: SubtitleAlignment.center,
    );
    const cfg2 = SubtitleConfig(
      fontSize: 16.0,
      fontColor: 0xFFFFFFFF,
      showOutline: true,
      outlineColor: 0xFF000000,
      verticalPosition: 0.9,
      horizontalAlignment: SubtitleAlignment.center,
    );
    const cfg3 = SubtitleConfig(
      fontSize: 24.0, // different font size
      fontColor: 0xFFFFFF00, // different color
      showOutline: false,
      verticalPosition: 0.5,
      horizontalAlignment: SubtitleAlignment.left,
    );

    test('same fields → equal', () {
      expect(cfg1, equals(cfg2));
    });

    test('different fields → not equal', () {
      expect(cfg1, isNot(equals(cfg3)));
    });

    test('same fields → same hashCode', () {
      expect(cfg1.hashCode, equals(cfg2.hashCode));
    });

    test('const instances are identical', () {
      // Dart const identity check.
      expect(identical(cfg1, cfg2), isTrue);
    });

    test('deduplicated correctly in a Set', () {
      final set = <SubtitleConfig>{}..addAll([cfg1, cfg2, cfg3]);
      expect(set, hasLength(2));
    });

    test('different fontSize → not equal', () {
      const other = SubtitleConfig(fontSize: 20.0);
      expect(cfg1, isNot(equals(other)));
    });

    test('different horizontalAlignment → not equal', () {
      const other = SubtitleConfig(
        horizontalAlignment: SubtitleAlignment.right,
      );
      expect(cfg1, isNot(equals(other)));
    });
  });

  // ===========================================================================
  // QoEMetrics — equality by all fields
  // ===========================================================================
  group('QoEMetrics equality', () {
    final ts = DateTime(2025, 6, 1);
    final m1 = QoEMetrics(
      totalPlayTime: const Duration(minutes: 5),
      bufferCount: 2,
      totalBufferTime: const Duration(seconds: 3),
      averageBitrate: 4000000.0,
      qualitySwitches: 1,
      startupTime: 1.2,
      rebufferRatio: 0.01,
      sessionStart: ts,
      mediaUrl: 'https://example.com/video.m3u8',
      sessionDuration: const Duration(minutes: 5, seconds: 10),
    );
    final m2 = QoEMetrics(
      totalPlayTime: const Duration(minutes: 5),
      bufferCount: 2,
      totalBufferTime: const Duration(seconds: 3),
      averageBitrate: 4000000.0,
      qualitySwitches: 1,
      startupTime: 1.2,
      rebufferRatio: 0.01,
      sessionStart: ts,
      mediaUrl: 'https://example.com/video.m3u8',
      sessionDuration: const Duration(minutes: 5, seconds: 10),
    );
    final m3 = QoEMetrics(
      totalPlayTime: const Duration(minutes: 3),
      bufferCount: 5,
      totalBufferTime: const Duration(seconds: 8),
      averageBitrate: 2000000.0,
      qualitySwitches: 3,
      startupTime: 2.5,
      rebufferRatio: 0.05,
      sessionStart: ts,
      mediaUrl: 'https://other.com/video.m3u8',
      sessionDuration: const Duration(minutes: 3, seconds: 20),
    );

    test('same fields → equal', () {
      expect(m1, equals(m2));
    });

    test('different fields → not equal', () {
      expect(m1, isNot(equals(m3)));
    });

    test('same fields → same hashCode', () {
      expect(m1.hashCode, equals(m2.hashCode));
    });

    test('deduplicated correctly in a Set', () {
      final set = {m1, m2, m3};
      expect(set, hasLength(2));
    });
  });

  // ===========================================================================
  // EngagementMetrics — equality by all fields
  // ===========================================================================
  group('EngagementMetrics equality', () {
    const e1 = EngagementMetrics(
      watchTime: Duration(minutes: 10),
      sessionTime: Duration(minutes: 12),
      pauseCount: 2,
      seekCount: 3,
      percentageWatched: 0.85,
      completed: false,
    );
    const e2 = EngagementMetrics(
      watchTime: Duration(minutes: 10),
      sessionTime: Duration(minutes: 12),
      pauseCount: 2,
      seekCount: 3,
      percentageWatched: 0.85,
      completed: false,
    );
    const e3 = EngagementMetrics(
      watchTime: Duration(minutes: 20),
      sessionTime: Duration(minutes: 22),
      pauseCount: 0,
      seekCount: 1,
      percentageWatched: 1.0,
      completed: true,
    );

    test('same fields → equal', () {
      expect(e1, equals(e2));
    });

    test('different fields → not equal', () {
      expect(e1, isNot(equals(e3)));
    });

    test('same fields → same hashCode', () {
      expect(e1.hashCode, equals(e2.hashCode));
    });

    test('deduplicated correctly in a Set', () {
      final set = <EngagementMetrics>{}..addAll([e1, e2, e3]);
      expect(set, hasLength(2));
    });
  });

  // ===========================================================================
  // PerformanceMetrics — equality by operation + duration + timestamp
  // ===========================================================================
  group('PerformanceMetrics equality', () {
    final ts = DateTime(2025, 1, 1, 12, 0, 0);
    final p1 = PerformanceMetrics(
      operation: 'drm_init',
      duration: 42.5,
      timestamp: ts,
    );
    final p2 = PerformanceMetrics(
      operation: 'drm_init',
      duration: 42.5,
      timestamp: ts,
    );
    final p3 = PerformanceMetrics(
      operation: 'seek',
      duration: 10.0,
      timestamp: ts,
    );

    test('same fields → equal', () {
      expect(p1, equals(p2));
    });

    test('different operation → not equal', () {
      expect(p1, isNot(equals(p3)));
    });

    test('same fields → same hashCode', () {
      expect(p1.hashCode, equals(p2.hashCode));
    });

    test('deduplicated correctly in a Set', () {
      final set = {p1, p2, p3};
      expect(set, hasLength(2));
    });

    test('different duration → not equal', () {
      final other = PerformanceMetrics(
        operation: 'drm_init',
        duration: 99.0,
        timestamp: ts,
      );
      expect(p1, isNot(equals(other)));
    });
  });
}

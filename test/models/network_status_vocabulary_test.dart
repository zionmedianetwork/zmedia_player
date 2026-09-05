import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// H-06 drift guard, in the spirit of
/// `test/exceptions/error_category_vocabulary_test.dart` (H-01).
///
/// [ConnectionType] (`lib/src/models/network_status.dart`) is the vocabulary
/// `ConnectionType.fromString` parses out of the `"connectionType"` field of
/// the `onNetworkStatusChanged` MethodChannel event. There is no compiled
/// constant shared across Dart/Kotlin/Swift, and native Android/iOS code is
/// not part of this package's Dart test/build pipeline (see CLAUDE.md's
/// "Gaps" note), so nothing stops a native-side rename/typo from silently
/// falling back to [ConnectionType.unknown] at runtime. This test parses the
/// native connection-type literals as *text* and asserts they are all either
/// a real `fromString` case or one of the small, explicitly-accepted set of
/// values that are known to intentionally fall back to `.unknown` (see
/// [intentionalUnknownFallbackLiterals] below).
///
/// Also covers the `"quality"` field's vocabulary
/// (excellent/good/fair/poor/offline/unknown). Until issue #112,
/// `NetworkStatus.fromPlatform` never read `"quality"` at all — it
/// recomputed [NetworkQuality] itself from `downloadSpeed` via
/// [NetworkQuality.fromBandwidth] — so a drift in native's string literal
/// was unreachable dead data. Now `fromPlatform` honours `"quality"` when
/// it parses (falling back to `fromBandwidth` only when the key is absent
/// or unparseable, per [NetworkStatus.fromPlatform]'s doc comment), so a
/// native typo/rename would silently degrade to the
/// bandwidth-derived fallback instead of throwing — exactly the kind of
/// drift this file exists to catch.
void main() {
  const androidMonitorPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/NetworkMonitor.kt';
  const iosMonitorPath =
      'ios/zmedia_player/Sources/zmedia_player/NetworkMonitor.swift';

  String readRepoFile(String relativePath) {
    // `flutter test` runs with the package root as the working directory.
    final file = File(relativePath);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Expected to find $relativePath relative to the package root '
          '(current working directory: ${Directory.current.path}). If the '
          'file moved, update this test\'s path alongside it.',
    );
    return file.readAsStringSync();
  }

  /// Extracts the brace-matched body of the first function/block whose
  /// signature (exact text) is [signature].
  String extractBlockBody(String source, String signature) {
    final startIndex = source.indexOf(signature);
    expect(
      startIndex,
      greaterThanOrEqualTo(0),
      reason: 'Could not find the exact signature:\n  $signature\n'
          'Has it been renamed, reformatted, or removed? Update this test '
          'to match.',
    );

    final braceStart = source.indexOf('{', startIndex);
    expect(braceStart, greaterThanOrEqualTo(0));

    var depth = 0;
    var i = braceStart;
    for (; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    expect(i, lessThan(source.length),
        reason: 'Unbalanced braces while extracting the block — the '
            'brace-matching heuristic may be confused by a string/comment '
            'containing an unmatched brace.');

    return source.substring(braceStart, i + 1);
  }

  /// Extracts the paren-matched body of the first expression whose exact
  /// signature is [signature] and which opens with `(` rather than `{`
  /// (Kotlin's `offlineStatus()` is a single-expression function body:
  /// `= mapOf( ... )`, not a `{ ... }` block). [signature] must end with the
  /// literal `(` that opens the body (e.g. `"... = mapOf("`) — the empty
  /// `()` parameter list earlier in a typical signature would otherwise be
  /// matched instead.
  String extractParenBody(String source, String signature) {
    expect(signature.endsWith('('), isTrue,
        reason: 'extractParenBody signature must end with the opening "(" '
            'of the body being extracted.');

    final startIndex = source.indexOf(signature);
    expect(
      startIndex,
      greaterThanOrEqualTo(0),
      reason: 'Could not find the exact signature:\n  $signature\n'
          'Has it been renamed, reformatted, or removed? Update this test '
          'to match.',
    );

    final parenStart = startIndex + signature.length - 1;

    var depth = 0;
    var i = parenStart;
    for (; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    expect(i, lessThan(source.length),
        reason: 'Unbalanced parens while extracting the block — the '
            'paren-matching heuristic may be confused by a string/comment '
            'containing an unmatched paren.');

    return source.substring(parenStart, i + 1);
  }

  /// Literal values [ConnectionType.fromString] recognizes as a *specific*
  /// (non-`unknown`) member.
  final recognizedConnectionTypeLiterals = {
    'wifi',
    'cellular',
    'mobile',
    'ethernet',
    'bluetooth',
    'vpn',
    'none',
  };

  /// Literal values that are known, intentional native connection-type
  /// strings which `ConnectionType.fromString` has no dedicated case for and
  /// therefore falls back to [ConnectionType.unknown] for — not a bug, just
  /// not modeled at that granularity. `loopback` is iOS-only (local/
  /// simulator loopback interface); `unknown` is the literal both platforms
  /// already emit for a transport they don't otherwise recognize.
  const intentionalUnknownFallbackLiterals = {'loopback', 'unknown'};

  void expectOnlyKnownConnectionTypes(Set<String> literals, String context) {
    expect(literals, isNotEmpty,
        reason: '$context yielded no quoted connectionType literals at all '
            '— the extraction likely broke, not that there are none.');
    for (final literal in literals) {
      final recognized = recognizedConnectionTypeLiterals.contains(literal) ||
          intentionalUnknownFallbackLiterals.contains(literal);
      expect(
        recognized,
        isTrue,
        reason: '$context emits connectionType "$literal", which is neither '
            'a member ConnectionType.fromString recognizes '
            '(${recognizedConnectionTypeLiterals.join(", ")}) nor an '
            'explicitly-accepted intentional-fallback literal '
            '(${intentionalUnknownFallbackLiterals.join(", ")}). Either fix '
            'the native typo/rename, add a real ConnectionType case for it '
            'in lib/src/models/network_status.dart, or add it to '
            'intentionalUnknownFallbackLiterals here if falling back to '
            '.unknown is genuinely fine.',
      );
    }
  }

  group('ConnectionType native/Dart drift guard (H-06)', () {
    test(
        'Android getNetworkStatusFromCapabilities connectionType `when` '
        'block only returns known literals', () {
      final source = readRepoFile(androidMonitorPath);
      final body = extractBlockBody(source, 'val connectionType = when {');
      final literals = RegExp(r'"([a-z_]+)"')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expectOnlyKnownConnectionTypes(
        literals,
        'Android NetworkMonitor.getNetworkStatusFromCapabilities',
      );
    });

    test('Android offlineStatus() only returns a known literal', () {
      final source = readRepoFile(androidMonitorPath);
      // Single-expression function (`= mapOf( ... )`), not a `{ ... }`
      // block — see extractParenBody's doc comment.
      final body = extractParenBody(
          source, 'private fun offlineStatus(): Map<String, Any> = mapOf(');
      final match = RegExp(r'"connectionType" to "([a-z_]+)"').firstMatch(body);
      expect(match, isNotNull,
          reason: 'offlineStatus() should set a literal "connectionType" '
              'value directly.');
      expectOnlyKnownConnectionTypes(
        {match!.group(1)!},
        'Android NetworkMonitor.offlineStatus',
      );
    });

    test(
        'iOS estimateBandwidth(from:) connectionType tuple values are all '
        'known literals', () {
      final source = readRepoFile(iosMonitorPath);
      final body = extractBlockBody(
        source,
        'private func estimateBandwidth(from path: NWPath) -> '
        '(mbps: Double, connectionType: String) {',
      );
      final literals = RegExp(r'return\s*\([^,]+,\s*"([a-z_]+)"\)')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expectOnlyKnownConnectionTypes(
        literals,
        'iOS NetworkMonitor.estimateBandwidth(from:)',
      );
    });

    test('iOS offlineStatus() only returns a known literal', () {
      final source = readRepoFile(iosMonitorPath);
      final body = extractBlockBody(
          source, 'private func offlineStatus() -> [String: Any] {');
      final match = RegExp(r'"connectionType":\s*"([a-z_]+)"').firstMatch(body);
      expect(match, isNotNull,
          reason: 'offlineStatus() should set a literal "connectionType" '
              'value directly.');
      expectOnlyKnownConnectionTypes(
        {match!.group(1)!},
        'iOS NetworkMonitor.offlineStatus',
      );
    });

    test(
        'every ConnectionType with a real fromString case (other than the '
        'default .unknown) is reachable from at least one native '
        'implementation', () {
      final combined =
          readRepoFile(androidMonitorPath) + readRepoFile(iosMonitorPath);

      // `.unknown` is the default/fallback branch of `fromString`, not tied
      // to a specific literal, so it's excluded here (both native platforms
      // do emit a literal "unknown" string, but that's incidental, not what
      // this assertion is checking for).
      final typesWithDedicatedLiteral =
          ConnectionType.values.where((c) => c != ConnectionType.unknown);

      for (final type in typesWithDedicatedLiteral) {
        expect(
          combined.contains('"${type.name}"'),
          isTrue,
          reason: 'ConnectionType.${type.name} is never referenced as a '
              'quoted literal by either native NetworkMonitor. A connection '
              'type no native code can ever send is unreachable vocabulary '
              '— either wire it up natively or remove it from the Dart '
              'enum.',
        );
      }
    });
  });

  /// Literal values `NetworkQuality._tryParse` (via `NetworkQuality.values`'
  /// `.name`) recognizes. Unlike `ConnectionType.fromString`, there is no
  /// aliasing (no "mobile" -> "cellular" equivalent) and no permissive
  /// default: an unrecognized literal returns `null` from `_tryParse` and
  /// `NetworkStatus.fromPlatform` falls back to `NetworkQuality
  /// .fromBandwidth` instead — a silent behavior change, not a crash, which
  /// is exactly why native's literals must stay an exact match for this
  /// vocabulary.
  final recognizedQualityLiterals =
      NetworkQuality.values.map((q) => q.name).toSet();

  group('NetworkQuality native/Dart drift guard (issue #112)', () {
    void expectOnlyKnownQualities(Set<String> literals, String context) {
      expect(literals, isNotEmpty,
          reason: '$context yielded no quoted quality literals at all — '
              'the extraction likely broke, not that there are none.');
      for (final literal in literals) {
        expect(
          recognizedQualityLiterals.contains(literal),
          isTrue,
          reason: '$context emits quality "$literal", which '
              'NetworkQuality._tryParse does not recognize '
              '(${recognizedQualityLiterals.join(", ")}). '
              'NetworkStatus.fromPlatform would silently fall back to '
              'fromBandwidth for this value instead of throwing — fix the '
              'native typo/rename, or add a matching NetworkQuality member '
              'in lib/src/models/network_status.dart.',
        );
      }
    }

    test(
        'Android getNetworkStatusFromCapabilities quality `when` block '
        'only returns known literals', () {
      final source = readRepoFile(androidMonitorPath);
      final body = extractBlockBody(source, 'val quality = when {');
      final literals = RegExp(r'"([a-z_]+)"')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expectOnlyKnownQualities(
        literals,
        'Android NetworkMonitor.getNetworkStatusFromCapabilities',
      );
    });

    test('Android offlineStatus() only returns a known quality literal', () {
      final source = readRepoFile(androidMonitorPath);
      final body = extractParenBody(
          source, 'private fun offlineStatus(): Map<String, Any> = mapOf(');
      final match = RegExp(r'"quality" to "([a-z_]+)"').firstMatch(body);
      expect(match, isNotNull,
          reason: 'offlineStatus() should set a literal "quality" value '
              'directly.');
      expectOnlyKnownQualities(
        {match!.group(1)!},
        'Android NetworkMonitor.offlineStatus',
      );
    });

    test(
        'iOS getNetworkStatus(from:) quality switch only returns known '
        'literals', () {
      final source = readRepoFile(iosMonitorPath);
      final body = extractBlockBody(source, 'switch estimatedMbps {');
      final literals = RegExp(r'quality = "([a-z_]+)"')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expectOnlyKnownQualities(
        literals,
        'iOS NetworkMonitor.getNetworkStatus(from:)',
      );
    });

    test('iOS offlineStatus() only returns a known quality literal', () {
      final source = readRepoFile(iosMonitorPath);
      final body = extractBlockBody(
          source, 'private func offlineStatus() -> [String: Any] {');
      final match = RegExp(r'"quality":\s*"([a-z_]+)"').firstMatch(body);
      expect(match, isNotNull,
          reason: 'offlineStatus() should set a literal "quality" value '
              'directly.');
      expectOnlyKnownQualities(
        {match!.group(1)!},
        'iOS NetworkMonitor.offlineStatus',
      );
    });

    test(
        'every NetworkQuality value with a real _tryParse match (other '
        'than the unreachable .unknown) is reachable from at least one '
        'native implementation', () {
      final combined =
          readRepoFile(androidMonitorPath) + readRepoFile(iosMonitorPath);

      // Neither native monitor ever emits a literal "unknown" quality
      // string (it's used only as a local sentinel default for
      // lastNetworkQuality/lastQuality, to detect the first quality
      // change, never written into a status map's "quality" key) — so
      // .unknown is intentionally excluded, mirroring the ConnectionType
      // guard above.
      final qualitiesWithDedicatedLiteral =
          NetworkQuality.values.where((q) => q != NetworkQuality.unknown);

      for (final quality in qualitiesWithDedicatedLiteral) {
        expect(
          combined.contains('"${quality.name}"'),
          isTrue,
          reason: 'NetworkQuality.${quality.name} is never referenced as a '
              'quoted literal by either native NetworkMonitor. A quality '
              'value no native code can ever send is unreachable '
              'vocabulary — either wire it up natively or remove it from '
              'the Dart enum.',
        );
      }
    });
  });
}

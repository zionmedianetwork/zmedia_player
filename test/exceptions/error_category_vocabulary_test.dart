import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// H-01 drift guard.
///
/// [MediaErrorCategory] (`lib/src/core/exceptions.dart`) is the single
/// documented vocabulary both native platforms are supposed to emit as the
/// `"category"` field of the `onError` MethodChannel event (and, best
/// effort, as a `"category"` detail on a few synchronous method-call
/// failures). There is no compiled constant shared across Dart/Kotlin/Swift
/// — and native Android/iOS code is not part of this package's Dart
/// test/build pipeline (see CLAUDE.md's "Gaps" note) — so nothing stops the
/// three implementations from drifting apart silently. A native-side typo,
/// rename, or new category that isn't mirrored in Dart doesn't fail loudly;
/// [MediaErrorCategory.fromWireValue] just falls back to
/// [MediaErrorCategory.unknown] at runtime, exactly the kind of "test that
/// can pass forever while the feature is broken" this fix set out to avoid.
///
/// This test parses the native categorization functions as *text* and
/// asserts every quoted category literal they return is a real member of
/// [MediaErrorCategory]. It will fail the next time someone edits
/// `categorizeExoPlayerError`/`categorizeSynchronousLoadError` (Android) or
/// `categorize(_:)` (iOS) to emit a string that doesn't exist in
/// [MediaErrorCategory.values] — without needing a native build.
void main() {
  final validWireValues =
      MediaErrorCategory.values.map((c) => c.wireValue).toSet();

  const androidManagerPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt';
  const androidPluginPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/ZMediaPlayerPlugin.kt';
  const iosManagerPath =
      'ios/zmedia_player/Sources/zmedia_player/MediaPlayerManager.swift';

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

  /// Extracts the brace-matched body of the first function whose signature
  /// (exact text) is [functionSignature].
  String extractFunctionBody(String source, String functionSignature) {
    final startIndex = source.indexOf(functionSignature);
    expect(
      startIndex,
      greaterThanOrEqualTo(0),
      reason: 'Could not find the exact signature:\n  $functionSignature\n'
          'Has the function been renamed, reformatted, or removed? Update '
          'this test to match.',
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
        reason: 'Unbalanced braces while extracting function body — the '
            'brace-matching heuristic may be confused by a string/comment '
            'containing an unmatched brace.');

    return source.substring(braceStart, i + 1);
  }

  /// All `"ALL_CAPS"`-style quoted string literals in [body] — the shape
  /// every [MediaErrorCategory.wireValue] takes.
  Set<String> extractQuotedUppercaseLiterals(String body) {
    return RegExp(r'"([A-Z_]+)"')
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
  }

  void expectOnlyKnownCategories(Set<String> literals, String context) {
    expect(literals, isNotEmpty,
        reason: '$context returned no quoted category literals at all — '
            'the extraction likely broke, not that there are none.');
    for (final literal in literals) {
      expect(
        validWireValues,
        contains(literal),
        reason: '$context returns "$literal", which is not a member of '
            'MediaErrorCategory.values (${validWireValues.join(", ")}). '
            'Either fix the native typo/rename, or add the new category to '
            'MediaErrorCategory in lib/src/core/exceptions.dart and update '
            'MediaPlayer.mapNativeMediaError to handle it.',
      );
    }
  }

  group('MediaErrorCategory native/Dart drift guard', () {
    test('Android categorizeExoPlayerError only returns known categories', () {
      final source = readRepoFile(androidManagerPath);
      final body = extractFunctionBody(
        source,
        'private fun categorizeExoPlayerError(errorCode: Int): String {',
      );
      expectOnlyKnownCategories(
        extractQuotedUppercaseLiterals(body),
        'Android MediaPlayerInstance.categorizeExoPlayerError',
      );
    });

    test('Android categorizeSynchronousLoadError only returns known categories',
        () {
      final source = readRepoFile(androidPluginPath);
      final body = extractFunctionBody(
        source,
        'private fun categorizeSynchronousLoadError(e: Exception): String {',
      );
      expectOnlyKnownCategories(
        extractQuotedUppercaseLiterals(body),
        'Android ZMediaPlayerPlugin.categorizeSynchronousLoadError',
      );
    });

    test('iOS categorize(_:) only returns known categories', () {
      final source = readRepoFile(iosManagerPath);
      final body = extractFunctionBody(
        source,
        'private func categorize(_ error: NSError) -> (category: String, httpStatusCode: Int?) {',
      );
      expectOnlyKnownCategories(
        extractQuotedUppercaseLiterals(body),
        'iOS MediaPlayerInstance.categorize(_:)',
      );
    });

    test(
        'every MediaErrorCategory wire value is reachable from at least one '
        'native mapper', () {
      final combined = readRepoFile(androidManagerPath) +
          readRepoFile(androidPluginPath) +
          readRepoFile(iosManagerPath);

      for (final category in MediaErrorCategory.values) {
        expect(
          combined.contains('"${category.wireValue}"'),
          isTrue,
          reason:
              'MediaErrorCategory.${category.name} ("${category.wireValue}") '
              'is never referenced by either native implementation. A '
              'category no native code can ever send is exactly the kind of '
              'unreachable vocabulary entry H-01 was written to eliminate — '
              'either wire it up natively or remove it from the Dart enum.',
        );
      }
    });
  });
}

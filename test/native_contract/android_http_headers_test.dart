import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #127 regression guard, in the spirit of
/// `test/exceptions/error_category_vocabulary_test.dart` (H-01) and
/// `test/models/network_status_vocabulary_test.dart` (H-06): a Dart test that
/// parses the **native sources as text**, because nothing else in this
/// repository can see the defect it guards.
///
/// The defect: Media3's
/// `DefaultHttpDataSource.Factory.setDefaultRequestProperties(Map)` **replaces**
/// the factory's default request properties — it delegates to
/// `HttpDataSource.RequestProperties.clearAndSet`, which is `Map.clear()`
/// followed by `Map.putAll()` — it does **not** merge. Android's
/// `MediaPlayerManager.loadMediaItem` used to call it once per entry from
/// inside `httpHeaders.forEach { ... }`, so every call wiped the preceding
/// ones and only the **last** header of `MediaItem.httpHeaders` ever reached
/// the wire. An item carrying both `Authorization` and `Referer` sent
/// whichever the map happened to iterate last.
///
/// Why a source-text test rather than a normal one: every Dart test in this
/// suite mocks the `MethodChannel`, so the Dart side round-trips all headers
/// perfectly (see `test/models/media_item_test.dart`'s "toMap round-trips
/// every header" test) whether or not native then drops them. `flutter
/// analyze` cannot see it either (the payload is an untyped string-keyed map on
/// both sides of the channel), and native Kotlin/Swift is not part of this
/// package's Dart test/build pipeline (see CLAUDE.md's "Gaps" note). A
/// per-entry `setDefaultRequestProperties` call therefore produces zero
/// analyzer errors and zero failing tests while silently dropping
/// authentication headers at runtime. This file is the only automated thing
/// standing between that mistake and a release.
///
/// Note the deliberately narrow scope: the sibling *additive* API
/// `HttpMediaDrmCallback.setKeyRequestProperty(key, value)` is a genuine
/// per-entry setter and **is** correctly called in a loop
/// (`DrmHandler.kt`'s `applyCustomDataAsKeyRequestProperties`); only
/// `setDefaultRequestProperties` is replace-not-merge, so only it is guarded
/// here.
void main() {
  const androidManagerPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt';
  const androidDrmHandlerPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/DrmHandler.kt';

  /// The replace-not-merge API this file exists to police.
  const replacingSetter = 'setDefaultRequestProperties';

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

  /// Blanks out Kotlin comments and string literals, replacing their contents
  /// with spaces so every remaining character keeps its original offset (and
  /// therefore its original line number).
  ///
  /// Required, not cosmetic: the fixed `loadMediaItem` carries a prose comment
  /// that names both `$replacingSetter` and `forEach` while explaining exactly
  /// this defect. Scanning raw text would match that comment and report a
  /// failure against correct code. String literals are blanked for the same
  /// reason and because a `//` inside a URL literal would otherwise swallow
  /// the rest of a line and unbalance the brace matching below.
  String stripCommentsAndStrings(String source) {
    final out = StringBuffer();
    var i = 0;

    void emitBlanked(String text) {
      for (final unit in text.codeUnits) {
        // Preserve newlines so line numbers survive; blank everything else.
        out.writeCharCode(unit == 0x0a ? 0x0a : 0x20);
      }
    }

    while (i < source.length) {
      if (source.startsWith('//', i)) {
        final end = source.indexOf('\n', i);
        final stop = end == -1 ? source.length : end;
        emitBlanked(source.substring(i, stop));
        i = stop;
      } else if (source.startsWith('/*', i)) {
        final end = source.indexOf('*/', i + 2);
        final stop = end == -1 ? source.length : end + 2;
        emitBlanked(source.substring(i, stop));
        i = stop;
      } else if (source.startsWith('"""', i)) {
        final end = source.indexOf('"""', i + 3);
        final stop = end == -1 ? source.length : end + 3;
        emitBlanked(source.substring(i, stop));
        i = stop;
      } else if (source[i] == '"') {
        var j = i + 1;
        while (j < source.length && source[j] != '"') {
          if (source[j] == r'\') j++;
          j++;
        }
        final stop = j >= source.length ? source.length : j + 1;
        emitBlanked(source.substring(i, stop));
        i = stop;
      } else {
        out.write(source[i]);
        i++;
      }
    }

    return out.toString();
  }

  /// Brace-matches forward from [braceIndex] (which must be a `{`) and returns
  /// the body including both braces.
  String braceMatchedBody(String source, int braceIndex) {
    expect(source[braceIndex], '{');
    var depth = 0;
    var i = braceIndex;
    for (; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    expect(i, lessThan(source.length),
        reason: 'Unbalanced braces while extracting a block body — the '
            'brace-matching heuristic may be confused by source this test '
            'does not understand.');
    return source.substring(braceIndex, i + 1);
  }

  /// Index of the first `{` at or after [from], skipping one balanced `(...)`
  /// group if one comes first (`for (x in y) { ... }`). Returns -1 when the
  /// construct has no brace body at all (e.g. a single-statement `for`).
  int bodyBraceIndex(String source, int from) {
    var i = from;
    while (i < source.length && source[i].trim().isEmpty) {
      i++;
    }
    if (i >= source.length) return -1;
    if (source[i] == '(') {
      var depth = 0;
      for (; i < source.length; i++) {
        if (source[i] == '(') depth++;
        if (source[i] == ')') {
          depth--;
          if (depth == 0) {
            i++;
            break;
          }
        }
      }
      while (i < source.length && source[i].trim().isEmpty) {
        i++;
      }
    }
    if (i < source.length && source[i] == '{') return i;
    return -1;
  }

  /// Every loop construct in [source], as (description, body) pairs.
  ///
  /// Covers Kotlin's `for (...) { ... }` / `while (...) { ... }` statements
  /// and the collection-iteration lambdas a header map is realistically
  /// walked with (`forEach`, `forEachIndexed`, `onEach`, `map`, `mapNotNull`,
  /// `associate`, `filter`) in both their trailing-lambda (`.forEach { }`)
  /// and parenthesized (`.forEach({ })`) spellings.
  List<MapEntry<String, String>> loopBodies(String source) {
    final results = <MapEntry<String, String>>[];
    final pattern = RegExp(
      r'\b(for|while)\s*\(|'
      r'\.(forEach|forEachIndexed|onEach|map|mapNotNull|associate|filter)\s*[({]',
    );

    for (final match in pattern.allMatches(source)) {
      final keyword = match.group(1) ?? match.group(2)!;
      // Start scanning at the construct's keyword so bodyBraceIndex can skip
      // a `(...)` header/argument list if there is one.
      final searchFrom = match.end - 1;
      final braceIndex = source[searchFrom] == '{'
          ? searchFrom
          : bodyBraceIndex(source, searchFrom);
      if (braceIndex == -1) continue;
      final line = '\n'.allMatches(source.substring(0, braceIndex)).length + 1;
      results.add(
        MapEntry('`$keyword` loop whose body opens at line $line',
            braceMatchedBody(source, braceIndex)),
      );
    }
    return results;
  }

  group('Android HTTP header wiring (issue #127)', () {
    test(
        '$replacingSetter is never called from inside a loop body in '
        'MediaPlayerManager.kt', () {
      final source = stripCommentsAndStrings(readRepoFile(androidManagerPath));

      final bodies = loopBodies(source);
      expect(bodies, isNotEmpty,
          reason: 'Found no loop constructs at all in MediaPlayerManager.kt — '
              'the extraction almost certainly broke rather than the file '
              'genuinely having none. Fix this test before trusting it.');

      for (final entry in bodies) {
        expect(
          entry.value.contains(replacingSetter),
          isFalse,
          reason: 'Issue #127: $replacingSetter is called from inside a '
              '${entry.key} in MediaPlayerManager.kt.\n\n'
              'That method REPLACES the factory\'s default request '
              'properties (it delegates to '
              'HttpDataSource.RequestProperties.clearAndSet, i.e. Map.clear() '
              'then Map.putAll()) — it does NOT merge. Calling it once per '
              'entry means every call wipes the previous one and only the '
              'LAST header survives, so a MediaItem carrying both an '
              'Authorization and a Referer header silently sends only '
              'whichever the map iterated last.\n\n'
              'Pass the WHOLE header map in a single call instead:\n'
              '    DefaultHttpDataSource.Factory()\n'
              '        .setUserAgent(...)\n'
              '        .$replacingSetter(httpHeaders)\n\n'
              'The additive per-entry API is '
              'HttpMediaDrmCallback.setKeyRequestProperty(key, value) — that '
              'one is safe in a loop; this one is not.',
        );
      }
    });

    test('loadMediaItem passes the whole header map in exactly one call', () {
      final source = stripCommentsAndStrings(readRepoFile(androidManagerPath));

      // The exact per-instance overload, not the plugin-facing
      // `loadMediaItem(playerId, mediaItem, config)` delegator that appears
      // earlier in the file.
      const signature = 'fun loadMediaItem(mediaItem: Map<String, Any>, '
          'newConfig: Map<String, Any>? = null)';
      final signatureIndex = source.indexOf(signature);
      expect(signatureIndex, greaterThanOrEqualTo(0),
          reason: 'Could not find the exact signature:\n  $signature\n'
              'Has it been renamed or reformatted? Update this test '
              'alongside it.');
      final braceIndex =
          bodyBraceIndex(source, signatureIndex + signature.length);
      expect(braceIndex, greaterThanOrEqualTo(0));
      final body = braceMatchedBody(source, braceIndex);

      final calls = RegExp('\\.$replacingSetter\\s*\\(([^)]*)\\)')
          .allMatches(body)
          .toList();
      expect(
        calls.length,
        1,
        reason: 'Expected loadMediaItem to make exactly one '
            '$replacingSetter call (it replaces rather than merges — see '
            'issue #127), but found ${calls.length}.',
      );
      expect(
        calls.single.group(1)!.trim(),
        'httpHeaders',
        reason: 'Issue #127: loadMediaItem must hand the ENTIRE '
            'mediaItem["httpHeaders"] map to $replacingSetter in one call. '
            'Passing a freshly-built single-entry map (e.g. '
            '`mapOf(key to value)`) is the exact shape of the original '
            'defect — it discards every header but one.',
      );
    });

    test(
        '$replacingSetter is never called from inside a loop body in '
        'DrmHandler.kt', () {
      // DrmHandler already gets this right — buildRequestHeaders accumulates
      // custom headers plus the optional Bearer token into ONE map, which
      // buildHttpDataSourceFactory then hands over in a single call. This
      // asserts it stays that way; DRM licence requests are exactly where a
      // dropped Authorization header is most damaging.
      final source =
          stripCommentsAndStrings(readRepoFile(androidDrmHandlerPath));

      for (final entry in loopBodies(source)) {
        expect(
          entry.value.contains(replacingSetter),
          isFalse,
          reason: 'Issue #127: $replacingSetter is called from inside a '
              '${entry.key} in DrmHandler.kt. It replaces rather than merges, '
              'so only the last header would survive — accumulate into a '
              'single map (as buildRequestHeaders does) and make one call. '
              'Note setKeyRequestProperty(key, value) IS additive and is '
              'correctly loop-called elsewhere in this file.',
        );
      }
    });
  });
}

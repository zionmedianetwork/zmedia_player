import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Issue #126 drift guard.
///
/// [PlayerPauseReason] is the single documented vocabulary both natives emit
/// as the `pauseReason` key of the `onStateChanged` MethodChannel event.
/// Nothing compiled is shared across Dart/Kotlin/Swift, and the native code
/// is not part of this package's Dart test/build pipeline (CLAUDE.md's
/// "Gaps"), so the three implementations can drift apart in total silence: a
/// native typo, rename, or new reason that Dart does not know about does not
/// fail anything — [PlayerPauseReason.fromWireValue] just returns `null` and
/// `pauseReasonStream` goes quiet. That is precisely the failure #126 was:
/// `PlayerPauseReason.user` sat in the public API, exported and documented,
/// while no code path on either side could ever produce it.
///
/// `flutter analyze` cannot see this (it is a `Map<String, dynamic>` on both
/// sides of the channel) and the event tests cannot either (they inject the
/// payload themselves, so they only prove Dart parses what the test author
/// typed). Parsing the native sources as *text* is the only mechanism in
/// this repo that catches it — same technique as
/// `test/exceptions/error_category_vocabulary_test.dart` and
/// `test/models/network_status_vocabulary_test.dart`.
void main() {
  final validWireValues =
      PlayerPauseReason.values.map((r) => r.wireValue).toSet();

  const androidManagerPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt';
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
          "file moved, update this test's path alongside it.",
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

  /// Strips `//` line comments and `/* */` block comments.
  ///
  /// Necessary because both natives are heavily commented *about* this
  /// vocabulary — the comments quote the very literals under test, and a
  /// naive substring search would match its own documentation.
  String stripComments(String source) {
    return source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((line) {
      final commentIndex = line.indexOf('//');
      return commentIndex == -1 ? line : line.substring(0, commentIndex);
    }).join('\n');
  }

  /// Every `"..."` literal in [body] that is produced as the *result* of a
  /// mapping arm — i.e. what could end up on the wire.
  ///
  /// Deliberately narrow: it matches only literals on the right-hand side of
  /// a Kotlin `->` arm or a Swift `return`, so the surrounding prose,
  /// log tags and log messages in these heavily-commented functions are not
  /// mistaken for vocabulary.
  Set<String> extractEmittedLiterals(String body) {
    final withoutComments = stripComments(body);

    return RegExp(r'(?:->|return)\s*"([^"\\]*)"')
        .allMatches(withoutComments)
        .map((m) => m.group(1)!)
        .toSet();
  }

  void expectOnlyKnownReasons(Set<String> literals, String context) {
    expect(literals, isNotEmpty,
        reason: '$context produced no quoted literals at all — the '
            'extraction likely broke, not that there are none.');
    for (final literal in literals) {
      expect(
        validWireValues,
        contains(literal),
        reason: '$context emits "$literal" as a pauseReason, which is not a '
            'member of PlayerPauseReason.values '
            '(${validWireValues.join(", ")}). Dart\'s '
            'PlayerPauseReason.fromWireValue will return null for it and '
            'pauseReasonStream will silently stay quiet — the exact '
            '"declared but never emitted" drift issue #126 was. Either fix '
            'the native typo/rename, or add the member to PlayerPauseReason '
            'in lib/src/core/media_player.dart and document it in '
            'docs/api-reference/events.md.',
      );
    }
  }

  group('PlayerPauseReason native/Dart drift guard', () {
    test('Android onIsPlayingChanged only emits known pause reasons', () {
      final source = readRepoFile(androidManagerPath);
      final body = extractFunctionBody(
        source,
        'override fun onIsPlayingChanged(isPlaying: Boolean) {',
      );
      expectOnlyKnownReasons(
        extractEmittedLiterals(body),
        'Android MediaPlayerInstance.onIsPlayingChanged',
      );
    });

    test('iOS consumePauseReason() only emits known pause reasons', () {
      final source = readRepoFile(iosManagerPath);
      final body = extractFunctionBody(
        source,
        'private func consumePauseReason() -> String? {',
      );
      expectOnlyKnownReasons(
        extractEmittedLiterals(body),
        'iOS MediaPlayerInstance.consumePauseReason()',
      );
    });

    /// The other direction, and the one that would have caught #126 on the
    /// day it was introduced: a member no native code can ever send is dead
    /// public API.
    test('every PlayerPauseReason is reachable from at least one native', () {
      final combined = stripComments(readRepoFile(androidManagerPath)) +
          stripComments(readRepoFile(iosManagerPath));

      for (final reason in PlayerPauseReason.values) {
        expect(
          combined.contains('"${reason.wireValue}"'),
          isTrue,
          reason: 'PlayerPauseReason.${reason.name} '
              '("${reason.wireValue}") is never emitted by either native '
              'implementation. A reason no native code can send is exactly '
              'the unreachable-vocabulary defect issue #126 reported — '
              'either wire it up natively or remove it from the enum.',
        );
      }
    });

    /// Documents, and pins, the asymmetry the dartdoc and
    /// `docs/api-reference/events.md` promise: two reasons are Android-only
    /// because AVFoundation has no equivalent signal. If iOS ever gains
    /// them, this test fails and the docs get updated with the code.
    test('audioBecomingNoisy and remote are Android-only, as documented', () {
      final ios = stripComments(readRepoFile(iosManagerPath));

      for (final reason in const [
        PlayerPauseReason.audioBecomingNoisy,
        PlayerPauseReason.remote,
      ]) {
        expect(
          ios.contains('"${reason.wireValue}"'),
          isFalse,
          reason: 'iOS now emits "${reason.wireValue}", which every doc in '
              'this repo (PlayerPauseReason\'s dartdoc, AGENTS.md, '
              'docs/api-reference/events.md) still calls Android-only. '
              'Update them in the same change.',
        );
      }
    });

    /// Both natives must attach the key under the same name, or one
    /// platform's attribution silently never arrives.
    test('both natives use the "pauseReason" payload key', () {
      expect(
        stripComments(readRepoFile(androidManagerPath))
            .contains('"pauseReason"'),
        isTrue,
      );
      expect(
        stripComments(readRepoFile(iosManagerPath)).contains('"pauseReason"'),
        isTrue,
      );
    });
  });
}

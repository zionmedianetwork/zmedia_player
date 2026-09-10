import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the **unauthenticated notification-artwork fetch**,
/// in the same source-text style as
/// `test/native_contract/android_http_headers_test.dart` (issue #127) — and
/// for the same reason: nothing else in this repository can see the defect.
///
/// The defect: when a `MediaItem` has no `artworkUrl`, both platforms fall back
/// to extracting a video frame from the **media URL** and using it as the
/// notification / Now Playing artwork. That extraction issues its own HTTP
/// requests — `MediaMetadataRetriever` on Android,
/// `AVAssetImageGenerator`/`AVURLAsset` on iOS — which are entirely separate
/// from the ones the player makes for playback and are therefore *not* covered
/// by the playback data source's headers. Both sides sent none:
///
///  * Android hardcoded `retriever.setDataSource(url, emptyMap<String, String>())`
///    — an empty map chosen only to select the non-deprecated overload, with
///    the consequence (an unauthenticated request) missed.
///  * iOS built a bare `AVURLAsset(url: url)`, with no
///    `AVURLAssetHTTPHeaderFieldsKey`/`AVURLAssetHTTPCookiesKey`.
///
/// Against an authenticated or signed media URL (bearer token, signed
/// CloudFront cookie, a multi-header CDN credential) the frame fetch answers
/// 401/403 and the notification silently shows no artwork, while playback
/// itself is fine — so the symptom never points at the cause. Same defect
/// family as issue #127 ("headers don't reach every request"), one layer up.
///
/// Why a source-text test: `flutter analyze` sees only a `Map<String, dynamic>`
/// on both sides of the MethodChannel, every Dart test mocks the channel, and
/// native Kotlin/Swift is not part of this package's Dart test/build pipeline
/// (CLAUDE.md's "Gaps" note). The Dart half of the contract — that
/// `NotificationService.show()` actually puts `httpHeaders` on the payload — is
/// pinned by real tests in
/// `test/services/notification_state_sync_test.dart`; this file pins the native
/// half, which those cannot reach.
void main() {
  const androidNotificationHandlerPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/NotificationHandler.kt';
  const iosNotificationHandlerPath =
      'ios/zmedia_player/Sources/zmedia_player/NotificationHandler.swift';
  const iosAssetOptionsPath =
      'ios/zmedia_player/Sources/zmedia_player/AssetHTTPOptions.swift';
  const dartNotificationServicePath =
      'lib/src/services/notification_service.dart';

  /// The single payload key the whole contract hangs on. It is spelled once
  /// here and asserted on all three sides, because a rename on one side alone
  /// is exactly the silent, analyzer-invisible break CLAUDE.md calls out.
  const payloadKey = 'httpHeaders';

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

  /// Blanks out `//` and `/* */` comments and string literals, replacing their
  /// contents with spaces so every remaining character keeps its original
  /// offset (and therefore its line number). Valid for both Kotlin and Swift,
  /// which share this lexical syntax closely enough for the purpose.
  ///
  /// Required, not cosmetic: the *fixed* sources carry prose comments that name
  /// `emptyMap()` and `AVURLAsset(url:)` while explaining precisely this
  /// defect. Scanning raw text would match those comments and fail against
  /// correct code.
  String stripCommentsAndStrings(String source) {
    final out = StringBuffer();
    var i = 0;

    void emitBlanked(String text) {
      for (final unit in text.codeUnits) {
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

  /// Blanks comments but **keeps** string literals.
  ///
  /// The two strippers exist for two different classes of assertion:
  ///  * negative ones ("this construct must not appear") run against
  ///    [stripCommentsAndStrings], since a prose comment or a log-message
  ///    literal naming the old construct would otherwise fail correct code;
  ///  * positive ones ("this key/identifier must appear") run against this
  ///    one, because the things they look for — `mediaItem["httpHeaders"]`,
  ///    `"AVURLAssetHTTPHeaderFieldsKey"` — *are* string literals.
  String stripComments(String source) {
    final out = StringBuffer();
    var i = 0;

    void emitBlanked(String text) {
      for (final unit in text.codeUnits) {
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
      } else {
        out.write(source[i]);
        i++;
      }
    }

    return out.toString();
  }

  /// The `{ ... }` block that opens at or after [from], braces included.
  String blockBodyAfter(String source, int from, String what) {
    final braceIndex = source.indexOf('{', from);
    expect(braceIndex, greaterThanOrEqualTo(0),
        reason: 'Found no opening brace for $what — this test\'s extraction '
            'broke, or the declaration was reshaped. Fix the test before '
            'trusting it.');
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
        reason: 'Unbalanced braces while extracting $what.');
    return source.substring(braceIndex, i + 1);
  }

  /// Declaration header + body of the function whose declaration starts with
  /// [declarationPrefix] (e.g. `fun generateThumbnail(`).
  ({String signature, String body}) functionAt(
    String source,
    String declarationPrefix,
    String what,
  ) {
    final start = source.indexOf(declarationPrefix);
    expect(start, greaterThanOrEqualTo(0),
        reason: 'Could not find `$declarationPrefix` in $what. Was it renamed? '
            'Update this test alongside it — do not delete the assertion.');
    final braceIndex = source.indexOf('{', start);
    return (
      signature: source.substring(start, braceIndex),
      body: blockBodyAfter(source, start, what),
    );
  }

  group('Notification artwork frame extraction sends the item\'s headers', () {
    test(
        'Android generateThumbnail takes the header map and never hardcodes an '
        'empty one', () {
      final source =
          stripCommentsAndStrings(readRepoFile(androidNotificationHandlerPath));
      final fn = functionAt(
          source, 'fun generateThumbnail(', 'NotificationHandler.kt');

      expect(
        fn.signature.contains(payloadKey),
        isTrue,
        reason: 'generateThumbnail must accept the current item\'s '
            '`$payloadKey` map — the frame fetch is a separate HTTP request '
            'from playback and carries no credentials otherwise. Signature '
            'found:\n  ${fn.signature.trim()}',
      );

      final setDataSourceCalls =
          RegExp(r'setDataSource\s*\(([^)]*)\)').allMatches(fn.body).toList();
      expect(setDataSourceCalls, hasLength(1),
          reason: 'Expected exactly one setDataSource call in '
              'generateThumbnail, found ${setDataSourceCalls.length}.');
      final arguments = setDataSourceCalls.single.group(1)!;

      expect(
        arguments.contains(payloadKey),
        isTrue,
        reason: 'setDataSource must be handed the item\'s `$payloadKey`. '
            'Arguments found: `$arguments`.\n\n'
            'Passing a hardcoded `emptyMap<String, String>()` (the original '
            'defect) makes the notification-artwork frame fetch an '
            'UNAUTHENTICATED request: it 401/403s against a signed or '
            'token-authenticated media URL and the notification silently ends '
            'up with no artwork, while playback is unaffected.\n\n'
            'Keep the two-argument overload — the single-argument '
            'setDataSource(String) is deprecated — and pass '
            '`$payloadKey ?: emptyMap<String, String>()`, which still yields '
            'an empty map for an item that genuinely has no headers.',
      );
      expect(
        RegExp(r'setDataSource\s*\(\s*[^,)]+\s*\)').hasMatch(fn.body),
        isFalse,
        reason: 'setDataSource(String) — the single-argument overload — is '
            'deprecated. Use the (String, Map<String, String>) overload.',
      );
    });

    test('Android showNotification reads the "$payloadKey" payload key', () {
      final source =
          stripComments(readRepoFile(androidNotificationHandlerPath));
      final fn =
          functionAt(source, 'fun showNotification(', 'NotificationHandler.kt');
      expect(
        fn.body.contains('mediaItem["$payloadKey"]'),
        isTrue,
        reason: 'showNotification must read mediaItem["$payloadKey"] (sent by '
            'NotificationService.show()) — it is the only place the artwork '
            'path can obtain the item\'s credentials.',
      );
    });

    test(
        'iOS generateThumbnail takes the header map and builds its asset '
        'through makeAVURLAsset', () {
      final source =
          stripCommentsAndStrings(readRepoFile(iosNotificationHandlerPath));
      final fn = functionAt(
          source, 'func generateThumbnail(', 'NotificationHandler.swift');

      expect(
        fn.signature.contains(payloadKey),
        isTrue,
        reason: 'generateThumbnail must accept the current item\'s '
            '`$payloadKey` map. Signature found:\n  ${fn.signature.trim()}',
      );
      expect(
        fn.body.contains('makeAVURLAsset'),
        isTrue,
        reason: 'The thumbnail asset must be built by makeAVURLAsset (see '
            'AssetHTTPOptions.swift), the same helper the playback path uses, '
            'so the item\'s headers — and the Cookie -> '
            'AVURLAssetHTTPCookiesKey conversion signed-cookie CDNs need — '
            'apply to the frame fetch too.',
      );
      expect(
        // Negative lookbehind so the intended `makeAVURLAsset(url:` call — which
        // ends in the same characters — is not mistaken for the bare
        // constructor this forbids.
        RegExp(r'(?<!make)AVURLAsset\s*\(\s*url:').hasMatch(fn.body),
        isFalse,
        reason: 'A direct `AVURLAsset(url:)` in generateThumbnail is the '
            'original defect: the frame fetch then carries no headers and '
            '401/403s against an authenticated or signed media URL, leaving '
            'the notification silently artwork-less. Go through '
            'makeAVURLAsset instead.',
      );
    });

    test('iOS showNotification reads the "$payloadKey" payload key', () {
      final source = stripComments(readRepoFile(iosNotificationHandlerPath));
      final fn = functionAt(
          source, 'func showNotification(', 'NotificationHandler.swift');
      expect(
        fn.body.contains('mediaItem["$payloadKey"]'),
        isTrue,
        reason: 'showNotification must read mediaItem["$payloadKey"] (sent by '
            'NotificationService.show()).',
      );
    });

    test('makeAVURLAsset applies both the header fields and the cookies keys',
        () {
      final source = stripComments(readRepoFile(iosAssetOptionsPath));
      final fn =
          functionAt(source, 'func makeAVURLAsset(', 'AssetHTTPOptions.swift');
      expect(fn.body.contains('AVURLAssetHTTPHeaderFieldsKey'), isTrue,
          reason: 'Custom headers reach AVFoundation only through '
              'AVURLAssetHTTPHeaderFieldsKey.');
      expect(fn.body.contains('AVURLAssetHTTPCookiesKey'), isTrue,
          reason: 'A "Cookie" header must still be converted to '
              'AVURLAssetHTTPCookiesKey — AVFoundation drops a custom Cookie '
              'header on its out-of-process requests, which is what breaks '
              'signed-cookie CDN auth (403 / CoreMediaErrorDomain -12660).');
    });

    test('Dart sends the same "$payloadKey" key both natives read', () {
      final dart = readRepoFile(dartNotificationServicePath);
      expect(
        dart.contains("'$payloadKey':"),
        isTrue,
        reason: 'NotificationService.show() must put `$payloadKey` on the '
            '`mediaItem` payload. Without the Dart half, the native handlers '
            'read a key that is never sent and the artwork fetch is '
            'unauthenticated again — with no analyzer error and no other '
            'failing test to show for it.',
      );
    });
  });
}

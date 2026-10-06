import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #147 drift guard (Android PiP auto-enter + exit reporting).
///
/// Native has no automated tests, so the wiring is pinned by parsing the
/// Kotlin sources: the plugin must register ComponentActivity's user-leave-hint
/// and PiP-mode-changed listeners (and remove them on detach), PiP params must
/// be pushed outside explicit entry, and the pre-12 path must enter PiP.
void main() {
  const dir = 'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/';

  String read(String name) {
    final f = File('$dir$name');
    if (!f.existsSync()) throw StateError('missing $dir$name');
    return f
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//.*'), '');
  }

  final plugin = read('ZMediaPlayerPlugin.kt');
  final pip = read('PipHandler.kt');
  final manager = read('MediaPlayerManager.kt');

  test('plugin registers and removes both ComponentActivity PiP listeners', () {
    expect(plugin, contains('addOnUserLeaveHintListener'));
    expect(plugin, contains('addOnPictureInPictureModeChangedListener'));
    expect(plugin, contains('removeOnUserLeaveHintListener'));
    expect(plugin, contains('removeOnPictureInPictureModeChangedListener'));
    // Detach paths unregister.
    expect(
      RegExp(r'onDetachedFromActivity\(\)\s*\{\s*unregisterPipActivityListeners')
          .hasMatch(plugin),
      isTrue,
    );
    expect(plugin, contains('is androidx.activity.ComponentActivity'));
  });

  test('pre-12 user-leave-hint enters PiP; 12+ relies on auto-enter', () {
    expect(plugin, contains('Build.VERSION_CODES.S'));
    expect(plugin, contains('candidate.value.enterPip(null)'));
  });

  test('exit is reported (latch cleared) from the activity callback', () {
    expect(plugin, contains('onPictureInPictureModeChanged(false)'));
    expect(pip, contains('isInPipMode = isInPictureInPictureMode'));
  });

  test('PiP params are pushed outside explicit entry', () {
    expect(pip, contains('fun applyPipParams'));
    expect(pip, contains('setPictureInPictureParams'));
    expect(pip, contains('setAutoEnterEnabled(autoEnter)'));
    expect(pip, contains('setSeamlessResizeEnabled(true)'));
    expect(plugin, contains('refreshPipParams'));
    expect(manager, contains('onVideoSizeChanged'));
    expect(manager, contains('onPipRelevantChange?.invoke()'));
  });
}

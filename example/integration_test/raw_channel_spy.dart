import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';

/// One native -> Dart `zmedia_player` MethodChannel call, captured before any
/// Dart-side handler saw it.
class RawEvent {
  RawEvent(this.t, this.method, this.args);

  final DateTime t;
  final String method;
  final dynamic args;

  /// The call arguments as a map (empty when the payload is not a map).
  Map get map => args is Map ? args as Map : const {};

  @override
  String toString() =>
      '${t.toIso8601String().substring(11, 23)} $method ${_short(args)}';

  // Track lists are large and irrelevant to the checks; drop them from logs.
  static String _short(dynamic a) {
    if (a is Map) {
      final m = Map.of(a);
      for (final k in [
        'qualityTracks',
        'tracks',
        'subtitleTracks',
        'audioTracks',
      ]) {
        m.remove(k);
      }
      return m.toString();
    }
    return a.toString();
  }
}

/// Every `zmedia_player` event received from native since [RawChannelSpy.install].
final List<RawEvent> rawEvents = [];

/// Records raw native -> Dart events so checks can assert on what the native
/// layer actually emitted, before `MediaPlayer`'s error latch or optimistic
/// state updates can mask a native regression.
///
/// The generated `flutter test` entrypoint creates the
/// `IntegrationTestWidgetsFlutterBinding` before `main()` runs, so a binding
/// subclass cannot be substituted. Instead this wraps
/// `PlatformDispatcher.onPlatformMessage`, through which every native -> Dart
/// channel message passes. If no handler is installed yet, messages are
/// forwarded to `ui.channelBuffers`, which is where the framework's own
/// default handler delivers them.
class RawChannelSpy {
  RawChannelSpy._();

  static bool _installed = false;

  /// Initializes the integration binding and installs the spy (idempotent).
  static void install() {
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    if (_installed) return;
    _installed = true;
    final dispatcher = ui.PlatformDispatcher.instance;
    // ignore: deprecated_member_use
    final orig = dispatcher.onPlatformMessage;
    // ignore: deprecated_member_use
    dispatcher.onPlatformMessage = (
      String name,
      ByteData? data,
      ui.PlatformMessageResponseCallback? cb,
    ) {
      if (name == 'zmedia_player' && data != null) {
        try {
          final call = const StandardMethodCodec().decodeMethodCall(data);
          rawEvents.add(RawEvent(DateTime.now(), call.method, call.arguments));
        } catch (_) {
          // Not a method call we understand; still forwarded below.
        }
      }
      if (orig != null) {
        orig(name, data, cb);
      } else {
        ui.channelBuffers.push(name, data, cb ?? (_) {});
      }
    };
  }
}

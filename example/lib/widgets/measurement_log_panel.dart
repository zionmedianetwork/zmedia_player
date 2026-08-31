import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:zmedia_player/zmedia_player.dart';

/// Shared logging infrastructure for the Stage 7a measurement harness
/// (`example/lib/pages/measurement/`).
///
/// Stage 7a's whole purpose is producing numbers Stage 7b designs against.
/// Some of those numbers (decoder ceiling, memory, bandwidth) can only be
/// read with external tooling (`adb shell dumpsys media.resource_manager |
/// grep -c 'Name: OMX'` — NOT `dumpsys media.codec`, which returns nothing
/// on some devices, e.g. MediaTek — `adb shell dumpsys meminfo`, Android
/// Studio Network Profiler, Xcode Instruments).
/// This file's job is to make the in-app half of that correlation
/// trustworthy: every measurement phase emits a distinctive
/// `[7A-MEASURE] <event>:<phase> ...` line at start and end so the operator
/// can grep `adb logcat` (or the on-screen panel, on a release build where
/// console capture isn't guaranteed) and line it up against an external
/// reading taken at the same moment.

/// Formats one `[7A-MEASURE]` marker line.
///
/// `event` is one of `start`, `end`, `mark` or `result`. `phase` is a
/// stable kebab-case identifier for the measurement being run (e.g.
/// `decoder-ceiling`, `ttff`, `scroll-bandwidth-50`,
/// `live-offscreen-pause`). `fields` are appended as `key=value` pairs in
/// insertion order.
///
/// Examples:
/// ```
/// [7A-MEASURE] start:decoder-ceiling n=5
/// [7A-MEASURE] end:decoder-ceiling n=8 failed=true
/// [7A-MEASURE] end:ttff fixture=hls condition=cold ttffMs=842
/// ```
String formatMeasurementMarker({
  required String event,
  required String phase,
  Map<String, Object?> fields = const {},
}) {
  final buffer = StringBuffer('[7A-MEASURE] $event:$phase');
  for (final entry in fields.entries) {
    buffer.write(' ${entry.key}=${entry.value}');
  }
  return buffer.toString();
}

/// Best-effort extraction of the native error code (e.g.
/// `ERROR_CODE_DECODER_INIT_FAILED`) from a typed [MediaPlayerException],
/// shared by every measurement page that surfaces *why* a player died
/// rather than just reporting a bare `toString()`.
///
/// This directly backs the fix for the field defect this harness turned
/// up: decoder exhaustion fails the *renderer*, asynchronously, and the
/// operator needs the native error code — not just a pass/fail count — to
/// diagnose it from the on-screen log alone.
String? nativeErrorCodeOf(MediaPlayerException err) {
  return switch (err) {
    PlaybackException(:final errorCode) => errorCode,
    DrmException(:final errorCode) => errorCode,
    PlatformOperationException(:final code) => code,
    MediaLoadException() ||
    NetworkException() ||
    InvalidStateException() ||
    PlayerDisposedException() ||
    ConfigurationException() ||
    ProtocolMismatchException() ||
    // MediaPlayerException is sealed, so this arm is still required for
    // exhaustiveness even though the package no longer throws
    // OperationBusyException (it queues instead). The bare directive must be
    // the last comment line before the pattern: `// ignore:` applies only to
    // the line immediately following it.
    // ignore: deprecated_member_use
    OperationBusyException() =>
      null,
  };
}

/// Mixin providing a shared, bounded, on-screen + console event log for
/// measurement pages.
///
/// - [log] prints to the console (so `adb logcat` / Xcode console capture
///   it even when the on-screen panel isn't being watched) and mirrors the
///   line into [eventLog] (newest first) for on-screen display.
/// - [logMarker] is a thin wrapper over [log] +
///   [formatMeasurementMarker] for the distinctive `[7A-MEASURE]` lines
///   documented above.
/// - [safeSetState] centralizes the "am I still mounted / not torn down"
///   guard every page in this harness needs, since each page runs
///   asynchronous, multi-second measurement loops that must never touch
///   widget state after the page is popped.
mixin MeasurementLoggerMixin<T extends StatefulWidget> on State<T> {
  final List<String> eventLog = [];

  /// Set `true` at the top of `dispose()` (before any teardown) so any
  /// in-flight async step of a measurement loop can check it and bail out
  /// instead of calling `setState` after the State is gone.
  bool loggerDisposed = false;

  void log(String message) {
    debugPrint(message);
    if (!mounted || loggerDisposed) return;
    setState(() {
      eventLog.insert(0, message);
      if (eventLog.length > 300) eventLog.removeLast();
    });
  }

  void logMarker(
    String event,
    String phase, [
    Map<String, Object?> fields = const {},
  ]) {
    log(formatMeasurementMarker(event: event, phase: phase, fields: fields));
  }

  /// Runs [fn] only if the page is still alive. Use this to guard
  /// `setState` calls made from deep inside async measurement loops.
  void safeSetState(VoidCallback fn) {
    if (!mounted || loggerDisposed) return;
    setState(fn);
  }
}

/// Fixed-height, copyable event log panel shared by every measurement page.
///
/// The operator is reading a phone, not a debugger — so every line is
/// individually selectable ([SelectableText]) and the whole log can be
/// copied to the clipboard in chronological (oldest-first) order via the
/// toolbar button, ready to paste into a notes app or bug report.
class MeasurementLogPanel extends StatelessWidget {
  final List<String> eventLog;
  final String title;
  final double height;

  const MeasurementLogPanel({
    super.key,
    required this.eventLog,
    this.title = 'Event log (newest first)',
    this.height = 220,
  });

  Future<void> _copyAll(BuildContext context) async {
    final chronological = eventLog.reversed.join('\n');
    await Clipboard.setData(ClipboardData(text: chronological));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            IconButton(
              icon: const Icon(Icons.copy_all, size: 18),
              tooltip: 'Copy full log to clipboard',
              onPressed: eventLog.isEmpty ? null : () => _copyAll(context),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: height),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: eventLog.isEmpty
              ? const Text('No events yet.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: eventLog.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      eventLog[index],
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Small reusable intro/banner card matching the visual style used across
/// the example app's other manual-verification pages
/// (`network_status_page.dart`, `secure_output_page.dart`, `feed_page.dart`).
class MeasurementIntroCard extends StatelessWidget {
  final String text;

  const MeasurementIntroCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// Highlighted "operator instructions" card — used to call out the exact
/// external-tooling command(s) to run alongside a measurement.
class MeasurementOperatorCard extends StatelessWidget {
  final String title;
  final String text;

  const MeasurementOperatorCard({
    super.key,
    this.title = 'Operator steps (external tooling)',
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          SelectableText(text, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

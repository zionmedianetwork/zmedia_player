import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../data/sample_media.dart';

/// Device-testing harness for screen-capture protection (B-12):
/// - [MediaConfig.secureSurface] — opt-in initial value (left `false` here;
///   the toggle below drives [MediaController.setSecureSurface] instead so
///   the ON/OFF transition itself is exercised).
/// - [MediaController.setSecureSurface] — runtime toggle.
/// - [MediaController.screenCaptureStream] / `.screenCaptureStatus` — live
///   [ScreenCaptureStatus.isCaptured] readout.
/// - [MediaController.isSecureSurfaceEnabled] — current enabled state.
///
/// ### Why this page exists
/// This is the *only* place in the example app that calls
/// `setSecureSurface`/reads `screenCaptureStream` — see the class-level
/// warning in `lib/src/security/screen_capture_protection.dart`. Two other
/// features in this repo shipped broken because nothing in the example app
/// ever exercised them on hardware (`MediaListPlayer`'s off-screen-pause path,
/// and the Android media-notification action buttons). This page exists so
/// that does not happen a third time for B-12.
///
/// ### The platform asymmetry — read before testing
/// - **Android**: `setSecureSurface(true)` sets `FLAG_SECURE` on the host
///   window. This is a hard OS-level *block*: a screenshot or screen
///   recording comes back solid BLACK where the video is. There is nothing
///   to detect, so [ScreenCaptureStatus.isCaptured] never flips to `true` on
///   Android — `screenCaptureStream` simply never emits there.
/// - **iOS**: there is no OS-level block available to third-party apps.
///   `setSecureSurface(true)` only starts *detecting* capture via
///   `UIScreen.isCaptured`. The picture does **not** go black — that is
///   correct, expected behaviour, not a bug. The host app is responsible for
///   reacting to `isCaptured == true` itself; this page demonstrates that by
///   drawing a warning overlay on top of the video for as long as capture is
///   detected.
class SecureOutputPage extends StatefulWidget {
  const SecureOutputPage({super.key});

  @override
  State<SecureOutputPage> createState() => _SecureOutputPageState();
}

class _SecureOutputPageState extends State<SecureOutputPage> {
  late final MediaController _controller;
  StreamSubscription<ScreenCaptureStatus>? _captureSub;

  bool _isLoading = false;
  String? _error;
  bool _secureEnabled = false;
  bool _togglingSurface = false;
  ScreenCaptureStatus _captureStatus =
      const ScreenCaptureStatus(isCaptured: false);
  final List<String> _eventLog = [];

  bool get _isIOS => !kIsWeb && Platform.isIOS;
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'secure_output_demo',
      config: const MediaConfig(
        respectSafeArea: true,
        autoPlay: true,
        // Intentionally left false: the page's toggle drives
        // setSecureSurface() at runtime so the ON/OFF transition itself is
        // part of what gets exercised, not just the initial config value.
        secureSurface: false,
      ),
    );
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _controller.initialize();

      _captureSub?.cancel();
      _captureSub = _controller.screenCaptureStream.listen((status) {
        if (!mounted) return;
        setState(() => _captureStatus = status);
        _log('[SECURE] screenCaptureStream isCaptured=${status.isCaptured}');
      });

      await _controller.load(SampleMedia.forBiggerFun);

      setState(() {
        _secureEnabled = _controller.isSecureSurfaceEnabled;
        _captureStatus = _controller.screenCaptureStatus;
      });
      _log('[SECURE] initialized, secureSurface=$_secureEnabled '
          '(playerId=${_controller.playerId})');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleSecureSurface(bool enabled) async {
    setState(() => _togglingSurface = true);
    try {
      await _controller.setSecureSurface(enabled);
      if (mounted) {
        setState(() => _secureEnabled = _controller.isSecureSurfaceEnabled);
      }
      _log('[SECURE] setSecureSurface($enabled) succeeded');
    } catch (e) {
      _log('[SECURE] setSecureSurface($enabled) FAILED: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('setSecureSurface failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingSurface = false);
    }
  }

  void _log(String line) {
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      _eventLog.insert(0, line);
      if (_eventLog.length > 40) _eventLog.removeLast();
    });
  }

  @override
  void dispose() {
    _captureSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen-Capture Protection (B-12)')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _buildPlayerStack(),
                    ),
                    const SizedBox(height: 16),
                    _PlatformNotice(isIOS: _isIOS, isAndroid: _isAndroid),
                    const SizedBox(height: 16),
                    Text('Controls', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _ControlsCard(
                      enabled: _secureEnabled,
                      busy: _togglingSurface,
                      onChanged: _toggleSecureSurface,
                    ),
                    const SizedBox(height: 16),
                    Text('Live status',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _StatusCard(
                      secureEnabled: _secureEnabled,
                      captureStatus: _captureStatus,
                      isIOS: _isIOS,
                      isAndroid: _isAndroid,
                    ),
                    const SizedBox(height: 16),
                    Text('Test steps',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _TestStepsCard(isIOS: _isIOS, isAndroid: _isAndroid),
                    const SizedBox(height: 16),
                    Text('Event log',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 260),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _eventLog.isEmpty
                          ? const Text('No events yet.')
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _eventLog.length,
                              itemBuilder: (context, index) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _eventLog[index],
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontFamily: 'monospace'),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Builds the player with an iOS-only warning overlay demonstrating the
  /// intended app reaction to a detected capture: since iOS cannot black out
  /// the picture itself, the *host app* blanks/warns over its own UI for as
  /// long as [ScreenCaptureStatus.isCaptured] is true.
  Widget _buildPlayerStack() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: MediaPlayerWidget(
            controller: _controller,
            showControls: true,
            boxFit: BoxFit.contain,
            customControls: AdaptiveMediaControls(
              controller: _controller,
              title: 'Secure Output Demo',
            ),
            backgroundColor: Colors.black,
          ),
        ),
        if (_isIOS && _captureStatus.isCaptured)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.92),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off, color: Colors.white, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'Screen recording / mirroring detected.\n'
                        'Content hidden by the host app in response to '
                        'screenCaptureStream — this overlay, not the video '
                        'itself, is iOS\'s protection mechanism.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlatformNotice extends StatelessWidget {
  final bool isIOS;
  final bool isAndroid;
  const _PlatformNotice({required this.isIOS, required this.isAndroid});

  @override
  Widget build(BuildContext context) {
    final String text;
    if (isAndroid) {
      text = 'Running on ANDROID: setSecureSurface(true) sets FLAG_SECURE '
          'on this Activity\'s window. Expected result: a screenshot or '
          'screen recording taken while the toggle is ON comes back solid '
          'BLACK where the video is. There is no detection signal on '
          'Android — screenCaptureStream will stay silent (isCaptured is '
          'always false) even while protection is actively working.';
    } else if (isIOS) {
      text = 'Running on iOS: there is no FLAG_SECURE equivalent — iOS apps '
          'cannot block screen recording or AirPlay mirroring of their own '
          'content. setSecureSurface(true) only enables DETECTION via '
          'UIScreen.isCaptured. Expected result: the video keeps playing '
          'normally (does NOT go black) — that is correct behaviour, not a '
          'failure. When a screen recording or AirPlay mirror starts, '
          '"Live status" below flips isCaptured to true and the warning '
          'overlay above the video appears, demonstrating the reaction a '
          'real app should perform.';
    } else {
      text = 'Running on a desktop/web target: screen-capture protection is '
          'Android/iOS-only. Use a physical Android or iOS device to test '
          'this page.';
    }
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

class _ControlsCard extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _ControlsCard({
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: SwitchListTile(
        title: const Text('Secure output (setSecureSurface)'),
        subtitle: Text(
          enabled
              ? 'ON — protection active for this player'
              : 'OFF — default, no protection',
        ),
        value: enabled,
        onChanged: busy ? null : onChanged,
        secondary: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(enabled ? Icons.lock : Icons.lock_open),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool secureEnabled;
  final ScreenCaptureStatus captureStatus;
  final bool isIOS;
  final bool isAndroid;

  const _StatusCard({
    required this.secureEnabled,
    required this.captureStatus,
    required this.isIOS,
    required this.isAndroid,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: (isIOS && captureStatus.isCaptured)
          ? Theme.of(context).colorScheme.errorContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row('isSecureSurfaceEnabled', secureEnabled ? 'true' : 'false'),
            _Row(
              'screenCaptureStatus.isCaptured',
              isAndroid
                  ? '${captureStatus.isCaptured} (Android never emits — '
                      'always false by design)'
                  : '${captureStatus.isCaptured}',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestStepsCard extends StatelessWidget {
  final bool isIOS;
  final bool isAndroid;
  const _TestStepsCard({required this.isIOS, required this.isAndroid});

  @override
  Widget build(BuildContext context) {
    final List<String> steps;
    if (isAndroid) {
      steps = [
        'Confirm the video above is playing.',
        'Turn the "Secure output" switch ON.',
        'Take a screenshot (Power + Volume Down) OR start a screen '
            'recording from Quick Settings.',
        'Open the screenshot / recording: the area where the video was '
            'showing should be solid BLACK. Everything else in the app UI '
            '(this text, the switch, the app bar) is captured normally — '
            'only the player surface is protected.',
        'Turn the switch OFF, repeat: the screenshot/recording should now '
            'show the video normally.',
      ];
    } else if (isIOS) {
      steps = [
        'Confirm the video above is playing.',
        'Turn the "Secure output" switch ON.',
        'Open Control Center and start a Screen Recording (or start '
            'AirPlay/Screen Mirroring to an Apple TV or another display).',
        'Within a second or two, "Live status" below should flip '
            'isCaptured to true, and a black warning overlay should appear '
            'on top of the video in this app.',
        'The recording/mirror output itself still shows the video playing '
            'normally underneath where the overlay is drawn locally — '
            'that is expected: iOS cannot black out the frame buffer, only '
            'detect that capture is happening.',
        'Stop the recording/mirroring: isCaptured should flip back to '
            'false and the overlay should disappear.',
        'Turn the switch OFF and repeat: screenCaptureStream should stay '
            'silent regardless of recording state.',
      ];
    } else {
      steps = [
        'This feature is Android/iOS-only. Run the example app on a '
            'physical device (a simulator/emulator screen recording API may '
            'not reflect real hardware capture behaviour).',
      ];
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Error: $message',
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

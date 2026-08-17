import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates DRM configuration using the public API:
/// - [DrmConfig.widevine] for Android Widevine L1/L3
/// - [DrmConfig.fairplay] for iOS FairPlay (requires certificateUrl)
/// - [EzdrmConfig.widevine] / [EzdrmConfig.fairplay] for EZDRM service
/// - [CertificatePinningConfig] attached to [DrmConfig.certificatePinning]
/// - [MediaPlayer.drmSessionStream] for session state updates
/// - [MediaController.hasError] / [MediaController.error] /
///   [MediaController.errorStream] (C-01) for observing a DRM/license
///   failure through the documented facade — deliberately *without*
///   reaching into `controller.player` — so a license failure that arrives
///   asynchronously (see the "DRM Session" card below, driven separately via
///   `controller.player.drmSessionStream`) is also visible as an ordinary
///   [MediaController] error, exactly like a network or decoder failure.
///
/// IMPORTANT: DRM playback requires:
///   1. A real physical or emulator device (not desktop/web).
///   2. A valid content key from the same license server used to encrypt
///      the stream.  The placeholder URLs below will FAIL license acquisition;
///      replace them with your own DRM-protected stream + license server.
///   3. On Android, Widevine L1 requires a non-rooted device.
///   4. On iOS, FairPlay requires a valid FPS certificate and a signed
///      content key context.
///
/// This page does NOT attempt to load DRM content by default — it only shows
/// how to construct the [DrmConfig] objects and attach them to a [MediaItem].
/// Press "Attempt DRM Load" to actually try loading (this will fail without
/// real credentials).
class DrmPage extends StatefulWidget {
  const DrmPage({super.key});

  @override
  State<DrmPage> createState() => _DrmPageState();
}

class _DrmPageState extends State<DrmPage> {
  late final MediaController _controller;
  StreamSubscription<DrmSession>? _drmSessionSub;

  DrmSession? _drmSession;
  bool _isAttempting = false;
  String? _statusMessage;

  // Which DRM scheme to show
  _DrmSchemeDemo _selectedScheme = _DrmSchemeDemo.widevine;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'drm_demo',
      // respectSafeArea keeps the video below the status bar / notch in
      // landscape so content is never obscured. Set immersiveLandscape: true
      // instead if you want the status bar hidden in landscape.
      config: const MediaConfig(respectSafeArea: true),
    );
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      _drmSessionSub = _controller.player.drmSessionStream.listen((session) {
        if (mounted) setState(() => _drmSession = session);
      });
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Init error: $e');
    }
  }

  Future<void> _attemptDrmLoad() async {
    setState(() {
      _isAttempting = true;
      _statusMessage = 'Attempting DRM load...';
    });
    try {
      final item = _buildDrmMediaItem();
      await _controller.load(item);
      await _controller.play();
      if (mounted) {
        setState(() => _statusMessage = 'Load started — awaiting DRM session.');
      }
    } on DrmException catch (e) {
      if (mounted) {
        setState(() =>
            _statusMessage = 'DRM Error: ${e.message} (code: ${e.errorCode})');
      }
    } on MediaLoadException catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Load Error: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isAttempting = false);
    }
  }

  MediaItem _buildDrmMediaItem() {
    switch (_selectedScheme) {
      case _DrmSchemeDemo.widevine:
        return MediaItem(
          id: 'drm_widevine_demo',
          title: 'Widevine Protected Content (demo)',
          // Replace with a real Widevine-protected DASH/HLS stream URL
          url: 'https://REPLACE_WITH_REAL_WIDEVINE_STREAM.mpd',
          mimeType: 'application/dash+xml',
          drmConfig: DrmConfig.widevine(
            // Replace with your license server endpoint
            licenseUrl:
                'https://REPLACE_WITH_WIDEVINE_LICENSE_SERVER.example.com/license',
            headers: const {
              'Authorization': 'Bearer YOUR_TOKEN_HERE',
            },
          ),
        );

      case _DrmSchemeDemo.fairplay:
        return MediaItem(
          id: 'drm_fairplay_demo',
          title: 'FairPlay Protected Content (demo)',
          // Replace with a real FairPlay HLS stream URL
          url: 'https://REPLACE_WITH_REAL_FAIRPLAY_STREAM.m3u8',
          mimeType: 'application/x-mpegURL',
          drmConfig: DrmConfig.fairplay(
            // Replace with your FPS license server
            licenseUrl:
                'https://REPLACE_WITH_FAIRPLAY_LICENSE_SERVER.example.com/license',
            // Required for FairPlay — your FPS certificate endpoint
            certificateUrl:
                'https://REPLACE_WITH_FAIRPLAY_CERT.example.com/fps/cert',
            headers: const {
              'Authorization': 'Bearer YOUR_TOKEN_HERE',
            },
          ),
        );

      case _DrmSchemeDemo.ezdrm:
        return MediaItem(
          id: 'drm_ezdrm_demo',
          title: 'EZDRM Protected Content (demo)',
          url: 'https://REPLACE_WITH_REAL_EZDRM_STREAM.mpd',
          mimeType: 'application/dash+xml',
          drmConfig: DrmConfig.ezdrm(
            ezdrmConfig: EzdrmConfig.widevine(
              customerId: 'YOUR_EZDRM_CUSTOMER_ID',
              apiKey: 'YOUR_EZDRM_API_KEY',
              contentId: 'YOUR_CONTENT_ID',
            ),
          ),
        );

      case _DrmSchemeDemo.pinning:
        return MediaItem(
          id: 'drm_pinned_demo',
          title: 'Widevine + Certificate Pinning (demo)',
          url: 'https://REPLACE_WITH_REAL_WIDEVINE_STREAM.mpd',
          mimeType: 'application/dash+xml',
          drmConfig: DrmConfig.widevine(
            licenseUrl:
                'https://REPLACE_WITH_WIDEVINE_LICENSE_SERVER.example.com/license',
            certificatePinning: const CertificatePinningConfig(
              pins: {
                // Replace with your actual SHA-256 SPKI pin (64 lowercase hex chars)
                'REPLACE_WITH_LICENSE_SERVER_HOST.example.com': [
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ],
              },
              minimumPins: 2,
            ),
          ),
        );
    }
  }

  @override
  void dispose() {
    _drmSessionSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'DRM',
      controller: _controller,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warning banner
        _WarningBanner(),
        const SizedBox(height: 16),
        const SectionHeader('DRM Scheme'),
        _SchemeSelector(
          selected: _selectedScheme,
          onChanged: (s) => setState(() => _selectedScheme = s),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Config Preview'),
        _ConfigPreview(scheme: _selectedScheme),
        const SizedBox(height: 16),
        // C-01: MediaController's own error surface — hasError/error/
        // errorStream — so a DRM/license failure is visible through the
        // documented facade, not only via the lower-level DRM session card
        // below. Rebuilds on every MediaController.notifyListeners() call,
        // which now includes errorStream events (see MediaController).
        const SectionHeader('Controller Error State (C-01)'),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _ControllerErrorCard(
            hasError: _controller.hasError,
            error: _controller.error,
          ),
        ),
        const SizedBox(height: 16),
        // DRM Session status
        if (_drmSession != null) ...[
          const SectionHeader('DRM Session'),
          _DrmSessionCard(session: _drmSession!),
          const SizedBox(height: 8),
        ],
        if (_statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _statusMessage!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        FilledButton.icon(
          icon: _isAttempting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open),
          label: Text(_isAttempting ? 'Loading...' : 'Attempt DRM Load'),
          onPressed: _isAttempting ? null : _attemptDrmLoad,
        ),
        const SizedBox(height: 16),
        _DrmApiNote(),
      ],
    );
  }
}

enum _DrmSchemeDemo { widevine, fairplay, ezdrm, pinning }

class _WarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'DRM requires a real device and valid license server credentials. '
              'The placeholder URLs below WILL fail. Replace them with your own '
              'DRM-protected stream and license server before testing.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.orange.shade200),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchemeSelector extends StatelessWidget {
  final _DrmSchemeDemo selected;
  final ValueChanged<_DrmSchemeDemo> onChanged;

  const _SchemeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Widevine'),
          selected: selected == _DrmSchemeDemo.widevine,
          onSelected: (_) => onChanged(_DrmSchemeDemo.widevine),
        ),
        ChoiceChip(
          label: const Text('FairPlay'),
          selected: selected == _DrmSchemeDemo.fairplay,
          onSelected: (_) => onChanged(_DrmSchemeDemo.fairplay),
        ),
        ChoiceChip(
          label: const Text('EZDRM'),
          selected: selected == _DrmSchemeDemo.ezdrm,
          onSelected: (_) => onChanged(_DrmSchemeDemo.ezdrm),
        ),
        ChoiceChip(
          label: const Text('+ Cert Pinning'),
          selected: selected == _DrmSchemeDemo.pinning,
          onSelected: (_) => onChanged(_DrmSchemeDemo.pinning),
        ),
      ],
    );
  }
}

class _ConfigPreview extends StatelessWidget {
  final _DrmSchemeDemo scheme;
  const _ConfigPreview({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final lines = _configLines();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        lines,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  String _configLines() {
    switch (scheme) {
      case _DrmSchemeDemo.widevine:
        return '''DrmConfig.widevine(
  licenseUrl: 'https://license-server/license',
  headers: {'Authorization': 'Bearer token'},
)''';
      case _DrmSchemeDemo.fairplay:
        return '''DrmConfig.fairplay(
  licenseUrl: 'https://license-server/license',
  certificateUrl: 'https://cert-server/fps/cert', // required
  headers: {'Authorization': 'Bearer token'},
)''';
      case _DrmSchemeDemo.ezdrm:
        return '''DrmConfig.ezdrm(
  ezdrmConfig: EzdrmConfig.widevine(
    customerId: 'YOUR_CUSTOMER_ID',
    apiKey: 'YOUR_API_KEY',
    contentId: 'YOUR_CONTENT_ID',
  ),
)''';
      case _DrmSchemeDemo.pinning:
        return '''DrmConfig.widevine(
  licenseUrl: 'https://license-server/license',
  certificatePinning: CertificatePinningConfig(
    pins: {
      'license-server': ['<sha256-spki-pin-1>', '<sha256-spki-pin-2>'],
    },
    minimumPins: 2,
  ),
)''';
    }
  }
}

/// C-01 demo card: shows [MediaController.hasError] / [MediaController.error]
/// directly, proving a DRM session failure (which previously left
/// `PlaybackState.state` unchanged — see MediaPlayer._handleDrmSessionUpdate)
/// now reaches this facade the same way any other playback error does.
class _ControllerErrorCard extends StatelessWidget {
  final bool hasError;
  final MediaPlayerException? error;

  const _ControllerErrorCard({required this.hasError, required this.error});

  @override
  Widget build(BuildContext context) {
    if (!hasError || error == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade900.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade700),
        ),
        child: Text(
          'controller.hasError == false — no error observed yet.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.green.shade200),
        ),
      );
    }

    final e = error!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'controller.hasError == true (${e.runtimeType})',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade200,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            e.message,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.red.shade100),
          ),
          if (e is DrmException) ...[
            const SizedBox(height: 4),
            Text(
              'isLicenseError: ${e.isLicenseError}, '
              'isCertificateError: ${e.isCertificateError}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.red.shade100, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrmSessionCard extends StatelessWidget {
  final DrmSession session;
  const _DrmSessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(label: 'Session ID', value: session.id),
            InfoRow(label: 'State', value: session.state.name),
            if (session.errorMessage != null)
              InfoRow(label: 'Error', value: session.errorMessage!),
            if (session.license != null)
              InfoRow(
                label: 'License',
                value: session.license!.status.name,
              ),
          ],
        ),
      ),
    );
  }
}

class _DrmApiNote extends StatelessWidget {
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
      child: Text(
        'API: DrmConfig.widevine() / DrmConfig.fairplay(certificateUrl: required) '
        '/ DrmConfig.ezdrm() / EzdrmConfig.widevine() / EzdrmConfig.fairplay()\n'
        'Attach to MediaItem(drmConfig: ...). '
        'Monitor session detail via player.drmSessionStream (DrmSession state); '
        'monitor failure via controller.hasError / controller.error / '
        'controller.errorStream (C-01) — no need to reach into '
        'controller.player for that.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

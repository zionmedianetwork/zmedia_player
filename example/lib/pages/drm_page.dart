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
///      the stream.  The Widevine/FairPlay/EZDRM/pinning placeholder URLs
///      below are rejected by [InputValidator] before `load()` ever reaches
///      native code (they demonstrate B-11 URL validation, not a DRM
///      failure) — replace them with your own DRM-protected stream + license
///      server to exercise real DRM with those schemes.
///   3. On Android, Widevine L1 requires a non-rooted device.
///   4. On iOS, FairPlay requires a valid FPS certificate and a signed
///      content key context.
///
/// Three additional cases below use a real, verified-reachable DASH test
/// stream (Axinom's public test vectors — see
/// https://github.com/Axinom/public-test-vectors) so `load()`/`play()`
/// actually pass validation and reach native DRM code on device, unlike the
/// placeholder cases:
/// - **"ClearKey — Bad License (C-01)"** points at a syntactically valid but
///   permanently unreachable license URL (`https://license.invalid/...`,
///   using the IANA-reserved `.invalid` TLD — RFC 2606/6761 — so it never
///   resolves and the failure is deterministic forever, not dependent on any
///   third party's uptime). This is the case to use to verify C-01 on a real
///   device: [MediaController.hasError] should become `true` once license
///   acquisition fails. On Android this failure is discovered *asynchronously*
///   by ExoPlayer's generic player-error callback (`onPlayerError`), not by
///   native `DrmHandler` — see the "PlayReady" case below for the contrast.
/// - **"ClearKey — Working License (bonus)"** uses Axinom's own
///   publicly-documented license server + content key for this exact test
///   vector, so it should play successfully — see the in-page note for a
///   caveat observed while wiring this up (that server's TLS certificate was
///   found expired at the time of writing, which would itself cause a
///   TLS/certificate failure independent of the key material being correct).
/// - **"PlayReady — Unsupported Device (C-01 path)"** exercises the
///   *synchronous* half of C-01 directly: on Android, `DrmHandler.
///   validateDrmConfig` calls `isPlayReadySupported()`
///   (`FrameworkMediaDrm.newInstance(PLAYREADY_UUID)`) before the media
///   source is ever built. On any device without a PlayReady CDM — confirmed
///   via `dumpsys media.drm` on the target test device, which reports none —
///   this fails immediately and calls `notifyDrmError()`, which is the
///   *only* route into `onDrmSessionUpdate` → `MediaPlayer.
///   _handleDrmSessionUpdate`, the exact method C-01 (commit `788291c`)
///   changed to set `PlayerState.error`. This is unlike the ClearKey
///   bad-license case above, which — because native `DrmHandler` has no
///   `DrmSessionEventListener` wired up (see finding C-08) — never reaches
///   `notifyDrmError` for a *live* license-fetch failure and instead surfaces
///   through ExoPlayer's generic `onPlayerError` path. Both make
///   `controller.hasError` become `true`, but only the PlayReady case here
///   actually walks C-01's own code path. (On iOS, PlayReady is rejected the
///   same way, at the very top of `DrmHandler.processDrmConfig` — scheme !=
///   "fairplay" — so this case is cross-platform.)
///
/// This page does NOT attempt to load DRM content by default — it only shows
/// how to construct the [DrmConfig] objects and attach them to a [MediaItem].
/// Press "Attempt DRM Load" to actually try loading.
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

      case _DrmSchemeDemo.clearKeyBadLicense:
        // REAL, verified-reachable (HTTP 200, carries a ClearKey
        // ContentProtection element) DASH ClearKey test stream — Axinom's
        // public test vectors, "v7-MultiDRM-SingleKey":
        // https://github.com/Axinom/public-test-vectors
        //
        // Unlike the placeholder cases above, this URL passes
        // InputValidator (real https host with valid syntax), so
        // load()/play() actually reach native code and playback attempts to
        // start. DrmScheme.clearkey is in the public API and Android's
        // DrmHandler maps "clearkey" -> C.CLEARKEY_UUID (ClearKey is not
        // supported on iOS — DrmHandler.swift only accepts "fairplay" — so
        // this case is Android-only; on iOS it fails immediately with
        // "Only FairPlay DRM is supported on iOS", which is also a valid,
        // if less interesting, C-01 signal).
        return MediaItem(
          id: 'drm_clearkey_bad_license_demo',
          title: 'ClearKey — Real Stream, Bad License (C-01)',
          url:
              'https://media.axprod.net/TestVectors/v7-MultiDRM-SingleKey/Manifest_1080p_ClearKey.mpd',
          mimeType: 'application/dash+xml',
          drmConfig: const DrmConfig(
            scheme: DrmScheme.clearkey,
            // `.invalid` is an IANA-reserved TLD (RFC 2606 / RFC 6761)
            // guaranteed to NEVER resolve — this fails deterministically,
            // forever, without depending on any third-party server's
            // uptime or certificate lifecycle. It is well-formed enough
            // (https + syntactically valid host) to pass InputValidator;
            // the failure only happens at request time, inside native DRM
            // code, once ExoPlayer actually tries to fetch a license.
            licenseUrl: 'https://license.invalid/AcquireLicense',
          ),
        );

      case _DrmSchemeDemo.clearKeyWorkingLicense:
        // Bonus (not required for C-01): same real test stream as above,
        // paired with Axinom's own publicly-documented license server +
        // key/entitlement header for this exact test vector (key ID
        // 9eb4050d-e44b-4802-932e-27d75083e266, content key
        // FmY0xnWCPCNaSpRG+tUuTQ==) from TestVectors-v7-v8.md in the same
        // repo — not guessed. See the in-page note for a caveat: this
        // server's TLS certificate was observed EXPIRED while wiring this
        // up, so this case may currently fail too (with a TLS/certificate
        // error, distinct from a license-content error) until Axinom
        // renews it.
        return MediaItem(
          id: 'drm_clearkey_working_license_demo',
          title: 'ClearKey — Real Stream, Documented License (bonus)',
          url:
              'https://media.axprod.net/TestVectors/v7-MultiDRM-SingleKey/Manifest_1080p_ClearKey.mpd',
          mimeType: 'application/dash+xml',
          drmConfig: const DrmConfig(
            scheme: DrmScheme.clearkey,
            licenseUrl:
                'https://drm-clearkey-testvectors.axtest.net/AcquireLicense',
            headers: {
              'X-AxDRM-Message':
                  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjoxLCJjb21fa2V5X2lkIjoiYjMzNjRlYjUtNTFmNi00YWUzLThjOTgtMzNjZWQ1ZTMxYzc4IiwibWVzc2FnZSI6eyJ0eXBlIjoiZW50aXRsZW1lbnRfbWVzc2FnZSIsInZlcnNpb24iOjIsImxpY2Vuc2UiOnsiYWxsb3dfcGVyc2lzdGVuY2UiOnRydWV9LCJjb250ZW50X2tleXNfc291cmNlIjp7ImlubGluZSI6W3siaWQiOiI5ZWI0MDUwZC1lNDRiLTQ4MDItOTMyZS0yN2Q3NTA4M2UyNjYiLCJlbmNyeXB0ZWRfa2V5IjoibEszT2pITFlXMjRjcjJrdFI3NGZudz09IiwidXNhZ2VfcG9saWN5IjoiUG9saWN5IEEifV19LCJjb250ZW50X2tleV91c2FnZV9wb2xpY2llcyI6W3sibmFtZSI6IlBvbGljeSBBIiwicGxheXJlYWR5Ijp7Im1pbl9kZXZpY2Vfc2VjdXJpdHlfbGV2ZWwiOjE1MCwicGxheV9lbmFibGVycyI6WyI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciXX19XX19.W2FbPDSDaq-LeeLfOnbpTMa-zCmXh8RLChEVDYvdcVw',
            },
          ),
        );

      case _DrmSchemeDemo.playReadyUnsupportedDevice:
        // Same real, verified-reachable Axinom test stream as the ClearKey
        // cases above — the point here isn't decoding it (PlayReady is never
        // going to succeed against a ClearKey-encrypted stream), it's that
        // the stream URL passes InputValidator so load() actually reaches
        // native code. DrmScheme.playready maps to native "playready", and
        // native DrmHandler.validateDrmConfig checks isPlayReadySupported()
        // — FrameworkMediaDrm.newInstance(PLAYREADY_UUID) — SYNCHRONOUSLY,
        // before any media source or license request is built. On a device
        // with no PlayReady CDM (confirmed via `dumpsys media.drm` on the
        // target test device), that check fails immediately and calls
        // notifyDrmError(), which is the only route into
        // onDrmSessionUpdate -> MediaPlayer._handleDrmSessionUpdate — C-01's
        // actual fix (commit 788291c). Unlike the ClearKey bad-license case,
        // no network round-trip happens at all: the license URL below is
        // syntactically valid (https + real host format) so it clears
        // InputValidator, but it is NEVER contacted.
        return MediaItem(
          id: 'drm_playready_unsupported_demo',
          title: 'PlayReady — Unsupported Device (C-01 path)',
          url:
              'https://media.axprod.net/TestVectors/v7-MultiDRM-SingleKey/Manifest_1080p_ClearKey.mpd',
          mimeType: 'application/dash+xml',
          drmConfig: const DrmConfig(
            scheme: DrmScheme.playready,
            // Never actually contacted — validateDrmConfig() fails on the
            // device-support check before any request is made. Valid
            // https + hostname syntax only so it clears InputValidator and
            // the failure genuinely happens on the native side, not here.
            licenseUrl: 'https://playready-license.example.com/license',
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
        const SectionHeader('What To Expect'),
        _ExpectedOutcomeCard(scheme: _selectedScheme),
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

enum _DrmSchemeDemo {
  widevine,
  fairplay,
  ezdrm,
  pinning,

  /// Real, verified-reachable ClearKey stream + deliberately-unreachable
  /// license URL. This is the case that exercises C-01 on a real device —
  /// see the class-level dartdoc above and `_buildDrmMediaItem`.
  clearKeyBadLicense,

  /// Bonus: same real stream, paired with Axinom's own documented
  /// (not guessed) license server + key for this test vector.
  clearKeyWorkingLicense,

  /// Real, verified-reachable stream + [DrmScheme.playready], on a device
  /// confirmed to have no PlayReady CDM. This fails synchronously inside
  /// native `DrmHandler.validateDrmConfig`, which is the only path that
  /// actually calls `notifyDrmError()` → `onDrmSessionUpdate` →
  /// `MediaPlayer._handleDrmSessionUpdate` — C-01's own code path, as
  /// opposed to the generic player-error path the ClearKey bad-license case
  /// above uses. See the class-level dartdoc above.
  playReadyUnsupportedDevice,
}

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
              'DRM requires a real device (not desktop/web). The Widevine / '
              'FairPlay / EZDRM / Pinning cases use PLACEHOLDER URLs that are '
              'rejected by input validation before load() ever reaches native '
              'code — replace them with your own DRM-protected stream + '
              'license server to exercise those schemes for real. The two '
              'ClearKey cases and the PlayReady case use a real, '
              'verified-reachable test stream instead, so they actually '
              'reach native DRM code on device — see "What To Expect" below '
              'for what each one demonstrates.',
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
        ChoiceChip(
          avatar: const Icon(Icons.error_outline, size: 18),
          label: const Text('ClearKey — Bad License (C-01)'),
          selected: selected == _DrmSchemeDemo.clearKeyBadLicense,
          onSelected: (_) => onChanged(_DrmSchemeDemo.clearKeyBadLicense),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('ClearKey — Working License (bonus)'),
          selected: selected == _DrmSchemeDemo.clearKeyWorkingLicense,
          onSelected: (_) => onChanged(_DrmSchemeDemo.clearKeyWorkingLicense),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.report_gmailerrorred, size: 18),
          label: const Text('PlayReady — Unsupported Device (C-01 path)'),
          selected: selected == _DrmSchemeDemo.playReadyUnsupportedDevice,
          onSelected: (_) =>
              onChanged(_DrmSchemeDemo.playReadyUnsupportedDevice),
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
      case _DrmSchemeDemo.clearKeyBadLicense:
        return '''// stream: media.axprod.net/.../Manifest_1080p_ClearKey.mpd
// (real, verified 200 + ClearKey ContentProtection)
DrmConfig(
  scheme: DrmScheme.clearkey,
  licenseUrl: 'https://license.invalid/AcquireLicense',
  // .invalid never resolves (RFC 2606/6761) -> deterministic failure
)''';
      case _DrmSchemeDemo.clearKeyWorkingLicense:
        return '''// same real stream as above
DrmConfig(
  scheme: DrmScheme.clearkey,
  licenseUrl:
      'https://drm-clearkey-testvectors.axtest.net/AcquireLicense',
  headers: {'X-AxDRM-Message': '<Axinom-documented JWT, see source>'},
)''';
      case _DrmSchemeDemo.playReadyUnsupportedDevice:
        return '''// same real stream as above (never decoded — see below)
DrmConfig(
  scheme: DrmScheme.playready,
  licenseUrl: 'https://playready-license.example.com/license',
  // never contacted: validateDrmConfig() fails synchronously on
  // isPlayReadySupported() before any request is built
)''';
    }
  }
}

/// Describes, per selected [_DrmSchemeDemo] case, what a device tester
/// should expect to observe — separate from [_ConfigPreview] (which shows
/// *what's configured*) so the "why" and "what happens next" is legible at
/// a glance without reading source comments.
class _ExpectedOutcomeCard extends StatelessWidget {
  final _DrmSchemeDemo scheme;
  const _ExpectedOutcomeCard({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final (String text, Color color) = switch (scheme) {
      _DrmSchemeDemo.widevine ||
      _DrmSchemeDemo.fairplay ||
      _DrmSchemeDemo.ezdrm ||
      _DrmSchemeDemo.pinning =>
        (
          'Placeholder URL — InputValidator throws ConfigurationException '
              'synchronously inside load(), before native code or DRM is ever '
              'reached. Playback never starts. controller.hasError stays '
              'false (this demonstrates B-11 validation, not C-01).',
          Colors.blueGrey,
        ),
      _DrmSchemeDemo.clearKeyBadLicense => (
          'REQUIRED case for C-01. load()/play() succeed (the stream URL '
              'is real and passes validation) and playback attempts to start. '
              'The license request to license.invalid can never resolve, so '
              'license acquisition fails asynchronously. Expect: '
              'controller.hasError flips to TRUE, controller.error is a '
              'DrmException naming a DRM/license failure (not a generic '
              'error) — and video must NOT start playing. On Android this is '
              'currently surfaced via the same player-error path as other '
              'network failures (category DRM) rather than the '
              'onDrmSessionUpdate path, since native DrmHandler does not yet '
              'forward a live ExoPlayer DRM session error back through '
              'notifyDrmError() — either way, MediaController.hasError still '
              'flips correctly, which is what C-01 guarantees.',
          Colors.redAccent,
        ),
      _DrmSchemeDemo.clearKeyWorkingLicense => (
          'Bonus. Uses Axinom\'s own documented license server + key for '
              'this stream, so playback SHOULD succeed with no error. Caveat '
              'observed while wiring this up: drm-clearkey-testvectors.axtest.net '
              'was serving an EXPIRED TLS certificate, which — on a device '
              'enforcing normal certificate validation — will itself cause a '
              'DRM/network failure independent of the key material being '
              'correct. If Axinom has since renewed it, this case should play '
              'successfully instead.',
          Colors.green,
        ),
      _DrmSchemeDemo.playReadyUnsupportedDevice => (
          'REQUIRED case for C-01\'s SYNCHRONOUS path — this is the one that '
              'actually walks _handleDrmSessionUpdate, not the generic '
              'player-error path. The stream URL is real and passes '
              'validation, but native DrmHandler.validateDrmConfig calls '
              'isPlayReadySupported() before building any media source or '
              'sending a single byte to the license URL above. On this test '
              'device (confirmed via dumpsys media.drm: no PlayReady CDM) '
              'that check fails immediately, which is the ONLY call site that '
              'invokes notifyDrmError() -> onDrmSessionUpdate -> '
              'MediaPlayer._handleDrmSessionUpdate — the exact method C-01 '
              '(commit 788291c) changed to set PlayerState.error. Contrast '
              'with "ClearKey — Bad License" above: that case reaches '
              'hasError too, but via ExoPlayer\'s generic onPlayerError '
              'callback, because native DrmHandler has no live '
              'DrmSessionEventListener wired up (finding C-08) — this one is '
              'the real thing. Expect: controller.hasError flips to TRUE '
              'almost instantly (no network round-trip), controller.error is '
              'a DrmException with message "PlayReady DRM is not supported '
              'on this device", and video must NOT start playing. Watch the '
              'isLicenseError/isCertificateError flags on the card below: '
              'both will likely read FALSE here too, since '
              '_handleDrmSessionUpdate only sets them via a substring match '
              'on the error text ("license"/"certificate") and this message '
              'contains neither — but per C-08, that substring match is only '
              'ever performed on THIS path. On the ClearKey path above, '
              'those same flags are hard-coded false unconditionally, '
              'because the generic player-error handler never attaches them '
              'at all. Same false value, very different reason — that\'s the '
              'contrast this case exists to make visible.',
          Colors.deepOrangeAccent,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: color.withValues(alpha: 0.95)),
      ),
    );
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
        '/ DrmConfig.ezdrm() / EzdrmConfig.widevine() / EzdrmConfig.fairplay() / '
        'plain DrmConfig(scheme: DrmScheme.clearkey, ...) for ClearKey.\n'
        'Attach to MediaItem(drmConfig: ...). '
        'Monitor session detail via player.drmSessionStream (DrmSession state); '
        'monitor failure via controller.hasError / controller.error / '
        'controller.errorStream (C-01) — no need to reach into '
        'controller.player for that.\n'
        'The two ClearKey cases and the PlayReady case use a real DASH test '
        'stream from Axinom\'s public test vectors '
        '(github.com/Axinom/public-test-vectors) — the only cases here that '
        'pass validation and reach native DRM code on device. Select '
        '"ClearKey — Bad License (C-01)" and press "Attempt DRM Load" to '
        'verify C-01 via the generic player-error path; select "PlayReady — '
        'Unsupported Device (C-01 path)" to verify C-01 via its own '
        'synchronous _handleDrmSessionUpdate code path instead. Either way, '
        'video must not start, and controller.hasError must become true.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

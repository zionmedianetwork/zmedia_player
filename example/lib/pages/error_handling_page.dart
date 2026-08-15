import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates error handling and the [MediaPlayerException] hierarchy:
/// - [MediaLoadException] — bad URL / HTTP error
/// - [NetworkException] — connectivity issues (bad host / offline)
/// - [PlaybackException] — codec / container / decoding failures
/// - [DrmException] — license / certificate failures (NOT provokable here,
///   see the note below)
/// - [PlayerState.error] surfaced via [MediaController.state]
/// - [PlaybackState.errorMessage] for human-readable description
/// - [MediaPlayer.errorStream] — the typed, category-tagged error stream
///   added in Phase 3 (see `mapNativeMediaError` / `MediaErrorCategory` in
///   `lib/src/core/exceptions.dart`)
///
/// ### Why `errorStream` is the primary signal on this page
/// Per the doc comment on `MediaPlayer.load()`, real native playback
/// failures (network, HTTP, decoder, source) are almost always reported
/// *asynchronously* by ExoPlayer/AVPlayer, well after `load()` has already
/// returned successfully — not as a thrown exception from the `load()` call
/// itself. That means the `try`/`on MediaLoadException`/`on NetworkException`
/// blocks below are a secondary safety net for genuinely synchronous
/// failures (bad config, rejected DRM setup); the four test scenarios in
/// this page are expected to surface primarily via
/// `controller.player.errorStream`, which this page subscribes to and
/// mirrors on screen.
///
/// The page provides five buttons:
///   1. Load a valid URL → happy path
///   2. Load a forbidden object (GCS bucket, 403) → HTTP category →
///      [MediaLoadException]
///   3. Load a genuinely missing object (404) → HTTP category →
///      [MediaLoadException]
///   4. Load a non-existent host → NETWORK category → [NetworkException]
///   5. Load a real, reachable, non-media file → SOURCE category →
///      [PlaybackException] (container/format cannot be parsed)
///
/// ### Why "403" and "404" are separate scenarios
/// They were originally conflated: a non-existent object in a public GCS
/// bucket (scenario 2's URL) returns **403 Forbidden**, not 404 — GCS can't
/// reveal that an object doesn't exist without granting list/read
/// permission on the bucket, so it refuses instead. That's still a useful,
/// dependable "server responds and refuses" HTTP case, just mislabeled if
/// called "404". Scenario 3 is a genuine 404: a non-existent path under a
/// real GitHub repo, which returns a plain 404 with no such permission
/// ambiguity. Both must land in the HTTP category; see
/// `MediaPlayerManager.categorizeFailure`/`categorize` (iOS) and
/// `categorizeExoPlayerError` (Android) for the native classification.
///
/// DRM (category `drm` / [DrmException]) cannot be provoked from this page:
/// every DRM scenario in this package requires a real license server and
/// valid credentials (Widevine/FairPlay/EZDRM), which are not available in
/// this example. See `drm_page.dart` for how DRM config is constructed; it
/// cannot complete a real license acquisition without a provisioned test
/// account, so it cannot be used to observe `MediaErrorCategory.drm` /
/// [DrmException] end-to-end either.
class ErrorHandlingPage extends StatefulWidget {
  const ErrorHandlingPage({super.key});

  @override
  State<ErrorHandlingPage> createState() => _ErrorHandlingPageState();
}

class _ErrorHandlingPageState extends State<ErrorHandlingPage> {
  late final MediaController _controller;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaPlayerException>? _errorSub;

  final List<_ErrorEvent> _errorLog = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'error_handling',
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

      // Untyped signal: PlayerState.error + PlaybackState.errorMessage.
      // Kept alongside errorStream below to demonstrate both APIs report the
      // same underlying native failure.
      _stateSub = _controller.player.stateStream.listen((state) {
        if (state.state == PlayerState.error && state.errorMessage != null) {
          _log(
            _ErrorEvent(
              timestamp: DateTime.now(),
              source: 'PlayerState.error',
              type: 'PlayerState.error',
              message: state.errorMessage!,
            ),
          );
        }
      });

      // Typed signal (Phase 3 / H-01): every network/HTTP/DRM/decoder/source
      // failure native reports, mapped onto the MediaPlayerException
      // hierarchy via the shared MediaErrorCategory vocabulary.
      _errorSub = _controller.player.errorStream.listen((e) {
        _logTypedError(e, source: 'errorStream');
      });
    } catch (e) {
      _log(
        _ErrorEvent(
          timestamp: DateTime.now(),
          source: 'init',
          type: e.runtimeType.toString(),
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> _loadGood() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(SampleMedia.forBiggerBlazes);
      await _controller.play();
    } on MediaPlayerException catch (e) {
      _logTypedError(e, source: 'catch(load)');
    } catch (e) {
      _logUnknown(e, source: 'catch(load)');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// A non-existent object in a **public** GCS bucket. GCS returns **403
  /// Forbidden** for this, not 404: determining whether the object exists
  /// would itself require list/read permission on the bucket, so GCS
  /// refuses the request outright rather than confirming non-existence.
  /// This is deliberately kept as its own scenario (distinct from the
  /// genuine 404 in [_loadNotFound]) because it exercises a different, real
  /// or-server-refusal shape than a plain "no such path" 404 — both must be
  /// classified as HTTP, but this one previously tripped up the iOS native
  /// classifier (`NSURLErrorNoPermissionsToReadFile` / -1102) in a way a
  /// plain 404 (`NSURLErrorFileDoesNotExist` / -1100) did not.
  Future<void> _loadForbidden() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(
        const MediaItem(
          id: 'forbidden_403',
          title: 'Forbidden (403)',
          url:
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/THIS_DOES_NOT_EXIST.mp4',
        ),
      );
    } on MediaPlayerException catch (e) {
      _logTypedError(e, source: 'catch(load)');
    } catch (e) {
      _logUnknown(e, source: 'catch(load)');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// A genuinely missing file under a real, public GitHub repository path.
  /// Chosen over a generic "status code" test service (e.g. httpbin.org)
  /// for two reasons: (1) it reuses the same `raw.githubusercontent.com`
  /// host already exercised by [_loadUnsupportedFormat] above, so this page
  /// depends on one external host instead of two, and (2) GitHub's raw CDN
  /// is high-uptime and returns a plain, unambiguous 404 (with a small body)
  /// for a non-existent path in an existing public repo — unlike the GCS
  /// bucket case in [_loadForbidden], there's no permission-checking
  /// ambiguity that could turn this into a 403.
  Future<void> _loadNotFound() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(
        const MediaItem(
          id: 'not_found_404',
          title: 'Not Found (404)',
          url:
              'https://raw.githubusercontent.com/flutter/flutter/master/THIS_PATH_DOES_NOT_EXIST_404_TEST.mp4',
        ),
      );
    } on MediaPlayerException catch (e) {
      _logTypedError(e, source: 'catch(load)');
    } catch (e) {
      _logUnknown(e, source: 'catch(load)');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBadHost() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(
        const MediaItem(
          id: 'bad_host',
          title: 'Non-existent Host',
          url: 'https://this-host-does-not-exist-zmedia.invalid/video.mp4',
        ),
      );
    } on MediaPlayerException catch (e) {
      _logTypedError(e, source: 'catch(load)');
    } catch (e) {
      _logUnknown(e, source: 'catch(load)');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// A real, reachable, HTTPS URL that returns HTTP 200 with a *non-media*
  /// body (a plain-text README, not a container ExoPlayer/AVPlayer can
  /// sniff/parse). This is deliberately distinct from the 404 and bad-host
  /// cases above: the server responds successfully, so this exercises the
  /// SOURCE category (unsupported/unparseable container) rather than HTTP or
  /// NETWORK — surfaced as a [PlaybackException] with
  /// `category == MediaErrorCategory.source`.
  Future<void> _loadUnsupportedFormat() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(
        const MediaItem(
          id: 'unsupported_format',
          title: 'Unsupported Format (text file)',
          url:
              'https://raw.githubusercontent.com/flutter/flutter/master/README.md',
        ),
      );
    } on MediaPlayerException catch (e) {
      _logTypedError(e, source: 'catch(load)');
    } catch (e) {
      _logUnknown(e, source: 'catch(load)');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------
  // Logging helpers
  // ---------------------------------------------------------------------

  /// Best-effort [MediaErrorCategory] for [e]. Only [PlaybackException]
  /// stores `category` directly; the other subtypes correspond 1:1 to a
  /// fixed category under `mapNativeMediaError` (see
  /// `lib/src/core/exceptions.dart`), so it is inferred here from the
  /// runtime type for display purposes.
  MediaErrorCategory? _categoryOf(MediaPlayerException e) {
    if (e is PlaybackException) return e.category;
    if (e is NetworkException) return MediaErrorCategory.network;
    if (e is MediaLoadException) return MediaErrorCategory.http;
    if (e is DrmException) return MediaErrorCategory.drm;
    return null;
  }

  /// Native error code / HTTP status carried by [e], when present.
  String? _codeOf(MediaPlayerException e) {
    if (e is MediaLoadException && e.statusCode != null) {
      return 'HTTP ${e.statusCode}';
    }
    if (e is DrmException && e.errorCode != null) return e.errorCode;
    if (e is PlaybackException && e.errorCode != null) return e.errorCode;
    return null;
  }

  /// Extra boolean flags [e] carries (isOffline/isTimeout,
  /// isLicenseError/isCertificateError), joined for display.
  String? _flagsOf(MediaPlayerException e) {
    if (e is NetworkException) {
      final flags = <String>[
        if (e.isOffline) 'offline',
        if (e.isTimeout) 'timeout',
      ];
      return flags.isEmpty ? null : flags.join(', ');
    }
    if (e is DrmException) {
      final flags = <String>[
        if (e.isLicenseError) 'license error',
        if (e.isCertificateError) 'certificate error',
      ];
      return flags.isEmpty ? null : flags.join(', ');
    }
    return null;
  }

  void _logTypedError(MediaPlayerException e, {required String source}) {
    _log(
      _ErrorEvent(
        timestamp: DateTime.now(),
        source: source,
        type: e.runtimeType.toString(),
        category: _categoryOf(e),
        code: _codeOf(e),
        flags: _flagsOf(e),
        message: e.message,
      ),
    );
  }

  void _logUnknown(Object e, {required String source}) {
    _log(
      _ErrorEvent(
        timestamp: DateTime.now(),
        source: source,
        type: e.runtimeType.toString(),
        message: e.toString(),
      ),
    );
  }

  /// Mirrors [event] into the on-screen log (primary readout — this page is
  /// exercised as a release build on a physical device, where `debugPrint`
  /// is not a reliable signal) and, best-effort, into the console with an
  /// `[ERR]` prefix so it stays greppable when console capture is
  /// available.
  void _log(_ErrorEvent event) {
    debugPrint('[ERR] ${event.consoleLine}');
    if (!mounted) return;
    setState(() {
      _errorLog.insert(0, event);
      if (_errorLog.length > 20) _errorLog.removeLast();
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _errorSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Error Handling',
      controller: _controller,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Test Scenarios'),
        _ScenarioButtons(
          isLoading: _isLoading,
          onLoadGood: _loadGood,
          onLoadForbidden: _loadForbidden,
          onLoadNotFound: _loadNotFound,
          onLoadBadHost: _loadBadHost,
          onLoadUnsupportedFormat: _loadUnsupportedFormat,
        ),
        const SizedBox(height: 16),
        const SectionHeader('Live Player State'),
        _LiveStateCard(controller: _controller),
        const SizedBox(height: 16),
        const SectionHeader('Error Log (errorStream + catch, newest first)'),
        if (_errorLog.isEmpty)
          Text(
            'No errors yet. Tap a scenario above to trigger one.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ..._errorLog.map((e) => _ErrorEventTile(event: e)),
        const SizedBox(height: 16),
        const _ErrorHandlingNote(),
      ],
    );
  }
}

class _ScenarioButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onLoadGood;
  final VoidCallback onLoadForbidden;
  final VoidCallback onLoadNotFound;
  final VoidCallback onLoadBadHost;
  final VoidCallback onLoadUnsupportedFormat;

  const _ScenarioButtons({
    required this.isLoading,
    required this.onLoadGood,
    required this.onLoadForbidden,
    required this.onLoadNotFound,
    required this.onLoadBadHost,
    required this.onLoadUnsupportedFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Load Valid URL'),
          onPressed: isLoading ? null : onLoadGood,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.block),
          label: const Text('Forbidden (403)'),
          onPressed: isLoading ? null : onLoadForbidden,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.broken_image),
          label: const Text('Not Found (404)'),
          onPressed: isLoading ? null : onLoadNotFound,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.wifi_off),
          label: const Text('Bad Host'),
          onPressed: isLoading ? null : onLoadBadHost,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.text_snippet_outlined),
          label: const Text('Unsupported Format'),
          onPressed: isLoading ? null : onLoadUnsupportedFormat,
        ),
      ],
    );
  }
}

class _LiveStateCard extends StatelessWidget {
  final MediaController controller;
  const _LiveStateCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final isError = state.state == PlayerState.error;
        return Card(
          margin: EdgeInsets.zero,
          color: isError ? Theme.of(context).colorScheme.errorContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(label: 'State', value: state.state.name),
                if (state.errorMessage != null)
                  InfoRow(label: 'Error', value: state.errorMessage!),
                InfoRow(
                    label: 'Has Error',
                    value: controller.hasError ? 'Yes' : 'No'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorEventTile extends StatelessWidget {
  final _ErrorEvent event;
  const _ErrorEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      _Chip(label: event.source, color: theme.colorScheme.secondaryContainer),
      if (event.category != null)
        _Chip(
          label: event.category!.wireValue,
          color: theme.colorScheme.tertiaryContainer,
        ),
      if (event.code != null)
        _Chip(
            label: event.code!,
            color: theme.colorScheme.surfaceContainerHighest),
      if (event.flags != null)
        _Chip(label: event.flags!, color: theme.colorScheme.errorContainer),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color:
          Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline,
                    size: 14, color: theme.colorScheme.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    event.type,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${event.timestamp.second.toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: chips),
            const SizedBox(height: 4),
            Text(
              event.message,
              style: theme.textTheme.bodySmall,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _ErrorHandlingNote extends StatelessWidget {
  const _ErrorHandlingNote();

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
        'Exception types: MediaLoadException (HTTP), NetworkException '
        '(NETWORK), DrmException (DRM), PlaybackException (DECODER / '
        'SOURCE / UNKNOWN), ConfigurationException, InvalidStateException, '
        'PlayerDisposedException, PlatformOperationException. All extend '
        'sealed class MediaPlayerException.\n\n'
        'Each log entry shows: [source it was observed on] [exception '
        'type] [MediaErrorCategory, inferred from mapNativeMediaError] '
        '[native code / HTTP status, if any] [extra flags] [message].\n\n'
        'DRM (category `drm`) cannot be provoked from this page — every '
        'DRM path needs a real license server + credentials this example '
        'does not have. Reachable here: NETWORK (Bad Host), HTTP (Forbidden '
        '403, Not Found 404), SOURCE (Unsupported Format).',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorEvent {
  final DateTime timestamp;

  /// Where this event was observed: 'errorStream', 'PlayerState.error',
  /// 'catch(load)', or 'init'.
  final String source;

  /// The exception's runtime type (e.g. 'NetworkException'), or
  /// 'PlayerState.error' for the untyped state-stream signal.
  final String type;

  final MediaErrorCategory? category;
  final String? code;
  final String? flags;
  final String message;

  _ErrorEvent({
    required this.timestamp,
    required this.source,
    required this.type,
    this.category,
    this.code,
    this.flags,
    required this.message,
  });

  /// Single-line representation for the `[ERR]`-prefixed console mirror.
  String get consoleLine {
    final parts = <String>[
      'source=$source',
      'type=$type',
      if (category != null) 'category=${category!.wireValue}',
      if (code != null) 'code=$code',
      if (flags != null) 'flags=$flags',
      'message=$message',
    ];
    return parts.join(' ');
  }
}

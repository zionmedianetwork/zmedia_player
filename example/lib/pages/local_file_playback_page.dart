import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates C-02 Stage 1 — local file playback.
///
/// A tiny synthetic clip (`assets/videos/local_sample.mp4`, generated with
/// ffmpeg's `testsrc`/`sine` filters — no external license) ships inside the
/// app bundle so this page works with no network access at all. Flutter
/// asset bundles are not directly readable by the native media players
/// (there is no filesystem path for a `rootBundle` asset), so on first run
/// this page copies the bytes out to a real file under the app's documents
/// directory, then builds a `file://` URL for it via
/// [LocalMediaUtils.fileUri] and loads that like any other [MediaItem].
///
/// This exercises the same validation path
/// ([InputValidator.validateUrl]) and the same native load path
/// (`MediaPlayer.load` -> platform `loadMediaItem`) as every other page —
/// there is nothing local-file-specific about them once the URL is a
/// well-formed `file://` URI.
class LocalFilePlaybackPage extends StatefulWidget {
  const LocalFilePlaybackPage({super.key});

  @override
  State<LocalFilePlaybackPage> createState() => _LocalFilePlaybackPageState();
}

class _LocalFilePlaybackPageState extends State<LocalFilePlaybackPage> {
  late final MediaController _controller;
  bool _isLoading = false;
  String? _error;
  String? _localFileUrl;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'local_file_playback',
      config: const MediaConfig(respectSafeArea: true, autoPlay: false),
    );
    _prepareAndLoad();
  }

  Future<void> _prepareAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final path = await _ensureLocalFileOnDisk();
      // C-02 Stage 1: the package standardizes on file:// URIs rather than
      // bare filesystem paths — see InputValidator's dartdoc for why —
      // LocalMediaUtils.fileUri() builds one that correctly percent-encodes
      // the path.
      final url = LocalMediaUtils.fileUri(path);

      await _controller.initialize();
      await _controller.load(
        MediaItem(
          id: 'local-sample-clip',
          title: 'Local sample clip (bundled asset)',
          url: url,
          mediaType: MediaType.video,
        ),
      );

      if (mounted) setState(() => _localFileUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Copies the bundled asset out to a real file under the app's documents
  /// directory (skipping the copy if it's already there from a previous
  /// run) and returns its filesystem path.
  Future<String> _ensureLocalFileOnDisk() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File('${docsDir.path}/local_sample.mp4');

    if (!await file.exists()) {
      final bytes = await rootBundle.load('assets/videos/local_sample.mp4');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }

    return file.path;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Local File Playback',
      controller: _controller,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorCard(message: _error!, onRetry: _prepareAndLoad);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Now Playing'),
        _NowPlayingCard(controller: _controller, url: _localFileUrl),
        const SectionHeader('Playback Controls'),
        _PlaybackControls(controller: _controller),
        const SizedBox(height: 16),
        const _ApiNote(),
      ],
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final MediaController controller;
  final String? url;
  const _NowPlayingCard({required this.controller, required this.url});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Local sample clip',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                InfoRow(label: 'State', value: state.state.name),
                InfoRow(
                  label: 'Position',
                  value:
                      '${controller.formattedPosition} / ${controller.formattedDuration}',
                ),
                InfoRow(label: 'file:// URL', value: url ?? '-'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final MediaController controller;
  const _PlaybackControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: Icon(
                controller.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              label: Text(controller.isPlaying ? 'Pause' : 'Play'),
              onPressed: () => controller.togglePlayPause(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              onPressed: controller.isPlaying || controller.isPaused
                  ? () => controller.stop()
                  : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.replay_10),
              label: const Text('-10s'),
              onPressed: () => controller.seekBackward(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.forward_10),
              label: const Text('+10s'),
              onPressed: () => controller.seekForward(),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Load Error',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 12,
                )),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ApiNote extends StatelessWidget {
  const _ApiNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'API Used',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'LocalMediaUtils.fileUri(path) -> MediaItem(url: file://...) -> '
            'MediaController.load(). No network is used: the clip is a '
            'bundled asset copied to the documents directory on first run.\n\n'
            'InputValidator.validateUrl() accepts file:// for MEDIA URLs '
            'only — DRM license/certificate URLs still require HTTPS '
            '(requireHttps: true never permits file://), and traversal '
            'segments ("..", percent-encoded or not) inside a file:// URL '
            'are rejected.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

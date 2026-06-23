import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates fullscreen playback using:
/// - [FullscreenMediaPlayer] — built-in fullscreen scaffold that locks
///   orientation and hides system UI
/// - [MaterialFullscreenPlayer] — Material Design 3 controls wrapper for
///   fullscreen, used as [MediaPlayerWidget.customControls]
///
/// The normal→fullscreen transition is achieved by pushing [FullscreenMediaPlayer]
/// as a new route.  The same [MediaController] is shared, so playback continues
/// seamlessly without re-loading.
///
/// NOTE: Orientation locking uses SystemChrome.setPreferredOrientations —
/// effective on physical devices.  On some simulators the orientation may not
/// actually rotate.
class FullscreenPage extends StatefulWidget {
  const FullscreenPage({super.key});

  @override
  State<FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<FullscreenPage> {
  late final MediaController _controller;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'fullscreen_demo',
      // respectSafeArea keeps the video below the status bar / notch in
      // landscape so content is never obscured. Set immersiveLandscape: true
      // instead if you want the status bar hidden in landscape.
      config: const MediaConfig(respectSafeArea: true),
    );
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _controller.initialize();
      await _controller.load(SampleMedia.bigBuckBunny);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Navigate to fullscreen route using the built-in FullscreenMediaPlayer.
  ///
  /// Passes the same [_controller] so playback is uninterrupted.
  Future<void> _enterFullscreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenMediaPlayer(
          controller: _controller,
        ),
        fullscreenDialog: true,
      ),
    );

    // Restore portrait orientation when returning
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Navigate to fullscreen using MaterialFullscreenPlayer as customControls.
  ///
  /// This variant lets you customise the controls in fullscreen while still
  /// using [MediaPlayerWidget] as the video surface.
  Future<void> _enterMaterialFullscreen() async {
    // Reuse the built-in FullscreenMediaPlayer wrapper (handles orientation, the
    // video surface, and an always-visible exit button) but supply
    // MaterialFullscreenPlayer as the controls overlay.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenMediaPlayer(
          controller: _controller,
          customControls: MaterialFullscreenPlayer(
            controller: _controller,
            title: SampleMedia.bigBuckBunny.title,
            showSettings: true,
            showPip: true,
          ),
        ),
        fullscreenDialog: true,
      ),
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Fullscreen',
      controller: _controller,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
        FilledButton(onPressed: _initAndLoad, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Playback Control'),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: Icon(
                    _controller.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(_controller.isPlaying ? 'Pause' : 'Play'),
                onPressed: () => _controller.togglePlayPause(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Enter Fullscreen'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.fullscreen),
              label: const Text('FullscreenMediaPlayer'),
              onPressed: _enterFullscreen,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.fullscreen),
              label: const Text('MaterialFullscreenPlayer'),
              onPressed: _enterMaterialFullscreen,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _FullscreenNote(),
      ],
    );
  }
}

class _FullscreenNote extends StatelessWidget {
  const _FullscreenNote();

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
        'FullscreenMediaPlayer: built-in Scaffold + orientation lock.\n'
        'MaterialFullscreenPlayer: custom fullscreen controls widget.\n'
        'Both share the same MediaController — no reload needed.\n'
        'The fullscreen button in AdaptiveMediaControls (top bar) also '
        'enters fullscreen via the same mechanism.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

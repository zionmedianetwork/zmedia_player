import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates the adaptive and custom controls widgets:
/// - [AdaptiveMediaControls] — auto-selects Material or Cupertino style
/// - [AdaptiveControlStyle] — force a specific style via forceStyle
/// - [MaterialMediaControls] — Material Design 3 controls directly
/// - [CupertinoMediaControls] — Cupertino blur-effect controls
/// - [CustomControlsBase] — abstract base for building fully custom controls
///
/// The live player at the top uses [AdaptiveMediaControls] with the forced
/// style matching the current selection.  The bottom section shows a minimal
/// custom controls example that extends [CustomControlsBase].
class AdaptiveControlsPage extends StatefulWidget {
  const AdaptiveControlsPage({super.key});

  @override
  State<AdaptiveControlsPage> createState() => _AdaptiveControlsPageState();
}

class _AdaptiveControlsPageState extends State<AdaptiveControlsPage> {
  late final MediaController _controller;
  AdaptiveControlStyle _forcedStyle = AdaptiveControlStyle.material;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(playerId: 'adaptive_controls');
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _controller.initialize();
      await _controller.load(SampleMedia.forBiggerFun);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adaptive Controls'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Player with overrideable controls style
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MediaPlayerWidget(
              controller: _controller,
              showControls: true,
              customControls: AdaptiveMediaControls(
                controller: _controller,
                title: 'For Bigger Fun',
                forceStyle: _forcedStyle,
                showFullscreen: true,
                showSettings: true,
                showPip: true,
              ),
              backgroundColor: Colors.black,
            ),
          ),
          // Controls for the demo
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Text('Error: $_error',
                          style: const TextStyle(color: Colors.redAccent))
                      : _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Control Style Override'),
        Text(
          'AdaptiveMediaControls auto-detects platform (iOS → Cupertino, '
          'Android/other → Material). Use forceStyle to override:',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<AdaptiveControlStyle>(
          segments: const [
            ButtonSegment(
              value: AdaptiveControlStyle.material,
              label: Text('Material'),
              icon: Icon(Icons.android),
            ),
            ButtonSegment(
              value: AdaptiveControlStyle.cupertino,
              label: Text('Cupertino'),
              icon: Icon(Icons.apple),
            ),
          ],
          selected: {_forcedStyle},
          onSelectionChanged: (s) => setState(() => _forcedStyle = s.first),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Custom Controls (CustomControlsBase)'),
        const _CustomControlsNote(),
        const SizedBox(height: 12),
        // Embed a live custom controls demo directly
        AspectRatio(
          aspectRatio: 16 / 9,
          child: MediaPlayerWidget(
            controller: _controller,
            showControls: true,
            customControls: _MinimalCustomControls(controller: _controller),
            backgroundColor: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        const _AdaptiveNote(),
      ],
    );
  }
}

/// Minimal custom controls implementation extending [CustomControlsBase].
///
/// Demonstrates:
/// - How to subclass [CustomControlsBase]
/// - How [buildControls] receives [ControlsState] with visibility / animation
/// - How to use the inherited [toggleControls], [showControls], etc.
class _MinimalCustomControls extends CustomControlsBase {
  const _MinimalCustomControls({
    required super.controller,
  }) : super(
          autoHideEnabled: true,
          autoHideDelay: const Duration(seconds: 4),
          animationDuration: const Duration(milliseconds: 250),
          animationCurve: Curves.easeInOut,
        );

  @override
  Widget buildControls(BuildContext context, ControlsState state) {
    return FadeTransition(
      opacity: state.animation,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.4),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Center play/pause
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => controller.togglePlayPause(),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => Icon(
                        controller.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final progress = controller.progress;
                    final pos = controller.formattedPosition;
                    final dur = controller.formattedDuration;
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12),
                          ),
                          child: Slider(
                            value: progress.clamp(0.0, 1.0),
                            onChanged: (v) {
                              final dur = controller.duration;
                              controller.seekTo(dur * v);
                            },
                            activeColor: Colors.white,
                            inactiveColor: Colors.white30,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('$pos / $dur',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                            const Text('Custom Controls',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomControlsNote extends StatelessWidget {
  const _CustomControlsNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .tertiaryContainer
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Extend CustomControlsBase and implement buildControls(context, state).\n'
        'ControlsState gives you fadeAnimation for opacity transitions.\n'
        'Inherited helpers: toggleControls(), showControls(), hideControls(), '
        'resetAutoHideTimer().',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _AdaptiveNote extends StatelessWidget {
  const _AdaptiveNote();

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
        'API: AdaptiveMediaControls(controller, forceStyle, title, ...)\n'
        'MaterialMediaControls / CupertinoMediaControls: direct platform widgets.\n'
        'CustomControlsBase: abstract class — extend and implement buildControls().\n'
        'Pass custom controls as MediaPlayerWidget(customControls: ...).',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

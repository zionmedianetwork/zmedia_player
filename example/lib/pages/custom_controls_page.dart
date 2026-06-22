import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

// =============================================================================
// HOW TO BUILD FULLY CUSTOM CONTROLS
// =============================================================================
//
// Step 1 — Extend [CustomControlsBase] and implement [buildControls].
//   Your override receives a [ControlsState] that carries:
//     • isVisible        — whether the overlay should be shown right now
//     • animation        — an Animation<double> (0→1) you can use for fades
//     • animationValue   — the current double value of that animation
//     • controller       — the [MediaController] to read state from and call
//                          actions on
//
//   Inherited state helpers (forwarded to MediaController):
//     • toggleControls()
//     • showControls({startAutoHide})
//     • hideControls()
//     • resetAutoHideTimer()      ← call after user interaction to reset the
//                                    auto-hide countdown
//
// Step 2 — Pass your widget to [MediaPlayerWidget.customControls].
//   MediaPlayerWidget(
//     controller: _controller,
//     customControls: BrandedControls(controller: _controller),
//   )
//
// Step 3 — Drive the UI entirely from [MediaController].
//   Use [ListenableBuilder] (scoped to what changes) rather than rebuilding
//   the whole overlay on every notification.
//
// ALTERNATIVE — no subclass required:
//   Use the [CustomControlsBuilder] convenience widget if you prefer an inline
//   builder approach:
//
//   CustomControlsBuilder(
//     controller: _controller,
//     builder: (context, state) {
//       return Opacity(
//         opacity: state.animationValue,
//         child: YourWidget(controller: state.controller),
//       );
//     },
//   )
//
// =============================================================================

/// Flagship demo of the ZMedia Player custom-controls API.
///
/// This page shows how a consumer can build a **completely bespoke overlay**
/// from scratch using [CustomControlsBase] + [MediaPlayerWidget].
/// The [BrandedControls] class below is the centrepiece: it demonstrates every
/// meaningful API surface without touching any private/src-internal member.
class CustomControlsPage extends StatefulWidget {
  const CustomControlsPage({super.key});

  @override
  State<CustomControlsPage> createState() => _CustomControlsPageState();
}

class _CustomControlsPageState extends State<CustomControlsPage> {
  late final MediaController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(playerId: 'custom_controls_demo');
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    try {
      await _controller.initialize();
      // BigBuckBunny gives ~10 min of content — enough to demonstrate seek.
      await _controller.load(SampleMedia.bigBuckBunny);
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
        title: const Text('Fully Custom Controls'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Player ────────────────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _isLoading
                ? const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                : _error != null
                    ? ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: Text(
                            'Error: $_error',
                            style: const TextStyle(color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : MediaPlayerWidget(
                        controller: _controller,
                        showControls: true,
                        // Inject the bespoke overlay — this is the key API call.
                        customControls: BrandedControls(
                          controller: _controller,
                          title: SampleMedia.bigBuckBunny.title,
                        ),
                        backgroundColor: Colors.black,
                      ),
          ),

          // ── Explanation body ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildBody(),
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
        const SectionHeader('What this demo shows'),
        _InfoBox(
          child: Text(
            'BrandedControls extends CustomControlsBase and implements '
            'buildControls(context, state) — every pixel of the overlay is '
            'drawn by this package consumer. No internal APIs are used.\n\n'
            'MediaController members driven: isPlaying, isBuffering, '
            'position, duration, progress, bufferedProgress, '
            'formattedPosition, formattedDuration, speed, qualityTracks, '
            'selectedQualityTrack, togglePlayPause(), seekTo(), '
            'seekForward(), seekBackward(), setSpeed(), setQualityTrack(), '
            'enableAutoQuality(), toggleControls(), showControlsTemporarily().',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Gestures'),
        _InfoBox(
          child: Text(
            '• Single tap — toggle controls (delegated to base)\n'
            '• Double-tap left half — rewind 10 s with animated feedback\n'
            '• Double-tap right half — forward 10 s with animated feedback\n'
            '• Seek-bar drag — position updated only on drag-end (not per frame)\n'
            '• Speed badge tap — cycles 0.5 / 1.0 / 1.5 / 2.0×\n'
            '• Quality badge tap — auto or any reported quality track',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Inline builder alternative'),
        _InfoBox(
          child: Text(
            'If you prefer not to subclass, use CustomControlsBuilder:\n\n'
            'CustomControlsBuilder(\n'
            '  controller: _controller,\n'
            '  builder: (context, state) {\n'
            '    return Opacity(\n'
            '      opacity: state.animationValue,\n'
            '      child: YourOverlay(controller: state.controller),\n'
            '    );\n'
            '  },\n'
            ')',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Live state readout ─────────────────────────────────────────────
        const SectionHeader('Live controller state'),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            children: [
              InfoRow(
                label: 'State',
                value: _controller.state.state.name,
              ),
              InfoRow(
                label: 'Position',
                value: _controller.formattedPosition,
              ),
              InfoRow(
                label: 'Duration',
                value: _controller.formattedDuration,
              ),
              InfoRow(
                label: 'Speed',
                value: '${_controller.speed}×',
              ),
              InfoRow(
                label: 'Buffered',
                value:
                    '${(_controller.bufferedProgress * 100).toStringAsFixed(1)} %',
              ),
              InfoRow(
                label: 'Quality tracks',
                value: _controller.qualityTracks.isEmpty
                    ? 'none reported'
                    : _controller.qualityTracks.map((t) => t.name).join(', '),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// BrandedControls — the fully custom overlay
// =============================================================================

/// A bespoke media-player overlay that extends [CustomControlsBase].
///
/// ### How a consumer builds custom controls (summary)
///
/// 1. Extend [CustomControlsBase].
/// 2. Declare constructor params you need (here: `title`).
/// 3. Override `buildControls(context, state)` — the framework calls it inside
///    an `AnimatedBuilder` so the whole overlay already rebuilds when the fade
///    animation ticks.  Do NOT start another AnimatedBuilder on `state.animation`
///    at the top level — instead pass the animation down to children that need
///    it (e.g. the gradient container).
/// 4. Read media state from `controller` (the inherited getter), scope each
///    `ListenableBuilder` to only the widgets that need to repaint.
/// 5. Inject via `MediaPlayerWidget(customControls: BrandedControls(...))`.
class BrandedControls extends CustomControlsBase {
  /// Title displayed in the top bar.
  final String title;

  const BrandedControls({
    super.key,
    required super.controller,
    required this.title,
    super.autoHideEnabled = true,
    super.autoHideDelay = const Duration(seconds: 4),
    super.animationDuration = const Duration(milliseconds: 280),
    super.animationCurve = Curves.easeInOut,
  });

  @override
  Widget buildControls(BuildContext context, ControlsState state) {
    // The AnimatedBuilder in CustomControlsBaseState already wraps this build.
    // We receive the current animationValue directly in ControlsState, so we
    // can use it for opacity without adding another AnimatedBuilder at this
    // level.
    return _BrandedControlsBody(
      controls: this,
      state: state,
    );
  }
}

/// Internal stateful body of [BrandedControls].
///
/// Kept separate so it can hold local state (seek-drag value, double-tap
/// flash) without forcing a full rebuild of the outer CustomControlsBase tree.
class _BrandedControlsBody extends StatefulWidget {
  final BrandedControls controls;
  final ControlsState state;

  const _BrandedControlsBody({
    required this.controls,
    required this.state,
  });

  @override
  State<_BrandedControlsBody> createState() => _BrandedControlsBodyState();
}

class _BrandedControlsBodyState extends State<_BrandedControlsBody>
    with TickerProviderStateMixin {
  // ── Seek drag state ──────────────────────────────────────────────────────
  /// When non-null the user is dragging the seek bar; value is 0.0→1.0.
  double? _dragProgress;

  // ── Double-tap flash animations ──────────────────────────────────────────
  late AnimationController _leftFlashCtrl;
  late AnimationController _rightFlashCtrl;

  // ── Quality / speed pop-up visibility ───────────────────────────────────
  bool _showSpeedPicker = false;
  bool _showQualityPicker = false;

  /// Convenience accessor to the [MediaController].
  MediaController get _mc => widget.controls.controller;

  /// Convenience accessor to the base-class state helpers.
  ///
  /// We need the [CustomControlsBaseState] to call [resetAutoHideTimer] and
  /// [hideControls].  The base widget's [State] is accessible via the context
  /// because [BrandedControls] is a [CustomControlsBase] — its
  /// [createState] returns a [CustomControlsBaseState] which is the first
  /// ancestor of type [CustomControlsBaseState].
  CustomControlsBaseState get _base =>
      context.findAncestorStateOfType<CustomControlsBaseState>()!;

  @override
  void initState() {
    super.initState();
    _leftFlashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _rightFlashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _leftFlashCtrl.dispose();
    _rightFlashCtrl.dispose();
    super.dispose();
  }

  // ── Gesture helpers ───────────────────────────────────────────────────────

  void _onDoubleTapLeft() {
    _mc.seekBackward();
    _leftFlashCtrl.forward(from: 0);
    _base.resetAutoHideTimer();
  }

  void _onDoubleTapRight() {
    _mc.seekForward();
    _rightFlashCtrl.forward(from: 0);
    _base.resetAutoHideTimer();
  }

  // ── Speed options ─────────────────────────────────────────────────────────

  static const _speeds = [0.5, 1.0, 1.5, 2.0];

  // ── Seek bar callbacks ────────────────────────────────────────────────────

  void _onSeekChanged(double value) {
    // Update local drag display only — do NOT call seekTo on every frame.
    setState(() => _dragProgress = value);
  }

  void _onSeekEnd(double value) {
    // Seek exactly once when the user lifts their finger.
    final target = _mc.duration * value;
    _mc.seekTo(target);
    setState(() => _dragProgress = null);
    _base.resetAutoHideTimer();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final animValue = widget.state.animationValue;

    return Stack(
      children: [
        // ── Gradient scrim (fades with animValue) ────────────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: animValue,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.35, 0.65, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.80),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Double-tap zones (always active, even when controls hidden) ───
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _onDoubleTapLeft,
                  // Single tap is NOT handled here; MediaPlayerWidget's own
                  // tap-detector calls controller.toggleControls() when
                  // controls are hidden, and BrandedControls receives the
                  // toggleControls() call via CustomControlsBase when
                  // controls are visible.
                  child: const SizedBox.expand(),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _onDoubleTapRight,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),

        // ── Left flash: rewind indicator ──────────────────────────────────
        Positioned(
          left: 24,
          top: 0,
          bottom: 0,
          child: _SeekFlashIndicator(
            controller: _leftFlashCtrl,
            icon: Icons.replay_10,
            label: '-10s',
          ),
        ),

        // ── Right flash: forward indicator ───────────────────────────────
        Positioned(
          right: 24,
          top: 0,
          bottom: 0,
          child: _SeekFlashIndicator(
            controller: _rightFlashCtrl,
            icon: Icons.forward_10,
            label: '+10s',
          ),
        ),

        // ── Top bar ───────────────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: animValue,
            child: IgnorePointer(
              ignoring: animValue < 0.1,
              child: _TopBar(
                title: widget.controls.title,
                onSettingsTap: () {
                  setState(() {
                    _showQualityPicker = false;
                    _showSpeedPicker = !_showSpeedPicker;
                  });
                  _base.resetAutoHideTimer();
                },
              ),
            ),
          ),
        ),

        // ── Center controls (play/pause + rewind/forward) ─────────────────
        Center(
          child: Opacity(
            opacity: animValue,
            child: IgnorePointer(
              ignoring: animValue < 0.1,
              child: _CenterControls(controller: _mc),
            ),
          ),
        ),

        // ── Buffering spinner (independent of overlay visibility) ─────────
        ListenableBuilder(
          listenable: _mc,
          builder: (context, _) {
            if (!_mc.isBuffering) return const SizedBox.shrink();
            return const Center(
              child: SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            );
          },
        ),

        // ── Bottom bar ────────────────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: animValue,
            child: IgnorePointer(
              ignoring: animValue < 0.1,
              child: _BottomBar(
                controller: _mc,
                dragProgress: _dragProgress,
                onSeekChanged: _onSeekChanged,
                onSeekEnd: _onSeekEnd,
                onSpeedTap: () {
                  setState(() {
                    _showQualityPicker = false;
                    _showSpeedPicker = !_showSpeedPicker;
                  });
                  _base.resetAutoHideTimer();
                },
                onQualityTap: () {
                  setState(() {
                    _showSpeedPicker = false;
                    _showQualityPicker = !_showQualityPicker;
                  });
                  _base.resetAutoHideTimer();
                },
              ),
            ),
          ),
        ),

        // ── Speed picker popup ────────────────────────────────────────────
        if (_showSpeedPicker)
          Positioned(
            bottom: 72,
            right: 12,
            child: _SpeedPicker(
              controller: _mc,
              speeds: _speeds,
              onSelected: (s) {
                _mc.setSpeed(s);
                setState(() => _showSpeedPicker = false);
                _base.resetAutoHideTimer();
              },
              onDismiss: () => setState(() => _showSpeedPicker = false),
            ),
          ),

        // ── Quality picker popup ──────────────────────────────────────────
        if (_showQualityPicker)
          Positioned(
            bottom: 72,
            right: 12,
            child: ListenableBuilder(
              listenable: _mc,
              builder: (context, _) {
                // Hide if there are no quality tracks yet.
                if (_mc.qualityTracks.isEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => setState(() => _showQualityPicker = false),
                  );
                  return const SizedBox.shrink();
                }
                return _QualityPicker(
                  controller: _mc,
                  onSelected: (track) {
                    if (track == null) {
                      _mc.enableAutoQuality();
                    } else {
                      _mc.setQualityTrack(track);
                    }
                    setState(() => _showQualityPicker = false);
                    _base.resetAutoHideTimer();
                  },
                  onDismiss: () => setState(() => _showQualityPicker = false),
                );
              },
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

/// Top bar: title on the left, settings icon on the right.
class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onSettingsTap;

  const _TopBar({required this.title, required this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _ControlIconButton(
            icon: Icons.settings,
            tooltip: 'Settings',
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

/// Center row: rewind • play/pause • forward.
class _CenterControls extends StatelessWidget {
  final MediaController controller;

  const _CenterControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rewind 10 s
            _ControlIconButton(
              icon: Icons.replay_10,
              size: 36,
              tooltip: 'Rewind 10s',
              onTap: controller.seekBackward,
            ),
            const SizedBox(width: 24),

            // Play / Pause — larger, filled circle
            _PlayPauseButton(
              isPlaying: controller.isPlaying,
              onTap: controller.togglePlayPause,
            ),
            const SizedBox(width: 24),

            // Forward 10 s
            _ControlIconButton(
              icon: Icons.forward_10,
              size: 36,
              tooltip: 'Forward 10s',
              onTap: controller.seekForward,
            ),
          ],
        );
      },
    );
  }
}

/// Bottom bar: seek bar + time + speed badge + quality badge.
class _BottomBar extends StatelessWidget {
  final MediaController controller;

  /// Non-null while the user is dragging the seek thumb.
  final double? dragProgress;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onSpeedTap;
  final VoidCallback onQualityTap;

  const _BottomBar({
    required this.controller,
    required this.dragProgress,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onSpeedTap,
    required this.onQualityTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Hand-built seek bar ─────────────────────────────────────────
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final played =
                  dragProgress ?? controller.progress.clamp(0.0, 1.0);
              final buffered = controller.bufferedProgress.clamp(0.0, 1.0);
              return RepaintBoundary(
                child: _BrandedSeekBar(
                  played: played,
                  buffered: buffered,
                  onChanged: onSeekChanged,
                  onChangeEnd: onSeekEnd,
                ),
              );
            },
          ),
          const SizedBox(height: 4),

          // ── Time + badges ──────────────────────────────────────────────
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Row(
                children: [
                  // Current / total — tabular numbers
                  Text(
                    '${controller.formattedPosition} / ${controller.formattedDuration}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),

                  // Quality badge (hidden when no tracks)
                  if (controller.qualityTracks.isNotEmpty) ...[
                    _BadgeButton(
                      label: controller.selectedQualityTrack?.name ?? 'Auto',
                      onTap: onQualityTap,
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Speed badge
                  _BadgeButton(
                    label: '${controller.speed}×',
                    onTap: onSpeedTap,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Hand-built seek bar (custom painter — buffered + played + remaining)
// =============================================================================

/// A seek bar drawn with a [CustomPainter] so we can show:
/// - **Remaining** (dim gray track)
/// - **Buffered** (semi-opaque white)
/// - **Played** (solid accent/white)
/// - **Thumb** (white circle)
///
/// Drag only emits [onChangeEnd] — NOT [onChanged] — to avoid seeking on every
/// pointer-move frame.  During a drag [onChanged] updates local display state
/// held in the parent, while [onChangeEnd] triggers the actual [seekTo] call.
class _BrandedSeekBar extends StatelessWidget {
  final double played;
  final double buffered;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BrandedSeekBar({
    required this.played,
    required this.buffered,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    // SliderTheme gives us dragging/interaction semantics for free while our
    // CustomPainter handles the visual drawing.  We override the track and
    // thumb to transparent so only our painter shows.
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
        overlayShape: SliderComponentShape.noOverlay,
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
        thumbColor: Colors.transparent,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Visual layer — custom painted track + thumb
          SizedBox(
            height: 24,
            child: CustomPaint(
              painter: _SeekBarPainter(played: played, buffered: buffered),
              size: Size.infinite,
            ),
          ),
          // Interaction layer — invisible Slider on top
          SizedBox(
            height: 24,
            child: Slider(
              value: played,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              min: 0,
              max: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  final double played;
  final double buffered;

  const _SeekBarPainter({required this.played, required this.buffered});

  @override
  void paint(Canvas canvas, Size size) {
    const trackH = 4.0;
    const thumbR = 7.0;
    final cy = size.height / 2;
    final trackY = cy - trackH / 2;

    // ── Remaining (gray) ───────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromLTRBR(
          0, trackY, size.width, trackY + trackH, const Radius.circular(2)),
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );

    // ── Buffered (lighter) ─────────────────────────────────────────────────
    final bufferedW = (size.width * buffered).clamp(0.0, size.width);
    if (bufferedW > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
            0, trackY, bufferedW, trackY + trackH, const Radius.circular(2)),
        Paint()..color = Colors.white.withValues(alpha: 0.45),
      );
    }

    // ── Played (solid white) ───────────────────────────────────────────────
    final playedW = (size.width * played).clamp(0.0, size.width);
    if (playedW > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
            0, trackY, playedW, trackY + trackH, const Radius.circular(2)),
        Paint()..color = Colors.white,
      );
    }

    // ── Thumb ──────────────────────────────────────────────────────────────
    final thumbX = playedW.clamp(thumbR, size.width - thumbR);
    canvas.drawCircle(
      Offset(thumbX, cy),
      thumbR,
      Paint()..color = Colors.white,
    );
    // Subtle shadow on thumb
    canvas.drawCircle(
      Offset(thumbX, cy),
      thumbR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      old.played != played || old.buffered != buffered;
}

// =============================================================================
// Speed picker popup
// =============================================================================

class _SpeedPicker extends StatelessWidget {
  final MediaController controller;
  final List<double> speeds;
  final ValueChanged<double> onSelected;
  final VoidCallback onDismiss;

  const _SpeedPicker({
    required this.controller,
    required this.speeds,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return _Popup(
      title: 'Speed',
      onDismiss: onDismiss,
      children: speeds.map((s) {
        final isCurrent = (controller.speed - s).abs() < 0.01;
        return _PopupItem(
          label: s == 1.0 ? 'Normal' : '${s}x',
          trailing: isCurrent
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : null,
          isSelected: isCurrent,
          onTap: () => onSelected(s),
        );
      }).toList(),
    );
  }
}

// =============================================================================
// Quality picker popup
// =============================================================================

class _QualityPicker extends StatelessWidget {
  final MediaController controller;
  final ValueChanged<QualityTrack?> onSelected;
  final VoidCallback onDismiss;

  const _QualityPicker({
    required this.controller,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = controller.qualityTracks;
    final selected = controller.selectedQualityTrack;

    return _Popup(
      title: 'Quality',
      onDismiss: onDismiss,
      children: [
        // Auto entry
        _PopupItem(
          label: 'Auto',
          isSelected: selected == null,
          trailing: selected == null
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : null,
          onTap: () => onSelected(null),
        ),
        ...tracks.map((t) {
          final isCurrent = selected?.id == t.id;
          return _PopupItem(
            label: t.name,
            trailing: isCurrent
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
            isSelected: isCurrent,
            onTap: () => onSelected(t),
          );
        }),
      ],
    );
  }
}

// =============================================================================
// Shared popup shell
// =============================================================================

class _Popup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback onDismiss;

  const _Popup({
    required this.title,
    required this.children,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
        decoration: BoxDecoration(
          color: const Color(0xE0282828),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onDismiss,
                    child: const Icon(Icons.close,
                        color: Colors.white54, size: 16),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PopupItem extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final bool isSelected;
  final VoidCallback onTap;

  const _PopupItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: isSelected
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(28),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Seek flash indicator (double-tap feedback)
// =============================================================================

/// Animated icon+label that flashes when the user double-taps to seek.
class _SeekFlashIndicator extends StatelessWidget {
  final AnimationController controller;
  final IconData icon;
  final String label;

  const _SeekFlashIndicator({
    required this.controller,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Fade in quickly, then out.
        final t = controller.value;
        final opacity = t < 0.2
            ? (t / 0.2)
            : t < 0.6
                ? 1.0
                : 1.0 - ((t - 0.6) / 0.4);

        if (opacity <= 0) return const SizedBox.shrink();

        return Center(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Reusable atomic widgets
// =============================================================================

/// Large animated play / pause button with a filled circle background.
class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              key: ValueKey(isPlaying),
              color: Colors.white,
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small semi-transparent icon button used in the overlay.
class _ControlIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  const _ControlIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

/// A pill-shaped badge button for speed / quality labels.
class _BadgeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BadgeButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Info box — used in the explanation body
// =============================================================================

class _InfoBox extends StatelessWidget {
  final Widget child;
  const _InfoBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

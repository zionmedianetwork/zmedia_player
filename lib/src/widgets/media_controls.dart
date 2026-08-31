import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import '../models/cast_device.dart';
import 'media_player_widget.dart';
import 'airplay_button.dart';
import 'menus/settings_menu.dart';

/// Modern media controls widget with enhanced UX and smooth animations
class MediaControls extends StatefulWidget {
  /// Media controller for this controls widget
  final MediaController controller;

  /// Whether to show the fullscreen button
  final bool allowFullscreen;

  /// Whether to show subtitle controls
  final bool showSubtitleControls;

  /// Whether to show speed controls
  final bool showSpeedControls;

  /// Whether to show volume controls
  final bool showVolumeControls;

  /// Whether to show playlist navigation controls
  final bool showPlaylistControls;

  /// Whether to show cast button
  final bool showCastButton;

  /// Whether to show PiP button
  final bool showPipButton;

  /// Whether to show settings button
  final bool showSettingsButton;

  /// Custom color scheme for the controls
  final MediaControlsTheme? theme;

  /// Custom title to display
  final String? title;

  /// Called when the empty background of the overlay is tapped.
  ///
  /// The overlay covers the whole video surface while visible, so this is the
  /// hook [MediaPlayerWidget] uses to forward its own `onTap` callback and
  /// keep it firing identically whether the overlay is visible or hidden.
  ///
  /// Carries no position; use [onBackgroundTapDown] when the tap location
  /// matters. Both may be supplied and both fire, [onBackgroundTapDown]
  /// first.
  ///
  /// When both are `null` the historical behavior applies: a background tap
  /// calls [MediaController.showControlsTemporarily], which simply restarts
  /// the auto-hide countdown. Supplying *either* callback replaces that
  /// default. Buttons rendered on top of the background take precedence over
  /// these callbacks.
  final VoidCallback? onBackgroundTap;

  /// Position-carrying counterpart of [onBackgroundTap].
  ///
  /// The background detector fills the entire overlay, which in turn fills
  /// the player's own box, so `details.localPosition` is measured from the
  /// top-left of the player — the same origin and the same box as
  /// `MediaPlayerWidget.onTapDown` reports when the overlay is hidden.
  final GestureTapDownCallback? onBackgroundTapDown;

  /// Called when the empty background of the overlay is double-tapped.
  ///
  /// [MediaPlayerWidget] forwards its own `onDoubleTap` (or the built-in
  /// toggle-play/pause behavior) here so a double tap does the same thing
  /// whether the overlay is visible or hidden. When this *and*
  /// [onBackgroundDoubleTapDown] are `null`, no double-tap recognizer is
  /// installed at all, which also keeps background single taps from being
  /// delayed by the double-tap timeout.
  final VoidCallback? onBackgroundDoubleTap;

  /// Position-carrying counterpart of [onBackgroundDoubleTap].
  ///
  /// This is what makes direction-aware double-tap seek work with the default
  /// controls: [MediaPlayerWidget] forwards its own `onDoubleTapDown` here,
  /// and because the background detector spans the player's own box, the
  /// `localPosition` a host receives is identical whether the overlay was
  /// visible (this path) or hidden (the player's own tap detector).
  ///
  /// Fires *before* [onBackgroundDoubleTap] when both are supplied.
  final GestureTapDownCallback? onBackgroundDoubleTapDown;

  const MediaControls({
    super.key,
    required this.controller,
    this.allowFullscreen = true,
    this.showSubtitleControls = true,
    this.showSpeedControls = true,
    this.showVolumeControls = true,
    this.showPlaylistControls = true,
    this.showCastButton = true,
    this.showPipButton = true,
    this.showSettingsButton = true,
    this.theme,
    this.title,
    this.onBackgroundTap,
    this.onBackgroundTapDown,
    this.onBackgroundDoubleTap,
    this.onBackgroundDoubleTapDown,
  });

  @override
  State<MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<MediaControls>
    with TickerProviderStateMixin {
  bool _showVolumeSlider = false;
  bool _showSpeedMenu = false;
  bool _showSubtitleMenu = false;
  bool _showCastMenu = false;
  bool _isDraggingProgress = false;
  double _dragValue = 0.0;
  List<CastDevice> _castDevices = [];

  StreamSubscription<List<CastDevice>>? _castDevicesSubscription;

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _overlayController;
  late Animation<double> _fadeAnimation;
  // ignore: unused_field
  late Animation<double> _scaleAnimation;
  late Animation<double> _overlayAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCastDevices();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOutBack,
    );

    _fadeController.forward();
  }

  void _initializeCastDevices() {
    // Listen to cast devices stream — store subscription for cancellation
    _castDevicesSubscription =
        widget.controller.player.castDevicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _castDevices = devices;
        });
      }
    });
  }

  @override
  void dispose() {
    _castDevicesSubscription?.cancel();
    _fadeController.dispose();
    _scaleController.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? MediaControlsTheme.defaultTheme;

    // Rebuild scope, accurately described:
    // - `widget.controller` (a ChangeNotifier) no longer calls
    //   notifyListeners() for position-only changes -- MediaController
    //   routes throttled position updates through the dedicated
    //   `positionListenable` instead (see
    //   MediaController.positionListenable). So none of the
    //   ListenableBuilder(listenable: widget.controller) subtrees below
    //   (main controls row, top bar, buffering overlay) rebuild on the
    //   ~2/sec position tick anymore; they still rebuild -- as whole
    //   subtrees, not scoped to a single button -- on genuine state changes
    //   (play/pause, buffering, casting, tracks, volume, speed,
    //   controlsVisible).
    // - The seek bar and time text in the bottom bar are the only parts
    //   that actually need to update every tick; they are the only
    //   subtrees wrapped in ValueListenableBuilder<Duration>(valueListenable:
    //   widget.controller.positionListenable), which is what genuinely
    //   limits per-tick rebuild scope to just those two.
    return FadeTransition(
      opacity: _fadeAnimation,
      child: RepaintBoundary(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.5,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.1),
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Background gesture detector.  This is the bottom-most child
              // of the overlay stack, so every control rendered above it wins
              // the gesture first; it only sees taps on empty overlay space.
              GestureDetector(
                // Position-carrying variants are forwarded verbatim and fire
                // before their bare counterparts.  Supplying EITHER variant
                // means the caller owns the gesture, so the overlay's own
                // default (restart the auto-hide countdown) is suppressed --
                // mirroring MediaPlayerWidget's tap-detector rule exactly.
                onTapDown: widget.onBackgroundTapDown,
                onTap: widget.onBackgroundTap ??
                    (widget.onBackgroundTapDown == null
                        ? () => widget.controller.showControlsTemporarily()
                        : null),
                onDoubleTapDown: widget.onBackgroundDoubleTapDown,
                onDoubleTap: widget.onBackgroundDoubleTap,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.transparent,
                ),
              ),

              // Center controls — only rebuilds when play state changes
              _buildMainControls(theme),

              // Top controls — static chrome, no per-tick rebuild
              _buildTopControls(theme),

              // Bottom controls — the inner seek bar + time text use their
              // own scoped ListenableBuilder; the outer gradient shell is const
              _buildBottomControls(theme),

              // Animated overlays
              if (_showVolumeSlider) _buildVolumeOverlay(theme),
              if (_showSpeedMenu) _buildSpeedMenu(theme),
              if (_showSubtitleMenu) _buildSubtitleMenu(theme),
              if (_showCastMenu) _buildCastMenu(theme),

              // Loading overlay — scoped to buffering state
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  if (widget.controller.state.state == PlayerState.buffering) {
                    return _buildBufferingOverlay(theme);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainControls(MediaControlsTheme theme) {
    // NOTE: this ListenableBuilder wraps the entire Row below (previous/
    // next, both seek-10 buttons, and the play/pause button) -- it is not
    // scoped to just the play/pause button. What actually keeps this cheap
    // is that `widget.controller` no longer notifies on position-only
    // ticks (see MediaController.positionListenable), so this whole Row
    // only rebuilds on genuine state changes -- play/pause, playlist
    // next/previous availability, etc. -- a handful of times per session,
    // not on the ~2/sec position tick.
    return Center(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Previous track
              if (widget.showPlaylistControls &&
                  widget.controller.hasPrevious) ...[
                Semantics(
                  button: true,
                  label: 'Previous track',
                  child: _buildCenterControlButton(
                    icon: FluentIcons.previous_20_regular,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.controller.skipToPrevious();
                    },
                    tooltip: 'Previous',
                  ),
                ),
                const SizedBox(width: 32),
              ],

              // Seek backward
              Semantics(
                button: true,
                label: 'Rewind 10 seconds',
                child: _buildCenterControlButton(
                  icon: FluentIcons.rewind_20_regular,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.controller.seekBackward();
                  },
                  tooltip: 'Rewind 10s',
                ),
              ),

              const SizedBox(width: 40),

              // Play/Pause button — only this part changes per-tick (play state)
              _buildPlayPauseButton(theme),

              const SizedBox(width: 40),

              // Seek forward
              Semantics(
                button: true,
                label: 'Forward 10 seconds',
                child: _buildCenterControlButton(
                  icon: FluentIcons.fast_forward_20_regular,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.controller.seekForward();
                  },
                  tooltip: 'Forward 10s',
                ),
              ),

              if (widget.showPlaylistControls && widget.controller.hasNext) ...[
                const SizedBox(width: 32),
                Semantics(
                  button: true,
                  label: 'Next track',
                  child: _buildCenterControlButton(
                    icon: FluentIcons.next_20_regular,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.controller.skipToNext();
                    },
                    tooltip: 'Next',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCenterControlButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(MediaControlsTheme theme) {
    switch (widget.controller.state.state) {
      case PlayerState.playing:
        return Semantics(
          button: true,
          label: 'Pause',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.controller.pause();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                FluentIcons.pause_24_regular,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        );
      case PlayerState.paused:
      case PlayerState.ready:
      case PlayerState.completed:
        return Semantics(
          button: true,
          label: 'Play',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.controller.play();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                FluentIcons.play_24_regular,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        );
      case PlayerState.buffering:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(32),
          ),
          child: const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
            ),
          ),
        );
      default:
        return Semantics(
          button: true,
          label: 'Play',
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(
              FluentIcons.play_24_regular,
              color: Colors.white.withValues(alpha: 0.5),
              size: 32,
            ),
          ),
        );
    }
  }

  Widget _buildTopControls(MediaControlsTheme theme) {
    // This ListenableBuilder rebuilds the entire top bar on every
    // `widget.controller` notification -- it is not scoped to a sub-widget.
    // It no longer rebuilds on position ticks specifically because
    // MediaController does not notify listeners for position-only changes
    // (see MediaController.positionListenable); it still rebuilds on the
    // real state changes this bar needs to reflect (cast status, PiP
    // availability, etc.).
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final isCasting = widget.controller.isCasting;
        final showCastButton = widget.showCastButton;

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: Row(
                children: [
                  // Back / collapse button
                  Semantics(
                    button: true,
                    label: 'Exit fullscreen',
                    child: GestureDetector(
                      onTap: () {
                        if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          FluentIcons.arrow_left_20_regular,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Action buttons — right aligned
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cast button (Android) or AirPlay button (iOS)
                      if (showCastButton)
                        Platform.isIOS
                            ? const AirPlayButton(size: 24)
                            : Semantics(
                                button: true,
                                label: isCasting ? 'Disconnect cast' : 'Cast',
                                child: _buildTopActionButton(
                                  icon: isCasting
                                      ? FluentIcons.cast_20_filled
                                      : FluentIcons.cast_20_regular,
                                  isActive: isCasting,
                                  onTap: _toggleCastMenu,
                                  tooltip: isCasting ? 'Connected' : 'Cast',
                                ),
                              ),

                      if (showCastButton) const SizedBox(width: 12),

                      // PiP button
                      if (widget.showPipButton &&
                          widget.controller.isPipAvailable) ...[
                        Semantics(
                          button: true,
                          label: 'Picture in picture',
                          child: _buildTopActionButton(
                            icon: FluentIcons.picture_in_picture_20_regular,
                            onTap: _enterPictureInPicture,
                            tooltip: 'Picture in Picture',
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // Settings button
                      if (widget.showSettingsButton)
                        Semantics(
                          button: true,
                          label: 'Settings',
                          child: _buildTopActionButton(
                            icon: FluentIcons.settings_20_regular,
                            isActive: false,
                            onTap: _toggleSettingsMenu,
                            tooltip: 'Settings',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.orange.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? Border.all(
                  color: Colors.orange.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.orange : Colors.white,
          size: 20,
        ),
      ),
    );
  }

  IconData _getVolumeIcon(double volume) {
    if (volume > 0.6) return FluentIcons.speaker_2_20_regular;
    if (volume > 0.3) return FluentIcons.speaker_1_20_regular;
    if (volume > 0) return FluentIcons.speaker_0_20_regular;
    return FluentIcons.speaker_mute_20_regular;
  }

  Widget _buildBottomControls(MediaControlsTheme theme) {
    // The gradient container and fullscreen button are static chrome built
    // directly here (not inside a builder), so they only rebuild when this
    // whole method re-runs. Only the seek bar and time text need to update
    // on every position tick, so those two -- and only those two -- are
    // each wrapped in RepaintBoundary + ValueListenableBuilder<Duration>
    // scoped to widget.controller.positionListenable, the dedicated,
    // throttled position signal that fires independently of
    // notifyListeners() (see MediaController.positionListenable).
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seek bar + live indicator — scoped to positionListenable,
                // not the whole controller, + repaint boundary.
                RepaintBoundary(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: widget.controller.positionListenable,
                    builder: (context, _, __) {
                      final isLive = widget.controller.player.isLive;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: isLive
                            ? _buildLiveIndicator(theme)
                            : _buildModernProgressBar(theme),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 2),

                // Time display (per-tick) + fullscreen button (static)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      // Time text — only this Text rebuilds per tick, via
                      // positionListenable (not the whole controller).
                      RepaintBoundary(
                        child: ValueListenableBuilder<Duration>(
                          valueListenable: widget.controller.positionListenable,
                          builder: (context, _, __) {
                            final isLive = widget.controller.player.isLive;
                            if (isLive) return const SizedBox.shrink();
                            final timeText = _isDraggingProgress
                                ? '${_formatDuration(widget.controller.duration * _dragValue)} / ${widget.controller.formattedDuration}'
                                : '${widget.controller.formattedPosition} / ${widget.controller.formattedDuration}';
                            return Text(
                              timeText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            );
                          },
                        ),
                      ),

                      const Spacer(),

                      // Fullscreen button — static, no rebuild needed
                      if (widget.allowFullscreen)
                        Semantics(
                          button: true,
                          label: 'Fullscreen',
                          child: GestureDetector(
                            onTap: _toggleFullscreen,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                FluentIcons.full_screen_maximize_20_regular,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveIndicator(MediaControlsTheme theme) {
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.5),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernProgressBar(MediaControlsTheme theme) {
    final progress =
        _isDraggingProgress ? _dragValue : widget.controller.progress;

    return SizedBox(
      height: 32,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 6,
            disabledThumbRadius: 6,
          ),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          activeTrackColor: Colors.orange, // Orange as per template
          inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
          overlayColor: Colors.orange.withValues(alpha: 0.2),
          thumbColor: Colors.orange,
        ),
        child: Slider(
          value: progress,
          onChanged: (value) {
            setState(() {
              _isDraggingProgress = true;
              _dragValue = value;
            });
          },
          onChangeStart: (value) {
            setState(() => _isDraggingProgress = true);
            widget.controller.showControlsTemporarily();
            HapticFeedback.selectionClick();
          },
          onChangeEnd: (value) {
            final position = widget.controller.duration * value;
            widget.controller.seekTo(position);
            setState(() => _isDraggingProgress = false);
            HapticFeedback.lightImpact();
          },
        ),
      ),
    );
  }

  Widget _buildVolumeOverlay(MediaControlsTheme theme) {
    return Positioned(
      right: 16,
      top: 80,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.5, 0),
          end: Offset.zero,
        ).animate(_overlayController),
        child: Container(
          height: 180,
          width: 50,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.controller.toggleMute();
                },
                icon: Icon(
                  widget.controller.isMuted
                      ? FluentIcons.speaker_mute_20_regular
                      : _getVolumeIcon(widget.controller.volume),
                  color: theme.iconColor,
                  size: 20,
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: theme.progressColor,
                        inactiveTrackColor: theme.progressBackgroundColor,
                      ),
                      child: Slider(
                        value: widget.controller.isMuted
                            ? 0.0
                            : widget.controller.volume,
                        onChanged: (value) {
                          if (widget.controller.isMuted && value > 0) {
                            widget.controller.toggleMute();
                          }
                          widget.controller.setVolume(value);
                          if (value > 0) HapticFeedback.selectionClick();
                        },
                      ),
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

  Widget _buildSpeedMenu(MediaControlsTheme theme) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return Positioned(
      right: 16,
      top: 80,
      child: FadeTransition(
        opacity: _overlayAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.5, 0),
            end: Offset.zero,
          ).animate(_overlayController),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: speeds.map((speed) {
                final isSelected = widget.controller.speed == speed;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.controller.setSpeed(speed);
                      _toggleSpeedMenu();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: isSelected
                          ? BoxDecoration(
                              color:
                                  theme.activeIconColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(
                        '${speed}x',
                        style: TextStyle(
                          color: isSelected
                              ? theme.activeIconColor
                              : theme.textColor,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleMenu(MediaControlsTheme theme) {
    final tracks = [
      null, // Off option
      ...widget.controller.subtitleTracks,
    ];

    return Positioned(
      right: 16,
      top: 80,
      child: FadeTransition(
        opacity: _overlayAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.5, 0),
            end: Offset.zero,
          ).animate(_overlayController),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: tracks.map((track) {
                final isSelected = track == null
                    ? widget.controller.selectedSubtitleTrack == null
                    : widget.controller.selectedSubtitleTrack?.id == track.id;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.controller.setSubtitleTrack(track);
                      _toggleSubtitleMenu();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: isSelected
                          ? BoxDecoration(
                              color:
                                  theme.activeIconColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Icon(
                              FluentIcons.checkmark_circle_20_regular,
                              color: theme.activeIconColor,
                              size: 16,
                            ),
                          if (isSelected) const SizedBox(width: 8),
                          Text(
                            track?.title ?? 'Off',
                            style: TextStyle(
                              color: isSelected
                                  ? theme.activeIconColor
                                  : theme.textColor,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCastMenu(MediaControlsTheme theme) {
    return Positioned(
      right: 16,
      top: 80,
      child: FadeTransition(
        opacity: _overlayAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.5, 0),
            end: Offset.zero,
          ).animate(_overlayController),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 400),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.cast_20_regular,
                        color: theme.activeIconColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Cast to Device',
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Device list
                if (_castDevices.isEmpty && !widget.controller.isCasting)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: theme.activeIconColor,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Looking for devices...',
                          style: TextStyle(
                            color: theme.textColor.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Disconnect option if currently casting
                        if (widget.controller.isCasting)
                          _buildCastDeviceItem(
                            theme: theme,
                            device: widget.controller.castStatus.device!,
                            isConnected: true,
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              try {
                                await widget.controller
                                    .disconnectFromCastDevice();
                                if (mounted) {
                                  _toggleCastMenu();
                                }
                              } catch (e) {
                                debugPrint('Failed to disconnect: $e');
                              }
                            },
                          ),

                        // Available devices
                        ..._castDevices.where((device) {
                          // Don't show currently connected device again
                          return !widget.controller.isCasting ||
                              device.id !=
                                  widget.controller.castStatus.device?.id;
                        }).map((device) {
                          return _buildCastDeviceItem(
                            theme: theme,
                            device: device,
                            isConnected: false,
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              try {
                                // Connect to the device and load current media
                                await widget.controller
                                    .connectAndLoadMedia(device);
                                if (mounted) {
                                  _toggleCastMenu();
                                }
                              } catch (e) {
                                debugPrint(
                                    'Failed to connect or load media: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Failed to connect: ${e.toString()}'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCastDeviceItem({
    required MediaControlsTheme theme,
    required CastDevice device,
    required bool isConnected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: isConnected
              ? BoxDecoration(
                  color: theme.activeIconColor.withValues(alpha: 0.15),
                )
              : null,
          child: Row(
            children: [
              Icon(
                _getCastDeviceIcon(device.type),
                color: isConnected ? theme.activeIconColor : theme.iconColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 14,
                        fontWeight:
                            isConnected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isConnected)
                      Text(
                        'Connected',
                        style: TextStyle(
                          color: theme.activeIconColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              if (isConnected)
                Icon(
                  FluentIcons.checkmark_circle_20_regular,
                  color: theme.activeIconColor,
                  size: 20,
                )
              else
                Icon(
                  FluentIcons.chevron_right_20_regular,
                  color: theme.iconColor.withValues(alpha: 0.5),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCastDeviceIcon(CastDeviceType type) {
    switch (type) {
      case CastDeviceType.chromecast:
        return FluentIcons.cast_20_regular;
      case CastDeviceType.airplay:
        return FluentIcons.cast_20_regular;
      default:
        return FluentIcons.cast_20_regular;
    }
  }

  Widget _buildBufferingOverlay(MediaControlsTheme theme) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: theme.progressColor,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading...',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSpeedMenu() {
    setState(() {
      _showSpeedMenu = !_showSpeedMenu;
      _showVolumeSlider = false;
      _showSubtitleMenu = false;
      _showCastMenu = false;
    });

    if (_showSpeedMenu) {
      _overlayController.forward();
    } else {
      _overlayController.reverse();
    }

    widget.controller.showControlsTemporarily();
    HapticFeedback.lightImpact();
  }

  void _toggleSubtitleMenu() {
    setState(() {
      _showSubtitleMenu = !_showSubtitleMenu;
      _showVolumeSlider = false;
      _showSpeedMenu = false;
      _showCastMenu = false;
    });

    if (_showSubtitleMenu) {
      _overlayController.forward();
    } else {
      _overlayController.reverse();
    }

    widget.controller.showControlsTemporarily();
    HapticFeedback.lightImpact();
  }

  void _toggleSettingsMenu() {
    HapticFeedback.lightImpact();
    widget.controller.showControlsTemporarily();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SettingsMenu(
        controller: widget.controller,
        onSettingChanged: () {
          // Refresh UI if needed
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  void _toggleCastMenu() {
    setState(() {
      _showCastMenu = !_showCastMenu;
      _showVolumeSlider = false;
      _showSpeedMenu = false;
      _showSubtitleMenu = false;
    });

    if (_showCastMenu) {
      _overlayController.forward();
      // Start cast discovery when menu is opened
      widget.controller.startCastDiscovery().catchError((e) {
        debugPrint('Failed to start cast discovery: $e');
      });
    } else {
      _overlayController.reverse();
      // Stop cast discovery when menu is closed
      widget.controller.stopCastDiscovery().catchError((e) {
        debugPrint('Failed to stop cast discovery: $e');
      });
    }

    widget.controller.showControlsTemporarily();
    HapticFeedback.lightImpact();
  }

  void _enterPictureInPicture() async {
    try {
      HapticFeedback.lightImpact();
      final success = await widget.controller.player.enterPictureInPicture();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to enter Picture-in-Picture mode'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _toggleFullscreen() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullscreenPlayerRoute(
          controller: widget.controller,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}

// Custom animated icon button widget
class _AnimatedIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final double size;
  final String? tooltip;

  const _AnimatedIconButton({
    required this.onPressed,
    required this.icon,
    required this.color,
    required this.size,
    // ignore: unused_element_parameter
    this.tooltip,
  });

  @override
  State<_AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<_AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _animation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _animation,
        child: IconButton(
          onPressed: widget.onPressed,
          icon: Icon(
            widget.icon,
            color: widget.color,
            size: widget.size,
          ),
          tooltip: widget.tooltip,
        ),
      ),
    );
  }
}

// Modern icon button with background
class _ModernIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final double size;
  final String? tooltip;
  final bool isActive;
  final String? badge;

  const _ModernIconButton({
    required this.onPressed,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    // ignore: unused_element_parameter
    this.size = 24,
    // ignore: unused_element_parameter
    this.tooltip,
    // ignore: unused_element_parameter
    this.isActive = false,
    // ignore: unused_element_parameter
    this.badge,
  });

  @override
  State<_ModernIconButton> createState() => _ModernIconButtonState();
}

class _ModernIconButtonState extends State<_ModernIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.backgroundColor,
                border: widget.isActive
                    ? Border.all(
                        color: widget.color.withValues(alpha: 0.5), width: 2)
                    : null,
                boxShadow: [
                  if (widget.isActive)
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: 0.2 + _glowAnimation.value * 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: widget.onPressed,
                    icon: Icon(
                      widget.icon,
                      color: widget.color,
                      size: widget.size,
                    ),
                    tooltip: widget.tooltip,
                  ),
                  if (widget.badge != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: widget.color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Custom slider thumb shape
class CustomSliderThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;
  final Color color;

  const CustomSliderThumbShape({
    required this.enabledThumbRadius,
    required this.color,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(enabledThumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawCircle(
      center + const Offset(0, 2),
      enabledThumbRadius,
      shadowPaint,
    );

    // Draw thumb
    final thumbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, enabledThumbRadius, thumbPaint);

    // Draw inner circle
    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, enabledThumbRadius * 0.4, innerPaint);
  }
}

// Custom track shape
class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = true,
    double additionalActiveTrackHeight = 2,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Canvas canvas = context.canvas;
    final radius = trackRect.height / 2;

    // Draw inactive track with shadow
    final inactiveTrackPaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final inactiveRRect = RRect.fromRectAndRadius(
      trackRect.translate(0, 1),
      Radius.circular(radius),
    );

    canvas.drawRRect(inactiveRRect, shadowPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(radius)),
      inactiveTrackPaint,
    );

    // Draw active track with gradient
    final activeTrackRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );

    final gradient = LinearGradient(
      colors: [
        sliderTheme.activeTrackColor ?? Colors.blue,
        (sliderTheme.activeTrackColor ?? Colors.blue).withValues(alpha: 0.8),
      ],
    );

    final activeTrackPaint = Paint()
      ..shader = gradient.createShader(activeTrackRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(activeTrackRect, Radius.circular(radius)),
      activeTrackPaint,
    );
  }
}

/// Enhanced theme configuration for media controls
class MediaControlsTheme {
  /// Primary icon color
  final Color iconColor;

  /// Active/selected icon color
  final Color activeIconColor;

  /// Text color
  final Color textColor;

  /// Progress bar color
  final Color progressColor;

  /// Progress bar background color
  final Color progressBackgroundColor;

  /// Background color for overlays
  final Color overlayBackgroundColor;

  /// Accent color for highlights
  final Color accentColor;

  /// Surface color for cards and containers
  final Color surfaceColor;

  const MediaControlsTheme({
    this.iconColor = Colors.white,
    this.activeIconColor = const Color(0xFF00C9FF),
    this.textColor = Colors.white,
    this.progressColor = const Color(0xFF00C9FF),
    this.progressBackgroundColor = Colors.white24,
    this.overlayBackgroundColor = Colors.black54,
    this.accentColor = const Color(0xFF0099CC),
    this.surfaceColor = const Color(0xFF1E1E1E),
  });

  /// Default modern theme with orange accents (matching template)
  static const defaultTheme = MediaControlsTheme(
    iconColor: Colors.white,
    activeIconColor: Colors.orange,
    textColor: Colors.white,
    progressColor: Colors.orange,
    progressBackgroundColor: Colors.white24,
    accentColor: Colors.orange,
    surfaceColor: Color(0xFF1E1E1E),
  );

  /// Dark theme with blue accents
  static const darkTheme = MediaControlsTheme(
    iconColor: Colors.white,
    activeIconColor: Color(0xFF64B5F6),
    textColor: Colors.white,
    progressColor: Color(0xFF64B5F6),
    progressBackgroundColor: Colors.white24,
    accentColor: Color(0xFF42A5F5),
    surfaceColor: Color(0xFF212121),
  );

  /// Light theme
  static const lightTheme = MediaControlsTheme(
    iconColor: Colors.black87,
    activeIconColor: Color(0xFF1976D2),
    textColor: Colors.black87,
    progressColor: Color(0xFF1976D2),
    progressBackgroundColor: Colors.black26,
    overlayBackgroundColor: Colors.white70,
    accentColor: Color(0xFF1565C0),
    surfaceColor: Colors.white,
  );

  /// Gaming theme with neon accents
  static const gamingTheme = MediaControlsTheme(
    iconColor: Colors.white,
    activeIconColor: Color(0xFF00FF88),
    textColor: Colors.white,
    progressColor: Color(0xFF00FF88),
    progressBackgroundColor: Colors.white24,
    overlayBackgroundColor: Color(0xFF0A0A0A),
    accentColor: Color(0xFF00DD77),
    surfaceColor: Color(0xFF1A1A1A),
  );
}

/// Enhanced fullscreen player route with modern transitions
class _FullscreenPlayerRoute extends StatefulWidget {
  final MediaController controller;

  const _FullscreenPlayerRoute({
    required this.controller,
  });

  @override
  State<_FullscreenPlayerRoute> createState() => _FullscreenPlayerRouteState();
}

class _FullscreenPlayerRouteState extends State<_FullscreenPlayerRoute>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  bool _isExiting = false;
  List<DeviceOrientation>? _previousOrientations;
  SystemUiMode? _previousSystemUiMode;

  @override
  void initState() {
    super.initState();

    // Store previous settings - we'll use defaults since we can't retrieve current values
    _previousOrientations = [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    _previousSystemUiMode = SystemUiMode.edgeToEdge;

    // Force landscape orientation for fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Hide system UI for truly immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _slideController.forward();
  }

  @override
  void dispose() {
    // Restore previous settings
    _restoreSystemSettings();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _restoreSystemSettings() async {
    try {
      // Restore system UI
      if (_previousSystemUiMode != null) {
        await SystemChrome.setEnabledSystemUIMode(_previousSystemUiMode!);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      // Restore orientations
      if (_previousOrientations != null && _previousOrientations!.isNotEmpty) {
        await SystemChrome.setPreferredOrientations(_previousOrientations!);
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } catch (e) {
      debugPrint('Error restoring system settings: $e');
    }
  }

  Future<void> _exitFullscreen() async {
    if (_isExiting) return;

    setState(() => _isExiting = true);
    HapticFeedback.lightImpact();

    await _slideController.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SlideTransition(
          position: _slideAnimation,
          child: Stack(
            children: [
              // Fullscreen video player — FullscreenMediaPlayer renders its own
              // MediaControls overlay which owns the single top bar.  No
              // duplicate header or dead PiP button is added here.
              Positioned.fill(
                child: FullscreenMediaPlayer(
                  controller: widget.controller,
                  backgroundColor: Colors.black,
                ),
              ),

              // Gesture detector for swipe to exit - only in video area, not over controls
              Positioned(
                top: 100, // Start below the header controls
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta! > 10) {
                      _exitFullscreen();
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

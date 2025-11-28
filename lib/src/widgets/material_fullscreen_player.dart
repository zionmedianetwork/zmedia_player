import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/player_state.dart';
import '../models/network_status.dart';
import 'components/seek_bar.dart';
import 'components/time_display.dart';
import 'fullscreen_controls_base.dart';
import 'menus/settings_menu.dart';
import 'overlays/buffering_indicator.dart';
import 'overlays/network_quality_indicator.dart';

/// Material Design 3 fullscreen media player
///
/// Optimized for fullscreen playback with:
/// - Landscape orientation lock
/// - Immersive system UI mode (Android)
/// - Material Design 3 controls
/// - Exit fullscreen button
///
/// Example usage:
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (context) => Scaffold(
///       body: MediaPlayerWidget(
///         controller: mediaController,
///         customControls: MaterialFullscreenPlayer(
///           controller: mediaController,
///           title: 'Video Title',
///         ),
///       ),
///     ),
///   ),
/// );
/// ```
class MaterialFullscreenPlayer extends FullscreenControlsBase {
  /// Custom title to display
  final String? title;

  /// Whether to show settings button
  final bool showSettings;

  /// Whether to show PiP button
  final bool showPip;

  /// Custom color scheme (defaults to Theme.of(context).colorScheme)
  final ColorScheme? colorScheme;

  const MaterialFullscreenPlayer({
    super.key,
    required super.controller,
    this.title,
    this.showSettings = true,
    this.showPip = true,
    this.colorScheme,
    super.lockOrientation = true,
    super.preferredOrientations = const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
    super.systemUiMode = SystemUiMode.immersiveSticky,
    super.hideSystemUI = true,
    super.onExitFullscreen,
  });

  @override
  Widget buildFullscreenControls(BuildContext context, ControlsState state) {
    final theme = Theme.of(context);
    final colorScheme = this.colorScheme ?? theme.colorScheme;
    final textTheme = theme.textTheme;

    return AnimatedOpacity(
      opacity: state.animationValue,
      duration: const Duration(milliseconds: 300),
      child: state.isVisible
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 0.2, 0.8, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  // Main controls
                  Column(
                    children: [
                      // Top bar with title and exit button
                      _buildTopBar(context, colorScheme, textTheme, state),

                      const Spacer(),

                      // Center play/pause button
                      _buildCenterControls(colorScheme, state),

                      const Spacer(),

                      // Bottom bar with seek and controls
                      _buildBottomBar(colorScheme, textTheme, state),
                    ],
                  ),

                  // LIVE badge (lower left corner)
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      final isLive = controller.currentItem?.isLive ?? false;
                      if (!isLive) return const SizedBox.shrink();

                      return Positioned(
                        left: 16,
                        bottom: 80,
                        child: TimeDisplay(
                          position: Duration.zero,
                          isLive: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          liveColor: Colors.red,
                        ),
                      );
                    },
                  ),

                  // Network Quality Indicator (top-right corner)
                  Positioned(
                    top: 80,
                    right: 16,
                    child: StreamBuilder(
                      stream: controller.player.bandwidthStream,
                      builder: (context, bandwidthSnapshot) {
                        final bandwidth = bandwidthSnapshot.data ?? 0;
                        final networkQuality =
                            NetworkQuality.fromBandwidth(bandwidth);

                        if (networkQuality == NetworkQuality.unknown) {
                          return const SizedBox.shrink();
                        }

                        return NetworkQualityIndicator(
                          networkStatus: NetworkStatus(
                            quality: networkQuality,
                            downloadSpeed: bandwidth,
                            connectionType: ConnectionType.wifi,
                            isMetered: false,
                            signalStrength: _estimateSignalStrength(
                              networkQuality,
                            ),
                            timestamp: DateTime.now(),
                          ),
                          showDetails: true,
                          size: 18.0,
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    ControlsState state,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Exit fullscreen button
            _buildM3IconButton(
              icon: Icons.fullscreen_exit,
              onPressed: () {
                final widgetState = context
                    .findAncestorStateOfType<FullscreenControlsBaseState>();
                widgetState?.exitFullscreen();
              },
              tooltip: 'Exit Fullscreen',
              colorScheme: colorScheme,
            ),

            const SizedBox(width: 16),

            // Title
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            const Spacer(),

            // PiP button
            if (showPip)
              _buildM3IconButton(
                icon: Icons.picture_in_picture_alt,
                onPressed: () async {
                  await controller.enterPictureInPicture();
                },
                tooltip: 'Picture in Picture',
                colorScheme: colorScheme,
              ),

            const SizedBox(width: 8),

            // Settings button
            if (showSettings)
              _buildM3IconButton(
                icon: Icons.settings,
                onPressed: () {
                  _showSettingsMenu(context, colorScheme);
                },
                tooltip: 'Settings',
                colorScheme: colorScheme,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls(ColorScheme colorScheme, ControlsState state) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final playerState = controller.state.state;
        final isPlaying = controller.isPlaying;
        final isLoading = playerState == PlayerState.buffering;

        // Show BufferingIndicator when buffering
        if (isLoading) {
          return StreamBuilder(
            stream: controller.player.bufferHealthStream,
            builder: (context, bufferSnapshot) {
              if (bufferSnapshot.hasData && bufferSnapshot.data != null) {
                return BufferingIndicator(
                  bufferHealth: bufferSnapshot.data!,
                  showDetails: true,
                  size: 80.0,
                  backgroundColor: Colors.black.withValues(alpha: 0.8),
                );
              }
              // Fallback to simple indicator
              return SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  color: colorScheme.primary,
                  strokeWidth: 3,
                ),
              );
            },
          );
        }

        // Show playback controls when not buffering
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Skip backward (if available)
            _buildM3IconButton(
              icon: Icons.replay_10,
              onPressed: () {
                final currentPos = controller.position;
                final newPos = currentPos - const Duration(seconds: 10);
                controller.seekTo(
                  newPos.isNegative ? Duration.zero : newPos,
                );
              },
              tooltip: 'Rewind 10 seconds',
              colorScheme: colorScheme,
              size: 40,
            ),

            const SizedBox(width: 24),

            // Play/Pause button
            _buildM3IconButton(
              icon: isPlaying ? Icons.pause : Icons.play_arrow,
              onPressed: controller.togglePlayPause,
              tooltip: isPlaying ? 'Pause' : 'Play',
              colorScheme: colorScheme,
              size: 64,
              filled: true,
            ),

            const SizedBox(width: 24),

            // Skip forward (if available)
            _buildM3IconButton(
              icon: Icons.forward_10,
              onPressed: () {
                final currentPos = controller.position;
                final duration = controller.duration;
                final newPos = currentPos + const Duration(seconds: 10);
                controller.seekTo(
                  newPos > duration ? duration : newPos,
                );
              },
              tooltip: 'Forward 10 seconds',
              colorScheme: colorScheme,
              size: 40,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(
    ColorScheme colorScheme,
    TextTheme textTheme,
    ControlsState state,
  ) {
    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seek bar
            AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                final position = controller.position;
                final duration = controller.duration;
                final value = duration.inMilliseconds > 0
                    ? position.inMilliseconds / duration.inMilliseconds
                    : 0.0;

                return SeekBar(
                  value: value.clamp(0.0, 1.0),
                  duration: duration,
                  onChanged: (newValue) {
                    final seekTo = duration * newValue;
                    controller.seekTo(seekTo);
                  },
                  activeColor: colorScheme.primary,
                  inactiveColor: colorScheme.onSurface.withValues(alpha: 0.3),
                  thumbColor: colorScheme.primary,
                );
              },
            ),

            const SizedBox(height: 12),

            // Time and volume controls
            Row(
              children: [
                // Time display
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    return TimeDisplay(
                      position: controller.position,
                      duration: controller.duration,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    );
                  },
                ),

                const Spacer(),

                // Volume button
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    final volume = controller.volume;
                    final isMuted = volume == 0;

                    return _buildM3IconButton(
                      icon: isMuted
                          ? Icons.volume_off
                          : volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      onPressed: () {
                        if (isMuted) {
                          controller.setVolume(1.0);
                        } else {
                          controller.setVolume(0);
                        }
                      },
                      tooltip: isMuted ? 'Unmute' : 'Mute',
                      colorScheme: colorScheme,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildM3IconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    required ColorScheme colorScheme,
    double size = 24,
    bool filled = false,
  }) {
    return IconButton(
      icon: Icon(icon, size: size),
      onPressed: onPressed,
      tooltip: tooltip,
      style: filled
          ? IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
            )
          : IconButton.styleFrom(
              foregroundColor: colorScheme.onSurface,
            ),
    );
  }

  void _showSettingsMenu(BuildContext context, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: SettingsMenu(
          controller: controller,
        ),
      ),
    );
  }

  /// Estimate signal strength from network quality
  double _estimateSignalStrength(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return 1.0;
      case NetworkQuality.good:
        return 0.75;
      case NetworkQuality.fair:
        return 0.5;
      case NetworkQuality.poor:
        return 0.25;
      case NetworkQuality.offline:
      case NetworkQuality.unknown:
        return 0.0;
    }
  }
}

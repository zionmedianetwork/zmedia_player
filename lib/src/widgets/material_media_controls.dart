import 'package:flutter/material.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import 'components/seek_bar.dart';
import 'components/time_display.dart';
import 'menus/settings_menu.dart';

/// Material Design 3 media controls widget
///
/// Implements Material Design 3 design language with:
/// - Filled and tonal buttons
/// - Material color scheme integration
/// - Material motion system (standard easing)
/// - Elevation and shadows
/// - Material typography
/// - State layers for interactive elements
///
/// Example usage:
/// ```dart
/// MaterialMediaControls(
///   controller: mediaController,
///   title: 'Video Title',
/// )
/// ```
class MaterialMediaControls extends StatefulWidget {
  /// Media controller for this controls widget
  final MediaController controller;

  /// Whether to show the fullscreen button
  final bool showFullscreen;

  /// Whether to show settings button
  final bool showSettings;

  /// Whether to show PiP button
  final bool showPip;

  /// Custom title to display
  final String? title;

  /// Custom color scheme (defaults to Theme.of(context).colorScheme)
  final ColorScheme? colorScheme;

  const MaterialMediaControls({
    super.key,
    required this.controller,
    this.showFullscreen = true,
    this.showSettings = true,
    this.showPip = true,
    this.title,
    this.colorScheme,
  });

  @override
  State<MaterialMediaControls> createState() => _MaterialMediaControlsState();
}

class _MaterialMediaControlsState extends State<MaterialMediaControls>
    with SingleTickerProviderStateMixin {
  bool _showControls = true;
  bool _showSettings = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut, // Material motion: standard easing
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _fadeController.forward();
      } else {
        _fadeController.reverse();
      }
    });
  }

  void _toggleSettings() {
    setState(() {
      _showSettings = !_showSettings;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = widget.colorScheme ?? theme.colorScheme;
    final textTheme = theme.textTheme;

    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Main controls
          AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: _showControls ? child : const SizedBox.shrink(),
              );
            },
            child: Container(
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
              child: Column(
                children: [
                  // Top bar with title and actions
                  _buildTopBar(colorScheme, textTheme),

                  const Spacer(),

                  // Center play/pause button
                  _buildCenterControls(colorScheme),

                  const Spacer(),

                  // Bottom bar with seek and controls
                  _buildBottomBar(colorScheme, textTheme),
                ],
              ),
            ),
          ),

          // Settings overlay
          if (_showSettings) _buildSettingsOverlay(colorScheme),
        ],
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme, TextTheme textTheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Title
            if (widget.title != null)
              Expanded(
                child: Text(
                  widget.title!,
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
            if (widget.showPip)
              _buildM3IconButton(
                icon: Icons.picture_in_picture_alt,
                onPressed: () async {
                  await widget.controller.enterPictureInPicture();
                },
                tooltip: 'Picture in Picture',
                colorScheme: colorScheme,
              ),

            const SizedBox(width: 8),

            // Settings button
            if (widget.showSettings)
              _buildM3IconButton(
                icon: Icons.settings,
                onPressed: _toggleSettings,
                tooltip: 'Settings',
                colorScheme: colorScheme,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state.state;
        final isPlaying = widget.controller.isPlaying;
        final isLoading = state == PlayerState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous button
            _buildM3FilledButton(
              icon: Icons.skip_previous,
              onPressed: widget.controller.hasPrevious
                  ? () => widget.controller.skipToPrevious()
                  : null,
              colorScheme: colorScheme,
              size: 32,
            ),

            const SizedBox(width: 24),

            // Play/Pause button (large, elevated)
            Material(
              elevation: 6, // M3 elevation level 3
              shape: const CircleBorder(),
              color: colorScheme.primaryContainer,
              child: InkWell(
                onTap: isLoading
                    ? null
                    : () {
                        if (isPlaying) {
                          widget.controller.pause();
                        } else {
                          widget.controller.play();
                        }
                      },
                customBorder: const CircleBorder(),
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  child: isLoading
                      ? SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            color: colorScheme.onPrimaryContainer,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 40,
                          color: colorScheme.onPrimaryContainer,
                        ),
                ),
              ),
            ),

            const SizedBox(width: 24),

            // Next button
            _buildM3FilledButton(
              icon: Icons.skip_next,
              onPressed: widget.controller.hasNext
                  ? () => widget.controller.skipToNext()
                  : null,
              colorScheme: colorScheme,
              size: 32,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme, TextTheme textTheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seek bar with time
            AnimatedBuilder(
              animation: widget.controller,
              builder: (context, child) {
                final position = widget.controller.position;
                final duration = widget.controller.duration;
                final value = duration.inMilliseconds > 0
                    ? position.inMilliseconds / duration.inMilliseconds
                    : 0.0;

                return Row(
                  children: [
                    // Current time
                    TimeDisplay(
                      position: position,
                      format: TimeDisplayFormat.currentOnly,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Seek bar
                    Expanded(
                      child: SeekBar(
                        value: value.clamp(0.0, 1.0),
                        duration: duration,
                        onChanged: (newValue) {
                          final seekTo = duration * newValue;
                          widget.controller.seekTo(seekTo);
                        },
                        activeColor: colorScheme.primary,
                        inactiveColor:
                            colorScheme.onSurface.withValues(alpha: 0.3),
                        thumbColor: colorScheme.primary,
                        trackHeight: 4.0,
                        thumbRadius: 8.0,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Total duration
                    TimeDisplay(
                      position: duration,
                      format: TimeDisplayFormat.totalOnly,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // Control buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Volume button
                    _buildM3IconButton(
                      icon: Icons.volume_up,
                      onPressed: () {
                        // Volume control (placeholder)
                      },
                      tooltip: 'Volume',
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Fullscreen button
                    if (widget.showFullscreen)
                      _buildM3IconButton(
                        icon: Icons.fullscreen,
                        onPressed: () {
                          // Fullscreen toggle (placeholder)
                        },
                        tooltip: 'Fullscreen',
                        colorScheme: colorScheme,
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsOverlay(ColorScheme colorScheme) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      child: GestureDetector(
        onTap: _toggleSettings,
        child: Container(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Prevent taps from closing when tapping sheet
            child: Container(
              constraints: const BoxConstraints(maxHeight: 500),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28), // M3 large border radius
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SettingsMenu(
                controller: widget.controller,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Material 3 icon button with state layer
  Widget _buildM3IconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required ColorScheme colorScheme,
  }) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      tooltip: tooltip,
      color: colorScheme.onSurface,
      iconSize: 24,
      style: IconButton.styleFrom(
        backgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        foregroundColor: colorScheme.onSurface,
        disabledBackgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
      ),
    );
  }

  /// Material 3 filled button
  Widget _buildM3FilledButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
    double size = 24,
  }) {
    return Material(
      elevation: 2, // M3 elevation level 1
      shape: const CircleBorder(),
      color: colorScheme.secondaryContainer,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: size,
            color: onPressed != null
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSecondaryContainer.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Example custom controls using CustomControlsBase
///
/// Demonstrates how to create fully custom controls by extending
/// the CustomControlsBase class.
class MinimalCustomControls extends CustomControlsBase {
  final String? title;

  const MinimalCustomControls({
    super.key,
    required super.controller,
    this.title,
    super.autoHideEnabled = true,
    super.autoHideDelay = const Duration(seconds: 3),
  });

  @override
  Widget buildControls(BuildContext context, ControlsState state) {
    if (!state.isVisible) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: state.animationValue,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.6),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(context),
            ),
            // Center play button
            Center(
              child: _buildCenterControls(state),
            ),
            // Bottom progress bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.arrow_back, color: Colors.white),
            const SizedBox(width: 16),
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Settings icon - top right corner
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 24),
              onPressed: () {
                debugPrint('Settings tapped');
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls(ControlsState state) {
    return AnimatedBuilder(
      animation: state.controller,
      builder: (context, _) {
        final isPlaying = state.controller.isPlaying;
        final isBuffering =
            state.controller.state.state == PlayerState.buffering;

        return Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.5),
            ),
            child: IconButton(
              icon: Icon(
                isBuffering
                    ? Icons.hourglass_empty
                    : (isPlaying ? Icons.pause : Icons.play_arrow),
                color: Colors.white,
                size: 32,
              ),
              onPressed: isBuffering
                  ? null
                  : () {
                      if (isPlaying) {
                        state.controller.pause();
                      } else {
                        state.controller.play();
                      }
                    },
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(ControlsState state) {
    return AnimatedBuilder(
      animation: state.controller,
      builder: (context, _) {
        final position = state.controller.position;
        final duration = state.controller.duration;
        final value = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Control buttons and time display - with padding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  // Current time
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      _formatDuration(position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),

                  // Spacer to push fullscreen to the right
                  const Spacer(),

                  // Fullscreen toggle
                  IconButton(
                    icon: const Icon(Icons.fullscreen,
                        color: Colors.white, size: 24),
                    onPressed: () {
                      debugPrint('Fullscreen tapped');
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),

                  // Duration
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      _formatDuration(duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            // Progress bar - absolutely at the bottom edge, no padding
            Container(
              height: 4,
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}

/// Example using CustomControlsBuilder for quick prototyping
class BuilderBasedControls extends StatelessWidget {
  final MediaController controller;
  final String? title;

  const BuilderBasedControls({
    super.key,
    required this.controller,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return CustomControlsBuilder(
      controller: controller,
      builder: (context, state) {
        if (!state.isVisible) {
          return const SizedBox.shrink();
        }

        return Opacity(
          opacity: state.animationValue,
          child: Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        title!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      return IconButton(
                        iconSize: 64,
                        icon: Icon(
                          controller.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          if (controller.isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        },
                      );
                    },
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

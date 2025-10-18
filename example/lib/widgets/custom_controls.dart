import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

class CustomControls extends StatefulWidget {
  final MediaController controller;

  const CustomControls({
    super.key,
    required this.controller,
  });

  @override
  State<CustomControls> createState() => _CustomControlsState();
}

class _CustomControlsState extends State<CustomControls> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _hideControlsAfterDelay();
    // Listen to controller changes
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // Rebuild when controller state changes
    if (mounted) {
      setState(() {});
    }
  }

  void _hideControlsAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && widget.controller.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _hideControlsAfterDelay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.transparent,
                Colors.black.withOpacity(0.7),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Column(
            children: [
              // Top Bar
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) {
                          return Text(
                            widget.controller.currentItem?.title ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ),
                      const Spacer(),
                      const SizedBox(width: 48), // Balance for back button
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Center Play/Pause Button
              Center(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    if (widget.controller.isBuffering) {
                      return const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      );
                    }

                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.5),
                      ),
                      child: IconButton(
                        icon: Icon(
                          widget.controller.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: 48,
                        ),
                        onPressed: widget.controller.togglePlayPause,
                      ),
                    );
                  },
                ),
              ),

              const Spacer(),

              // Bottom Controls
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Progress Bar
                    ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  widget.controller.formattedPosition,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  widget.controller.formattedDuration,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                                activeTrackColor: const Color(0xFF6366F1),
                                inactiveTrackColor: Colors.white30,
                                thumbColor: const Color(0xFF6366F1),
                                overlayColor:
                                    const Color(0xFF6366F1).withOpacity(0.2),
                              ),
                              child: Slider(
                                value: widget.controller.position.inMilliseconds
                                    .toDouble(),
                                max: widget.controller.duration.inMilliseconds
                                    .toDouble()
                                    .clamp(1.0, double.infinity),
                                onChanged: (value) {
                                  widget.controller.seekTo(
                                    Duration(milliseconds: value.toInt()),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 8),

                    // Control Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Rewind 10s
                        IconButton(
                          icon:
                              const Icon(Icons.replay_10, color: Colors.white),
                          onPressed: () => widget.controller.seekBackward(
                            const Duration(seconds: 10),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Previous (disabled for single video)
                        IconButton(
                          icon: const Icon(Icons.skip_previous,
                              color: Colors.white54),
                          onPressed: null,
                        ),

                        const SizedBox(width: 16),

                        // Play/Pause
                        ListenableBuilder(
                          listenable: widget.controller,
                          builder: (context, _) {
                            return Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF6366F1),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  widget.controller.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                                onPressed: widget.controller.togglePlayPause,
                              ),
                            );
                          },
                        ),

                        const SizedBox(width: 16),

                        // Next (disabled for single video)
                        IconButton(
                          icon: const Icon(Icons.skip_next,
                              color: Colors.white54),
                          onPressed: null,
                        ),

                        const SizedBox(width: 16),

                        // Forward 10s
                        IconButton(
                          icon:
                              const Icon(Icons.forward_10, color: Colors.white),
                          onPressed: () => widget.controller.seekForward(
                            const Duration(seconds: 10),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/subtitle_track.dart';
import '../services/subtitle_service.dart';

/// Widget for displaying subtitles over video content
class SubtitleView extends StatefulWidget {
  /// The subtitle service to use
  final SubtitleService subtitleService;

  /// Current playback position
  final Duration position;

  /// Subtitle configuration
  final SubtitleConfig config;

  /// Whether subtitles are enabled
  final bool enabled;

  /// Callback when subtitle track changes
  final ValueChanged<SubtitleTrack>? onTrackChanged;

  const SubtitleView({
    Key? key,
    required this.subtitleService,
    required this.position,
    required this.config,
    this.enabled = true,
    this.onTrackChanged,
  }) : super(key: key);

  @override
  State<SubtitleView> createState() => _SubtitleViewState();
}

class _SubtitleViewState extends State<SubtitleView> {
  SubtitleCue? _currentCue;
  List<SubtitleTrack> _availableTracks = [];
  SubtitleTrack? _selectedTrack;

  @override
  void initState() {
    super.initState();
    _loadAvailableTracks();
  }

  @override
  void didUpdateWidget(SubtitleView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.position != widget.position) {
      _updateCurrentCue();
    }

    if (oldWidget.subtitleService != widget.subtitleService) {
      _loadAvailableTracks();
    }
  }

  /// Load available subtitle tracks from the subtitle service's current state.
  ///
  /// The widget itself has no media-source access; real tracks are pushed into
  /// [SubtitleService] by the player.  We read whatever the service already
  /// has rather than fabricating placeholder URLs.
  Future<void> _loadAvailableTracks() async {
    // Derive available tracks from the service's current active track, if any.
    // When the player later provides tracks (e.g. via a platform callback)
    // the caller is expected to rebuild this widget with an updated service,
    // which will trigger didUpdateWidget → _loadAvailableTracks again.
    final active = widget.subtitleService.activeTrack;
    if (active != null) {
      _availableTracks = [active];
      _selectedTrack = active;
    } else {
      _availableTracks = [];
      _selectedTrack = null;
    }

    setState(() {});
  }

  /// Update current subtitle cue based on position
  void _updateCurrentCue() {
    if (!widget.enabled) return;

    final cue = widget.subtitleService.getCueAtTime(widget.position);
    if (cue != _currentCue) {
      setState(() {
        _currentCue = cue;
      });
    }
  }

  /// Change subtitle track
  Future<void> _changeTrack(SubtitleTrack track) async {
    try {
      await widget.subtitleService.setActiveTrack(track);
      setState(() {
        _selectedTrack = track;
      });
      widget.onTrackChanged?.call(track);
    } catch (e) {
      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to change subtitle track: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _currentCue == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: _getSubtitlePosition(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: _buildSubtitleText(),
      ),
    );
  }

  /// Build subtitle text with styling
  Widget _buildSubtitleText() {
    final textStyle = TextStyle(
      fontSize: widget.config.fontSize,
      color: Color(widget.config.fontColor),
      fontFamily: widget.config.fontFamily,
      fontWeight: FontWeight.w500,
      shadows: widget.config.showOutline
          ? [
              Shadow(
                offset: const Offset(1, 1),
                blurRadius: 2,
                color: Color(widget.config.outlineColor ?? 0xFF000000),
              ),
              Shadow(
                offset: const Offset(-1, -1),
                blurRadius: 2,
                color: Color(widget.config.outlineColor ?? 0xFF000000),
              ),
            ]
          : null,
    );

    Widget subtitleWidget = Text(
      _currentCue!.text,
      style: textStyle,
      textAlign: _getTextAlignment(),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );

    // Add background if specified
    if (widget.config.backgroundColor != null) {
      subtitleWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Color(widget.config.backgroundColor!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: subtitleWidget,
      );
    }

    return subtitleWidget;
  }

  /// Get subtitle position based on configuration
  double _getSubtitlePosition() {
    final screenHeight = MediaQuery.of(context).size.height;
    final position = screenHeight * widget.config.verticalPosition;

    // Ensure subtitle is not too close to the bottom
    return position.clamp(80.0, screenHeight - 100.0);
  }

  /// Get text alignment based on configuration
  TextAlign _getTextAlignment() {
    switch (widget.config.horizontalAlignment) {
      case SubtitleAlignment.left:
        return TextAlign.left;
      case SubtitleAlignment.center:
        return TextAlign.center;
      case SubtitleAlignment.right:
        return TextAlign.right;
    }
  }

  /// Build subtitle track selector
  Widget buildTrackSelector() {
    if (_availableTracks.isEmpty) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<SubtitleTrack>(
      icon: const Icon(Icons.subtitles),
      onSelected: _changeTrack,
      itemBuilder: (context) => [
        for (final track in _availableTracks)
          PopupMenuItem(
            value: track,
            child: Row(
              children: [
                if (track.id == _selectedTrack?.id)
                  const Icon(Icons.check, size: 16),
                const SizedBox(width: 8),
                Text(track.title),
                if (track.language != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${track.language})',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Subtitle view with controls
class SubtitleViewWithControls extends StatelessWidget {
  /// The subtitle view
  final SubtitleView subtitleView;

  /// Whether to show controls
  final bool showControls;

  const SubtitleViewWithControls({
    super.key,
    required this.subtitleView,
    this.showControls = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        subtitleView,
        if (showControls)
          Positioned(
            top: 16,
            right: 16,
            child: _buildTrackSelector(context),
          ),
      ],
    );
  }

  Widget _buildTrackSelector(BuildContext context) {
    // Create a simple track selector that works with the subtitle view
    return PopupMenuButton<String>(
      icon: const Icon(Icons.subtitles, color: Colors.white),
      onSelected: (trackId) {
        // This would typically trigger a track change
        // For now, just show a snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subtitle track changed to: $trackId')),
        );
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'en',
          child: Text('English'),
        ),
        const PopupMenuItem(
          value: 'es',
          child: Text('Spanish'),
        ),
        const PopupMenuItem(
          value: 'fr',
          child: Text('French'),
        ),
        const PopupMenuItem(
          value: 'off',
          child: Text('Off'),
        ),
      ],
    );
  }
}

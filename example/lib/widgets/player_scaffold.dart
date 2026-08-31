import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// A reusable scaffold used by feature pages that embed a [MediaPlayerWidget].
///
/// Provides:
/// - An AppBar with the page title
/// - The [MediaPlayerWidget] at 16:9 aspect ratio at the top
/// - A scrollable body for additional controls / info
///
/// ### Single-native-view pattern
///
/// When pushing a fullscreen route (e.g. [FullscreenMediaPlayer]) for the
/// same [controller], pass a [playerWidget] override — typically a black
/// [ColoredBox] placeholder — so the inline player surface is hidden while
/// the fullscreen host owns the native view.  Restore [playerWidget] to
/// `null` after the route pops to show the inline player again.
///
/// ```dart
/// // Before push:
/// setState(() => _fullscreenActive = true); // show placeholder
/// await Navigator.push(...);
/// // After pop:
/// setState(() => _fullscreenActive = false); // restore player
/// ```
class PlayerScaffold extends StatelessWidget {
  final String title;
  final MediaController controller;
  final Widget body;
  final List<Widget>? actions;
  final bool showAdaptiveControls;

  /// Optional widget that replaces the default [MediaPlayerWidget].
  ///
  /// Pass a [ColoredBox] with [Colors.black] here while a fullscreen route is
  /// active for this player so only one native-view host is alive at a time.
  final Widget? playerWidget;

  /// Forwarded to [MediaPlayerWidget.onDoubleTapDown], with the player box's
  /// size supplied alongside the raw [TapDownDetails].
  ///
  /// `details.localPosition` is relative to the player widget's own box, so a
  /// page maps it onto a left/right half by comparing against
  /// `playerSize.width / 2` -- the canonical direction-aware double-tap seek.
  /// Supplying this suppresses the widget's built-in
  /// double-tap-to-play/pause; see the "Gesture callbacks" section of
  /// `docs/api-reference/advanced-features.md`.
  ///
  /// Supplying it also switches this scaffold to the package's **default**
  /// [MediaControls] overlay instead of [AdaptiveMediaControls]. That is not
  /// cosmetic: the controls overlay is always mounted and sits above the
  /// package's own tap detector, and [AdaptiveMediaControls] (via
  /// `MaterialMediaControls`/`CupertinoMediaControls`) declares an *opaque*
  /// root `GestureDetector` with its own `onDoubleTap`, so it would claim the
  /// double tap before it could ever reach this callback. The default
  /// [MediaControls] instead forwards background taps and double taps --
  /// position included -- back to [MediaPlayerWidget], which is what makes the
  /// gesture work in both visibility states.
  final void Function(TapDownDetails details, Size playerSize)?
      onVideoDoubleTapDown;

  const PlayerScaffold({
    super.key,
    required this.title,
    required this.controller,
    required this.body,
    this.actions,
    this.showAdaptiveControls = true,
    this.playerWidget,
    this.onVideoDoubleTapDown,
  });

  Widget _buildPlayer({required BoxFit boxFit}) {
    // Use the caller-supplied playerWidget (e.g. a black placeholder) when one
    // is provided, so the inline surface relinquishes the native view while a
    // fullscreen route is active.
    if (playerWidget != null) return playerWidget!;

    return LayoutBuilder(
      builder: (context, constraints) => MediaPlayerWidget(
        controller: controller,
        showControls: showAdaptiveControls,
        boxFit: boxFit,
        customControls: showAdaptiveControls && onVideoDoubleTapDown == null
            ? AdaptiveMediaControls(
                controller: controller,
                title: title,
              )
            : null,
        backgroundColor: Colors.black,
        onDoubleTapDown: onVideoDoubleTapDown == null
            ? null
            : (details) => onVideoDoubleTapDown!(details, constraints.biggest),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: actions,
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          // Landscape: the video fills the entire screen using BoxFit.cover so
          // there are no black bars (the player scales to cover, cropping the
          // edges as needed). Dropping the scrollable body here also avoids the
          // vertical overflow an AspectRatio(16:9) would force at large widths.
          // The adaptive controls overlay keeps playback controllable; rotate
          // back to portrait for the per-page demo controls.
          if (orientation == Orientation.landscape) {
            return ColoredBox(
              color: Colors.black,
              child: SizedBox.expand(
                child: _buildPlayer(boxFit: BoxFit.cover),
              ),
            );
          }

          // Portrait: 16:9 video at the top (letterboxed to preserve aspect) +
          // scrollable body for controls/info.
          return Column(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildPlayer(boxFit: BoxFit.contain),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: body,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A section header used inside the player scaffold body.
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// A labeled info row for displaying key-value pairs.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const InfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

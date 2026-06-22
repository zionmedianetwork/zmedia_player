import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// A reusable scaffold used by feature pages that embed a [MediaPlayerWidget].
///
/// Provides:
/// - An AppBar with the page title
/// - The [MediaPlayerWidget] at 16:9 aspect ratio at the top
/// - A scrollable body for additional controls / info
class PlayerScaffold extends StatelessWidget {
  final String title;
  final MediaController controller;
  final Widget body;
  final List<Widget>? actions;
  final bool showAdaptiveControls;

  const PlayerScaffold({
    super.key,
    required this.title,
    required this.controller,
    required this.body,
    this.actions,
    this.showAdaptiveControls = true,
  });

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
      body: Column(
        children: [
          // Video player at 16:9 aspect ratio
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MediaPlayerWidget(
              controller: controller,
              showControls: showAdaptiveControls,
              customControls: showAdaptiveControls
                  ? AdaptiveMediaControls(
                      controller: controller,
                      title: title,
                    )
                  : null,
              backgroundColor: Colors.black,
            ),
          ),
          // Scrollable area for additional controls / info
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: body,
            ),
          ),
        ],
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

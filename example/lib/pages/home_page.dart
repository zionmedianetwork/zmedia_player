import 'package:flutter/material.dart';
import '../widgets/feature_card.dart';
import 'simple_playback_page.dart';
import 'local_file_playback_page.dart';
import 'cache_playback_page.dart';
import 'playlist_page.dart';
import 'streaming_quality_page.dart';
import 'subtitles_page.dart';
import 'drm_page.dart';
import 'pip_page.dart';
import 'casting_page.dart';
import 'notifications_page.dart';
import 'fullscreen_page.dart';
import 'adaptive_controls_page.dart';
import 'custom_controls_page.dart';
import 'error_handling_page.dart';
import 'multi_player_page.dart';
import 'network_status_page.dart';
import 'feed_page.dart';
import 'media_feed_pool_page.dart';
import 'secure_output_page.dart';
import 'measurement/measurement_hub_page.dart';

/// Home page displaying a scrollable gallery of ZMedia Player feature demos.
///
/// Each card navigates to a self-contained page that exercises a specific
/// portion of the public API.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('ZMedia Player'),
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.6),
                      Theme.of(context).colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionLabel('Core Playback'),
                _feature(
                  context,
                  title: 'Simple Playback',
                  description:
                      'Load a single video; play, pause, seek, volume control.',
                  icon: Icons.play_circle_outline,
                  page: const SimplePlaybackPage(),
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Playlist',
                  description:
                      'Multiple items with next/previous, repeat and shuffle modes.',
                  icon: Icons.queue_music,
                  page: const PlaylistPage(),
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Local File Playback (C-02 Stage 1)',
                  description:
                      'Play a bundled asset copied to disk via a file:// '
                      'URL -- no network required.',
                  icon: Icons.folder_open,
                  page: const LocalFilePlaybackPage(),
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Cache -> Playback (C-03a)',
                  description:
                      'Download a progressive file into CacheService, then '
                      'play it back from disk -- verify with airplane mode.',
                  icon: Icons.download_for_offline_outlined,
                  page: const CachePlaybackPage(),
                ),
                const SizedBox(height: 16),
                _SectionLabel('Streaming'),
                _feature(
                  context,
                  title: 'Adaptive Streaming & Quality',
                  description:
                      'HLS/DASH with quality track selection and bandwidth display.',
                  icon: Icons.hd,
                  page: const StreamingQualityPage(),
                  iconColor: Colors.teal,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Subtitles',
                  description:
                      'Select subtitle tracks; configure font size, color and styling.',
                  icon: Icons.closed_caption,
                  page: const SubtitlesPage(),
                  iconColor: Colors.teal,
                ),
                const SizedBox(height: 16),
                _SectionLabel('Content Protection'),
                _feature(
                  context,
                  title: 'DRM (Widevine / FairPlay / EZDRM)',
                  description:
                      'Construct DrmConfig and monitor DRM session state.',
                  icon: Icons.lock,
                  page: const DrmPage(),
                  iconColor: Colors.deepOrange,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Screen-Capture Protection (B-12)',
                  description:
                      'Toggle secure output at runtime; live isCaptured '
                      'status; Android (FLAG_SECURE block) vs iOS '
                      '(detection-only) device test steps.',
                  icon: Icons.screenshot_monitor,
                  page: const SecureOutputPage(),
                  iconColor: Colors.deepOrange,
                ),
                const SizedBox(height: 16),
                _SectionLabel('Platform Features'),
                _feature(
                  context,
                  title: 'Picture-in-Picture',
                  description:
                      'Check availability, enter/exit PiP, auto-enter on background.',
                  icon: Icons.picture_in_picture,
                  page: const PipPage(),
                  iconColor: Colors.indigo,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Casting (Chromecast / AirPlay)',
                  description:
                      'Discover devices, connect, load media, AirPlayButton.',
                  icon: Icons.cast,
                  page: const CastingPage(),
                  iconColor: Colors.indigo,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Media Notifications',
                  description:
                      'Show / update / dismiss lock-screen notification with actions.',
                  icon: Icons.notifications,
                  page: const NotificationsPage(),
                  iconColor: Colors.indigo,
                ),
                const SizedBox(height: 16),
                _SectionLabel('UI / Controls'),
                _feature(
                  context,
                  title: 'Fullscreen Playback',
                  description:
                      'FullscreenMediaPlayer and MaterialFullscreenPlayer routes.',
                  icon: Icons.fullscreen,
                  page: const FullscreenPage(),
                  iconColor: Colors.purple,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Adaptive Controls',
                  description:
                      'AdaptiveMediaControls and a custom CustomControlsBase example.',
                  icon: Icons.widgets,
                  page: const AdaptiveControlsPage(),
                  iconColor: Colors.purple,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Fully Custom Controls & Overlay',
                  description:
                      'Build a completely bespoke overlay from scratch using CustomControlsBase.',
                  icon: Icons.brush,
                  page: const CustomControlsPage(),
                  iconColor: Colors.deepPurple,
                ),
                const SizedBox(height: 16),
                _SectionLabel('Robustness'),
                _feature(
                  context,
                  title: 'Error Handling',
                  description:
                      'Bad URL, network failure, typed exceptions, error state.',
                  icon: Icons.error_outline,
                  page: const ErrorHandlingPage(),
                  iconColor: Colors.red,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Multi-Player (B-02 / H-07)',
                  description:
                      'Two concurrent players; scripted regression check for '
                      'cross-instance completion and Now Playing ownership.',
                  icon: Icons.view_column_outlined,
                  page: const MultiPlayerPage(),
                  iconColor: Colors.red,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Network Status (H-06)',
                  description: 'Live NetworkStatus / networkStatusStream / '
                      'networkChangeStream readout; toggle airplane mode '
                      'to verify.',
                  icon: Icons.signal_cellular_alt,
                  page: const NetworkStatusPage(),
                  iconColor: Colors.red,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Feed (MediaListPlayer, Phase 4)',
                  description:
                      'Scrolling feed of 12 MediaListPlayers; verifies '
                      'scroll-away pause, the maxConcurrentPlayers cap, and '
                      'pauseOthersOnPlay.',
                  icon: Icons.view_agenda_outlined,
                  page: const FeedPage(),
                  iconColor: Colors.red,
                ),
                const SizedBox(height: 16),
                _SectionLabel('Phase 7 — Feed Architecture'),
                _feature(
                  context,
                  title: 'Stage 7a Measurement Harness',
                  description:
                      'Throwaway harness producing the numbers Stage 7b\'s '
                      'pool/prewarm/prefetch defaults are designed against: '
                      'decoder ceiling, paused-vs-playing memory, '
                      'time-to-first-frame, 50-item scroll bandwidth, '
                      'off-screen live bandwidth.',
                  icon: Icons.science_outlined,
                  page: const MeasurementHubPage(),
                  iconColor: Colors.brown,
                ),
                const SizedBox(height: 8),
                _feature(
                  context,
                  title: 'Feed (MediaFeed pool, Stage 7b)',
                  description: '20-item feed backed by a package-owned '
                      'MediaPlayerPool -- this page never touches a '
                      'MediaController. Live pool occupancy readout proves '
                      'concurrent decoder sessions stay bounded to '
                      'maxPoolSize regardless of scroll distance (fixes '
                      'F-01/F-02).',
                  icon: Icons.dynamic_feed_outlined,
                  page: const MediaFeedPoolPage(),
                  iconColor: Colors.brown,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Widget page,
    Color? iconColor,
  }) {
    return FeatureCard(
      title: title,
      description: description,
      icon: icon,
      iconColor: iconColor,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

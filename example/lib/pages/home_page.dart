import 'package:flutter/material.dart';
import 'simple_player_page.dart';
import 'full_featured_player_page.dart';
import 'fullscreen_demo_page.dart';
import 'playlist_demo_page.dart';
import 'streaming_demo_page.dart';
import 'notifications_demo_page.dart';
import 'pip_demo_page.dart';
import 'casting_demo_page.dart';
import 'drm_demo_page.dart';
import 'exception_handling_demo_page.dart';
import 'settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'ZMedia Player',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF6366F1),
                      const Color(0xFF8B5CF6),
                      const Color(0xFFEC4899),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.play_circle_filled,
                    size: 80,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),

                  // Welcome Text
                  Text(
                    'Welcome! 👋',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Explore powerful video playback features',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 30),

                  // Feature Cards
                  _FeatureCard(
                    icon: Icons.play_circle_outline,
                    iconColor: const Color(0xFF6366F1),
                    title: 'Simple Player',
                    description: 'Basic video playback with default controls',
                    features: const [
                      'Play, Pause, Seek',
                      'Volume Control',
                      'Fullscreen Support',
                    ],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SimplePlayerPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.featured_play_list,
                    iconColor: const Color(0xFF8B5CF6),
                    title: 'Full Featured Player',
                    description: 'Advanced player with all features',
                    features: const [
                      'Custom Controls',
                      'Speed Control (0.25x - 4x)',
                      'BoxFit Options',
                      'Volume & Mute',
                    ],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FullFeaturedPlayerPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.playlist_play,
                    iconColor: const Color(0xFFEC4899),
                    title: 'Playlist Demo',
                    description: 'Multiple videos with playlist controls',
                    features: const [
                      'Next/Previous',
                      'Shuffle & Repeat',
                      'Sequential Playback',
                    ],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PlaylistDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.fullscreen,
                    iconColor: const Color(0xFF10B981),
                    title: 'Fullscreen Players (Phase 2)',
                    description:
                        'Immersive fullscreen with platform-specific controls',
                    features: const [
                      'Material Design Fullscreen',
                      'Cupertino (iOS) Fullscreen',
                      'Orientation Locking',
                      'System UI Hiding',
                    ],
                    badge: 'PHASE 2',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FullscreenDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.stream,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Streaming Demo (Phase 2)',
                    description:
                        'HLS/DASH adaptive streaming with quality selection',
                    features: const [
                      'HLS & DASH Support',
                      'Adaptive Bitrate',
                      'Quality Selection',
                      'Offline Download',
                    ],
                    badge: 'PHASE 2',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StreamingDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Phase 3 Section Header
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: Colors.amber, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        'Phase 3 - Advanced Features',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.notifications_active,
                    iconColor: const Color(0xFF9333EA),
                    title: 'Notifications Demo',
                    description:
                        'Media playback notifications with lock screen controls',
                    features: const [
                      'Lock Screen Controls',
                      'Control Center',
                      'Background Playback',
                      'Album Artwork',
                    ],
                    badge: 'PHASE 3',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NotificationsDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.picture_in_picture_alt,
                    iconColor: const Color(0xFF14B8A6),
                    title: 'Picture-in-Picture',
                    description: 'Floating video playback on top of other apps',
                    features: const [
                      'PiP Mode',
                      'Auto-enter on Background',
                      'Custom Aspect Ratio',
                      'iOS & Android Support',
                    ],
                    badge: 'PHASE 3',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PipDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.cast,
                    iconColor: const Color(0xFFDB2777),
                    title: 'Chromecast & AirPlay',
                    description: 'Stream media to external devices',
                    features: const [
                      'Chromecast (Android)',
                      'AirPlay (iOS)',
                      'Device Discovery',
                      'Remote Control',
                    ],
                    badge: 'PHASE 3',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CastingDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  _FeatureCard(
                    icon: Icons.security,
                    iconColor: const Color(0xFFDC2626),
                    title: 'DRM Content Protection',
                    description: 'Play DRM-protected media content',
                    features: const [
                      'Widevine (Android)',
                      'FairPlay (iOS)',
                      'EZDRM Support',
                    ],
                    badge: 'PHASE 4',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DrmDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _FeatureCard(
                    icon: Icons.error_outline,
                    iconColor: const Color(0xFFF97316),
                    title: 'Exception Handling',
                    description: 'Comprehensive error handling and recovery',
                    features: const [
                      'Typed Exceptions',
                      'User-Friendly Errors',
                      'Recovery Recommendations',
                      'Error Logging',
                    ],
                    badge: 'PHASE 4',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ExceptionHandlingDemoPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  _FeatureCard(
                    icon: Icons.settings,
                    iconColor: const Color(0xFF64748B),
                    title: 'Settings & Configuration',
                    description: 'Explore player configuration options',
                    features: const [
                      'Auto-play',
                      'Hardware Acceleration',
                      'Custom Headers',
                    ],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsPage(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Features List
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1E293B),
                          const Color(0xFF334155),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'All Features',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Phase 1
                        Text(
                          'Phase 1 - Core Features',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[300],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Cross-Platform (Android & iOS)',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'ExoPlayer & AVPlayer Integration',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'HTTP Headers Support',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Multiple BoxFit Options',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Playback Speed Control',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Playlist Management',
                        ),

                        const SizedBox(height: 20),

                        // Phase 2
                        Text(
                          'Phase 2 - Streaming Features',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[300],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'HLS & DASH Streaming',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Adaptive Bitrate Streaming',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Quality & Audio Track Selection',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Subtitle Support (SRT, WebVTT)',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Offline Caching & Download',
                        ),

                        const SizedBox(height: 20),

                        // Phase 3
                        Text(
                          'Phase 3 - Advanced Features',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple[300],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Media Notifications & Lock Screen',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Picture-in-Picture Mode',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Chromecast Support (Android)',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'AirPlay Support (iOS)',
                        ),
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Background Playback',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Footer
                  Center(
                    child: Text(
                      'Made with ❤️ using Flutter',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final List<String> features;
  final VoidCallback onTap;
  final String? badge;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.features,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  badge!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.white54,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: features.map((feature) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      feature,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

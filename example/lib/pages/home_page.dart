import 'package:flutter/material.dart';
import 'simple_player_page.dart';
import 'full_featured_player_page.dart';
import 'playlist_demo_page.dart';
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
                    color: Colors.white.withOpacity(0.3),
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
                    icon: Icons.settings,
                    iconColor: const Color(0xFF14B8A6),
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
                              'Phase 1 Features',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
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
                        _FeatureItem(
                          icon: Icons.check_circle,
                          text: 'Comprehensive State Management',
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

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.features,
    required this.onTap,
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
                      color: iconColor.withOpacity(0.2),
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
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
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
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_videos.dart';

class FullscreenDemoPage extends StatefulWidget {
  const FullscreenDemoPage({super.key});

  @override
  State<FullscreenDemoPage> createState() => _FullscreenDemoPageState();
}

class _FullscreenDemoPageState extends State<FullscreenDemoPage> {
  late MediaController _controller;
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isInitializing = true;
        _error = null;
      });

      _controller = MediaController.create(
        config: const MediaConfig(
          autoPlay: false,
          volume: 1.0,
          showControls: true,
          boxFit: BoxFit.contain,
        ),
      );

      await _controller.initialize();
      await _controller.load(SampleVideos.defaultVideo);

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isInitializing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fullscreen Demo'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.1),
                    const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.fullscreen,
                        color: const Color(0xFF6366F1),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Fullscreen Players',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Immersive fullscreen playback with platform-specific controls. '
                    'Choose between Material Design (Android) or Cupertino (iOS) styles.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '✓ Landscape orientation lock\n'
                    '✓ System UI hiding (immersive mode)\n'
                    '✓ Platform-optimized controls\n'
                    '✓ Exit fullscreen button\n'
                    '✓ Auto-restore orientation on exit',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Video Preview
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildPlayer(),
              ),
            ),

            const SizedBox(height: 24),

            // Fullscreen Buttons
            Text(
              'Choose Fullscreen Style',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            // Material Fullscreen Button
            _FullscreenButton(
              icon: Icons.android,
              title: 'Material Design Fullscreen',
              description:
                  'Android-style fullscreen with Material Design 3 controls',
              color: const Color(0xFF6366F1),
              onPressed: _isInitializing || _error != null
                  ? null
                  : () => _openMaterialFullscreen(context),
            ),

            const SizedBox(height: 12),

            // Cupertino Fullscreen Button
            _FullscreenButton(
              icon: CupertinoIcons.device_phone_portrait,
              title: 'Cupertino Fullscreen',
              description:
                  'iOS-style fullscreen with blur effects and native controls',
              color: const Color(0xFF8B5CF6),
              onPressed: _isInitializing || _error != null
                  ? null
                  : () => _openCupertinoFullscreen(context),
            ),

            const SizedBox(height: 12),

            // Auto-detect Button
            _FullscreenButton(
              icon: Icons.phone_iphone,
              title: 'Auto-Detect Platform',
              description:
                  'Automatically use Material on Android, Cupertino on iOS',
              color: const Color(0xFFEC4899),
              onPressed: _isInitializing || _error != null
                  ? null
                  : () => _openAdaptiveFullscreen(context),
            ),

            const SizedBox(height: 24),

            // Technical Details
            _buildTechnicalDetails(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF6366F1),
            ),
            SizedBox(height: 16),
            Text(
              'Initializing player...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return MediaPlayerWidget(
      controller: _controller,
      showControls: true,
    );
  }

  void _openMaterialFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: MediaPlayerWidget(
            controller: _controller,
            showControls: true,
            customControls: MaterialFullscreenPlayer(
              controller: _controller,
              title: _controller.currentItem?.title ?? 'Material Fullscreen',
              showSettings: true,
              showPip: true,
            ),
          ),
        ),
      ),
    );
  }

  void _openCupertinoFullscreen(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => CupertinoPageScaffold(
          child: MediaPlayerWidget(
            controller: _controller,
            showControls: true,
            customControls: CupertinoFullscreenPlayer(
              controller: _controller,
              title: _controller.currentItem?.title ?? 'Cupertino Fullscreen',
              showSettings: true,
              showPip: true,
            ),
          ),
        ),
      ),
    );
  }

  void _openAdaptiveFullscreen(BuildContext context) {
    if (Platform.isIOS) {
      _openCupertinoFullscreen(context);
    } else {
      _openMaterialFullscreen(context);
    }
  }

  Widget _buildTechnicalDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Technical Details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _TechDetail(
            title: 'System UI Mode',
            value: 'SystemUiMode.immersiveSticky',
            description: 'Hides status bar and navigation bar',
          ),
          _TechDetail(
            title: 'Orientation',
            value: 'landscapeLeft, landscapeRight',
            description: 'Auto-locks to landscape on enter',
          ),
          _TechDetail(
            title: 'Exit Behavior',
            value: 'Restores orientation and UI',
            description: 'Returns to previous state on exit',
          ),
          _TechDetail(
            title: 'Base Class',
            value: 'FullscreenControlsBase',
            description: 'Extends CustomControlsBase',
          ),
        ],
      ),
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback? onPressed;

  const _FullscreenButton({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: isEnabled ? 0.3 : 0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isEnabled ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isEnabled ? color : color.withValues(alpha: 0.5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isEnabled ? Colors.white : Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: isEnabled ? Colors.white70 : Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: isEnabled ? color : color.withValues(alpha: 0.3),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechDetail extends StatelessWidget {
  final String title;
  final String value;
  final String description;

  const _TechDetail({
    required this.title,
    required this.value,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: const Color(0xFF6366F1),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

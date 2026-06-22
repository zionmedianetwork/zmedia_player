import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates Picture-in-Picture (PiP) mode:
/// - [MediaController.checkPipAvailability] — must return true before entering
/// - [MediaController.enterPictureInPicture] — moves playback to PiP window
/// - [MediaController.exitPictureInPicture]
/// - [MediaController.pipStatusStream] / [MediaController.pipStatus]
/// - [PipConfig] inside [MediaConfig] to configure auto-enter on background
///
/// REQUIREMENTS:
///   Android: API 26+ (Oreo). The example/android MainActivity must relay
///   onPictureInPictureModeChanged — see example/android/app/MainActivity.kt.
///   iOS: Requires background audio capability and AVFoundation.
///
/// On desktop / simulator without hardware PiP support,
/// checkPipAvailability() will return false and the Enter PiP button will
/// be disabled.
class PipPage extends StatefulWidget {
  const PipPage({super.key});

  @override
  State<PipPage> createState() => _PipPageState();
}

class _PipPageState extends State<PipPage> {
  late final MediaController _controller;
  StreamSubscription<PipStatus>? _pipSub;

  bool _pipAvailable = false;
  PipStatus _pipStatus = const PipStatus(
    state: PipState.unavailable,
    isSupported: false,
    isActive: false,
  );
  bool _isLoading = false;
  String? _error;
  bool _autoEnterOnBackground = false;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'pip_demo',
      config: MediaConfig(
        pipConfig: PipConfig(
          enabled: true,
          aspectRatio: 16 / 9,
          autoEnterOnBackground: _autoEnterOnBackground,
          showPlaybackControls: true,
        ),
      ),
    );
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _controller.initialize();

      // Subscribe to PiP status stream
      _pipSub?.cancel();
      _pipSub = _controller.pipStatusStream.listen((status) {
        if (mounted) setState(() => _pipStatus = status);
      });

      await _controller.load(SampleMedia.bigBuckBunny);

      // Check availability after initialising
      final available = await _controller.checkPipAvailability();
      if (mounted) setState(() => _pipAvailable = available);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enterPip() async {
    try {
      await _controller.enterPictureInPicture();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to enter PiP: $e')),
        );
      }
    }
  }

  Future<void> _exitPip() async {
    try {
      await _controller.exitPictureInPicture();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to exit PiP: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _pipSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Picture-in-Picture',
      controller: _controller,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
        FilledButton(onPressed: _initAndLoad, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('PiP Status'),
        _StatusCard(
          available: _pipAvailable,
          status: _pipStatus,
        ),
        const SizedBox(height: 16),
        const SectionHeader('Controls'),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.picture_in_picture),
              label: const Text('Enter PiP'),
              onPressed:
                  (_pipAvailable && !_pipStatus.isActive) ? _enterPip : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.fullscreen),
              label: const Text('Exit PiP'),
              onPressed: _pipStatus.isActive ? _exitPip : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SectionHeader('Options'),
        SwitchListTile(
          title: const Text('Auto-enter PiP on background'),
          subtitle: const Text(
              'When enabled, the player enters PiP when the app is backgrounded.'),
          value: _autoEnterOnBackground,
          onChanged: _pipAvailable
              ? (v) {
                  setState(() => _autoEnterOnBackground = v);
                  _controller.updateConfig(_controller.config.copyWith(
                    pipConfig: PipConfig(
                      enabled: true,
                      aspectRatio: 16 / 9,
                      autoEnterOnBackground: v,
                    ),
                  ));
                }
              : null,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        _PipNote(available: _pipAvailable),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool available;
  final PipStatus status;

  const _StatusCard({required this.available, required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(label: 'Available', value: available ? 'Yes' : 'No'),
            InfoRow(
                label: 'Supported', value: status.isSupported ? 'Yes' : 'No'),
            InfoRow(label: 'Active', value: status.isActive ? 'Yes' : 'No'),
            InfoRow(label: 'State', value: status.state.name),
            if (status.errorMessage != null)
              InfoRow(label: 'Error', value: status.errorMessage!),
          ],
        ),
      ),
    );
  }
}

class _PipNote extends StatelessWidget {
  final bool available;
  const _PipNote({required this.available});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: available
            ? Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.4)
            : Colors.orange.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        available
            ? 'PiP is available on this device. '
                'Start playback, then tap "Enter PiP" to activate.'
            : 'PiP is NOT available on this device/simulator. '
                'Android requires API 26+. '
                'iOS requires a physical device with AVPictureInPictureController support.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

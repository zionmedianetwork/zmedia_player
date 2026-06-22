import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates error handling and the [MediaPlayerException] hierarchy:
/// - [MediaLoadException] — bad URL / HTTP error
/// - [NetworkException] — connectivity issues
/// - [PlaybackException] — codec / decoding failures
/// - [PlayerState.error] surfaced via [MediaController.state]
/// - [PlaybackState.errorMessage] for human-readable description
/// - [ErrorOverlay] built-in overlay widget
///
/// The page provides three buttons:
///   1. Load a valid URL → happy path
///   2. Load a bad URL → triggers MediaLoadException → PlayerState.error
///   3. Load a non-existent host → triggers NetworkException
class ErrorHandlingPage extends StatefulWidget {
  const ErrorHandlingPage({super.key});

  @override
  State<ErrorHandlingPage> createState() => _ErrorHandlingPageState();
}

class _ErrorHandlingPageState extends State<ErrorHandlingPage> {
  late final MediaController _controller;
  StreamSubscription<PlaybackState>? _stateSub;

  final List<_ErrorEvent> _errorLog = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(playerId: 'error_handling');
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      // Also subscribe at the player level to capture typed exceptions
      _stateSub = _controller.player.stateStream.listen((state) {
        if (state.state == PlayerState.error && state.errorMessage != null) {
          if (mounted) {
            setState(() {
              _errorLog.insert(
                0,
                _ErrorEvent(
                  timestamp: DateTime.now(),
                  message: state.errorMessage!,
                  type: 'PlayerState.error',
                ),
              );
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorLog.insert(
            0,
            _ErrorEvent(
              timestamp: DateTime.now(),
              message: e.toString(),
              type: 'init',
            ),
          );
        });
      }
    }
  }

  Future<void> _loadGood() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(SampleMedia.forBiggerBlazes);
      await _controller.play();
    } catch (e) {
      _logException(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBadUrl() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(
        const MediaItem(
          id: 'bad_url',
          title: 'Bad URL (404)',
          url:
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/THIS_DOES_NOT_EXIST.mp4',
        ),
      );
    } on MediaLoadException catch (e) {
      _logException(e, type: 'MediaLoadException');
    } on MediaPlayerException catch (e) {
      _logException(e, type: e.runtimeType.toString());
    } catch (e) {
      _logException(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBadHost() async {
    setState(() => _isLoading = true);
    try {
      await _controller.load(
        const MediaItem(
          id: 'bad_host',
          title: 'Non-existent Host',
          url: 'https://this-host-does-not-exist-zmedia.invalid/video.mp4',
        ),
      );
    } on NetworkException catch (e) {
      _logException(e, type: 'NetworkException');
    } on MediaLoadException catch (e) {
      _logException(e, type: 'MediaLoadException');
    } on MediaPlayerException catch (e) {
      _logException(e, type: e.runtimeType.toString());
    } catch (e) {
      _logException(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _logException(Object e, {String? type}) {
    if (!mounted) return;
    setState(() {
      _errorLog.insert(
        0,
        _ErrorEvent(
          timestamp: DateTime.now(),
          message: e.toString(),
          type: type ??
              (e is MediaPlayerException
                  ? e.runtimeType.toString()
                  : 'Unknown'),
        ),
      );
      if (_errorLog.length > 10) _errorLog.removeLast();
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Error Handling',
      controller: _controller,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Test Scenarios'),
        _ScenarioButtons(
          isLoading: _isLoading,
          onLoadGood: _loadGood,
          onLoadBadUrl: _loadBadUrl,
          onLoadBadHost: _loadBadHost,
        ),
        const SizedBox(height: 16),
        const SectionHeader('Live Player State'),
        _LiveStateCard(controller: _controller),
        const SizedBox(height: 16),
        const SectionHeader('Error Log'),
        if (_errorLog.isEmpty)
          Text(
            'No errors yet. Tap a scenario above to trigger one.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ..._errorLog.map((e) => _ErrorEventTile(event: e)),
        const SizedBox(height: 16),
        const _ErrorHandlingNote(),
      ],
    );
  }
}

class _ScenarioButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onLoadGood;
  final VoidCallback onLoadBadUrl;
  final VoidCallback onLoadBadHost;

  const _ScenarioButtons({
    required this.isLoading,
    required this.onLoadGood,
    required this.onLoadBadUrl,
    required this.onLoadBadHost,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Load Valid URL'),
          onPressed: isLoading ? null : onLoadGood,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.broken_image),
          label: const Text('Bad URL (404)'),
          onPressed: isLoading ? null : onLoadBadUrl,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.wifi_off),
          label: const Text('Bad Host'),
          onPressed: isLoading ? null : onLoadBadHost,
        ),
      ],
    );
  }
}

class _LiveStateCard extends StatelessWidget {
  final MediaController controller;
  const _LiveStateCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final isError = state.state == PlayerState.error;
        return Card(
          margin: EdgeInsets.zero,
          color: isError ? Theme.of(context).colorScheme.errorContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(label: 'State', value: state.state.name),
                if (state.errorMessage != null)
                  InfoRow(label: 'Error', value: state.errorMessage!),
                InfoRow(
                    label: 'Has Error',
                    value: controller.hasError ? 'Yes' : 'No'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorEventTile extends StatelessWidget {
  final _ErrorEvent event;
  const _ErrorEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color:
          Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline,
                    size: 14, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 4),
                Text(
                  event.type,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${event.timestamp.second.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              event.message,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorHandlingNote extends StatelessWidget {
  const _ErrorHandlingNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Exception types: MediaLoadException, NetworkException, DrmException, '
        'PlaybackException, ConfigurationException, InvalidStateException, '
        'PlayerDisposedException, PlatformOperationException.\n'
        'All extend sealed class MediaPlayerException.\n'
        'Error state is also surfaced via player.stateStream (PlayerState.error) '
        'with errorMessage on PlaybackState.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorEvent {
  final DateTime timestamp;
  final String message;
  final String type;

  _ErrorEvent({
    required this.timestamp,
    required this.message,
    required this.type,
  });
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates media playback notifications via [NotificationService]:
/// - Configuring [NotificationConfig] with show/hide action flags
/// - [NotificationService.initialize] with a [MediaPlayer]
/// - [NotificationService.updateConfig] to change those flags at runtime --
///   the config only reaches native at `initialize()` time, so toggling a
///   checkbox here has to re-send it or nothing changes on the lock screen
/// - [NotificationService.show] to display / update the notification
/// - [NotificationService.dismiss] to remove the notification
/// - [NotificationService.actionEventStream] to receive play/pause/next/seekTo
///   actions (typed as [NotificationActionEvent], which carries the seek
///   position for "seekTo")
///
/// REQUIREMENTS:
///   Android 13+ requires POST_NOTIFICATIONS permission at runtime.
///   iOS requires notification permission granted by the user.
///   Background audio on iOS requires UIBackgroundModes (audio) in Info.plist.
///
/// NOTE: On Android, the notification is shown in the system tray.
/// On iOS, it appears in the lock screen and Control Center.
/// The notification actions (play, pause, next, previous, seekTo) call back via
/// [MediaPlayer.notificationActionEventStream].
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final MediaController _controller;
  late final NotificationService _notificationService;
  StreamSubscription<NotificationActionEvent>? _actionSub;

  bool _isLoading = false;
  bool _notifShowing = false;
  String? _error;
  final List<String> _receivedActions = [];

  // Notification options
  bool _showNext = true;
  bool _showPrevious = true;
  bool _showStop = false;
  bool _showSeekForward = false;
  bool _showSeekBackward = false;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'notifications_demo',
      // respectSafeArea keeps the video below the status bar / notch in
      // landscape so content is never obscured. Set immersiveLandscape: true
      // instead if you want the status bar hidden in landscape.
      config: const MediaConfig(respectSafeArea: true),
    );
    _notificationService = NotificationService(
      _buildNotificationConfig(),
    );
    _initAndLoad();
  }

  NotificationConfig _buildNotificationConfig() {
    return NotificationConfig(
      enabled: true,
      channelId: 'zmedia_example_playback',
      channelName: 'ZMedia Playback',
      channelDescription: 'Media playback controls',
      showPlayPause: true,
      showNext: _showNext,
      showPrevious: _showPrevious,
      showStop: _showStop,
      showSeekForward: _showSeekForward,
      showSeekBackward: _showSeekBackward,
      seekInterval: 10,
      showWhenPaused: true,
      priority: NotificationPriority.high,
    );
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _controller.initialize();

      // Initialize notification service with the underlying player
      await _notificationService.initialize(
        _controller.playerId,
        mediaPlayer: _controller.player,
      );

      // Listen for notification actions. actionEventStream (not the
      // deprecated actionStream) is required here because "seekTo" (dragging
      // the lock-screen / Control Center scrub bar) only carries its target
      // position on the typed event stream.
      _actionSub?.cancel();
      _actionSub = _notificationService.actionEventStream.listen((event) {
        if (mounted) {
          setState(() {
            final label = event.position != null
                ? '${event.action} (${event.position})'
                : event.action;
            _receivedActions.insert(0, label);
            if (_receivedActions.length > 10) _receivedActions.removeLast();
          });
          _handleNotificationAction(event);
        }
      });

      // Load a short playlist (starting with the full ~10-minute Big Buck
      // Bunny) so every lock-screen control is testable: play/pause, the ±10s
      // skip/seek (needs runtime), and next/previous (needs a playlist).
      await _controller.setPlaylist(
        const Playlist(
          id: 'notif_demo',
          title: 'Notifications Demo',
          items: [
            SampleMedia.forBiggerFun,
            SampleMedia.bigBuckBunny,
            SampleMedia.elephantsDream,
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleNotificationAction(NotificationActionEvent event) {
    switch (event.action) {
      case 'play':
        _controller.play();
        break;
      case 'pause':
        _controller.pause();
        break;
      case 'next':
        _controller.skipToNext();
        break;
      case 'previous':
        _controller.skipToPrevious();
        break;
      case 'stop':
        _controller.stop();
        break;
      // NotificationConfig.seekInterval only *labels* the platform control --
      // the host app performs the seek and must pass the matching Duration.
      case NotificationActions.seekForward:
        _controller.seekForward(const Duration(seconds: 10));
        break;
      case NotificationActions.seekBackward:
        _controller.seekBackward(const Duration(seconds: 10));
        break;
      case NotificationActions.seekTo:
        // The host app -- not the package -- is responsible for performing
        // this seek: NotificationService only forwards the event.
        final position = event.position;
        if (position != null) {
          _controller.seekTo(position);
        }
        break;
    }
  }

  /// Pushes the checkbox state to native.
  ///
  /// [NotificationConfig] is immutable and is only handed to native by
  /// [NotificationService.initialize] -- `show()` renders from whatever config
  /// native already holds. Without this call the checkboxes would flip local
  /// booleans and change nothing on the lock screen / notification tray.
  ///
  /// `updateConfig` also re-renders a notification that is currently showing,
  /// so a toggle is visible immediately with no extra "Show / Update" tap.
  Future<void> _applyNotificationConfig() async {
    try {
      await _notificationService.updateConfig(
        _buildNotificationConfig(),
        playerId: _controller.playerId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update notification config failed: $e')),
        );
      }
    }
  }

  Future<void> _showNotification() async {
    final item = _controller.currentItem;
    if (item == null) return;
    try {
      await _notificationService.show(
        mediaItem: item,
        state: _controller.state,
        playerId: _controller.playerId,
      );
      if (mounted) setState(() => _notifShowing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Show notification failed: $e')),
        );
      }
    }
  }

  Future<void> _dismissNotification() async {
    try {
      await _notificationService.dismiss(_controller.playerId);
      if (mounted) setState(() => _notifShowing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dismiss failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    _notificationService.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Notifications',
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
        const SectionHeader('Notification Actions'),
        _OptionsPanel(
          showNext: _showNext,
          showPrevious: _showPrevious,
          showStop: _showStop,
          showSeekForward: _showSeekForward,
          showSeekBackward: _showSeekBackward,
          onChanged: (next, prev, stop, fwd, bwd) {
            setState(() {
              _showNext = next;
              _showPrevious = prev;
              _showStop = stop;
              _showSeekForward = fwd;
              _showSeekBackward = bwd;
            });
            _applyNotificationConfig();
          },
        ),
        const SizedBox(height: 16),
        const SectionHeader('Notification Controls'),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: const Text('Show / Update'),
              onPressed: _showNotification,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.notifications_off),
              label: const Text('Dismiss'),
              onPressed: _notifShowing ? _dismissNotification : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_receivedActions.isNotEmpty) ...[
          const SectionHeader('Received Actions'),
          ..._receivedActions.map((action) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_forward_ios, size: 12),
                    const SizedBox(width: 4),
                    Text(action),
                  ],
                ),
              )),
        ],
        const SizedBox(height: 16),
        const _NotifNote(),
      ],
    );
  }
}

class _OptionsPanel extends StatelessWidget {
  final bool showNext;
  final bool showPrevious;
  final bool showStop;
  final bool showSeekForward;
  final bool showSeekBackward;
  final void Function(bool, bool, bool, bool, bool) onChanged;

  const _OptionsPanel({
    required this.showNext,
    required this.showPrevious,
    required this.showStop,
    required this.showSeekForward,
    required this.showSeekBackward,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CheckboxListTile(
          title: const Text('Show Next'),
          value: showNext,
          onChanged: (v) => onChanged(
              v!, showPrevious, showStop, showSeekForward, showSeekBackward),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          title: const Text('Show Previous'),
          value: showPrevious,
          onChanged: (v) => onChanged(
              showNext, v!, showStop, showSeekForward, showSeekBackward),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          title: const Text('Show Stop'),
          value: showStop,
          onChanged: (v) => onChanged(
              showNext, showPrevious, v!, showSeekForward, showSeekBackward),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          title: const Text('Show Seek Forward (+10s)'),
          subtitle: const Text(
            'Applied immediately via updateConfig(). Rendered only when the '
            'item is also seekable — the demo playlist is all VOD, so it is',
          ),
          value: showSeekForward,
          onChanged: (v) =>
              onChanged(showNext, showPrevious, showStop, v!, showSeekBackward),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          title: const Text('Show Seek Backward (-10s)'),
          subtitle: const Text(
            'Applied immediately via updateConfig(). Rendered only when the '
            'item is also seekable — the demo playlist is all VOD, so it is',
          ),
          value: showSeekBackward,
          onChanged: (v) =>
              onChanged(showNext, showPrevious, showStop, showSeekForward, v!),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}

class _NotifNote extends StatelessWidget {
  const _NotifNote();

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
        'Android 13+ requires POST_NOTIFICATIONS permission.\n'
        'iOS requires user permission and UIBackgroundModes (audio) in Info.plist.\n'
        'API: NotificationService(config) -> initialize(playerId, mediaPlayer) -> '
        'show(mediaItem, state, playerId) / dismiss(playerId).\n'
        'The config reaches native only at initialize(); the checkboxes above '
        'call updateConfig(config, playerId:), which re-sends it and re-renders '
        'a showing notification in place.\n'
        'Actions arrive on actionEventStream (drag the lock-screen / Control '
        'Center scrub bar to test "seekTo", which carries the target '
        'position).',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

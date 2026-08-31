import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// On-device verification harness for four previously-inert config
/// parameters that a recent branch wired up. Nothing else in the example
/// app exercises any of these, so without this page every one of them would
/// be unverifiable on a physical device (see the "Two other features in
/// this repo shipped broken" warning in `secure_output_page.dart` — this
/// page exists for the same reason, for a different set of features):
///
/// 1. **Live seek gating** ([HlsConfig.enableDvr] / [DashConfig.enableDvr]).
///    [MediaPlayer.isLive] / [MediaPlayer.dvrEnabled] / [MediaPlayer.isSeekable]
///    are read live, and a "Try Seek" button calls [MediaPlayer.seekTo]
///    directly and displays the outcome (success, or the thrown exception's
///    type + message) so the headline fix — live-without-DVR seeking is
///    rejected, live-with-DVR and VOD are unaffected — is visible on screen,
///    not just in a debug log.
/// 2. **[HlsConfig.liveLatency]** — settable and reloadable; position /
///    duration / bufferedPosition are shown as the best available proxy
///    (see the section's own disclaimer for why nothing more precise than
///    that is exposed).
/// 3. **[NotificationConfig.customActions] / .priority / .dismissible**
///    (Android only — see those fields' dartdocs for why iOS cannot honour
///    them). The notification is posted automatically the first time
///    playback starts (see [_maybeAutoShowNotification]) — it used to only
///    appear after an explicit "Show Notification" tap, which made device
///    testing confusing (a missing notification looked identical to a
///    broken one). "Show / Update now" / "Dismiss" remain as manual
///    overrides. Two distinct custom actions are configured; tapping one in
///    the system notification is routed back via
///    [NotificationService.actionEventStream] and logged on screen.
/// 4. **[PipConfig.actions]** (Android only — see that field's dartdoc for
///    why AVKit has no equivalent). Tapping a custom PiP action button is
///    routed back via [MediaPlayer.pipActionStream] and logged on screen.
///
/// Uses [SampleMedia.hlsLiveStream] (Unified Streaming's public demo
/// channel) as the live fixture — verified genuinely live (not merely
/// "200 with no ENDLIST", which a dead/404 variant can satisfy trivially)
/// via the 4-step procedure documented on that constant, most recently
/// re-confirmed by hand: master 200, child 200 with real `#EXTINF` segment
/// lines, no `#EXT-X-ENDLIST`, and `#EXT-X-MEDIA-SEQUENCE` advancing on a
/// re-fetch ~15s later.
class WiredConfigVerificationPage extends StatefulWidget {
  const WiredConfigVerificationPage({super.key});

  @override
  State<WiredConfigVerificationPage> createState() =>
      _WiredConfigVerificationPageState();
}

class _WiredConfigVerificationPageState
    extends State<WiredConfigVerificationPage> {
  late final MediaController _controller;
  NotificationService? _notificationService;

  StreamSubscription<PipStatus>? _pipStatusSub;
  StreamSubscription<PipActionEvent>? _pipActionSub;
  StreamSubscription<NotificationActionEvent>? _notifActionSub;

  bool _isLoading = false;
  String? _error;

  // --- Section 1/2: live seek gating + liveLatency -------------------------
  bool _useLiveSource = true;
  bool _dvrEnabled = false;
  Duration? _liveLatency; // null = off
  String? _seekOutcome;
  bool _reloading = false;

  // --- Section 3: notifications (Android only) ------------------------------
  bool _notifShowing = false;
  // null == "unset", NotificationConfig.priority's own default (falls back
  // to IMPORTANCE_LOW/PRIORITY_LOW natively -- see that field's dartdoc).
  // Starting here, rather than at NotificationPriority.max, demonstrates the
  // field without immediately posting a maximum-priority heads-up
  // notification for a demo page whose "Show / Update" button is expected
  // to be tapped repeatedly.
  NotificationPriority? _notifPriority;
  bool _notifDismissible = true;
  final List<String> _notifActionEvents = [];

  // --- Section 4: PiP custom actions (Android only) -------------------------
  bool _pipAvailable = false;
  PipStatus _pipStatus = const PipStatus(
    state: PipState.unavailable,
    isSupported: false,
    isActive: false,
  );
  final List<String> _pipActionEvents = [];

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static const _pipConfig = PipConfig(
    enabled: true,
    aspectRatio: 16 / 9,
    actions: [
      PipAction(id: 'pip_demo_like', title: 'Like'),
      PipAction(id: 'pip_demo_skip30', title: '+30s'),
    ],
    showPlaybackControls: true,
  );

  MediaItem get _liveItem => SampleMedia.hlsLiveStream;
  // Full ~10-minute progressive MP4 — its URL path ends in neither `.m3u8`
  // nor `.mpd` and it declares no `MediaItem.streamingFormat`, so it resolves
  // to StreamingFormat.progressive and neither HlsConfig nor DashConfig ever
  // applies to it. This is the regression check: toggling `enableDvr` must
  // have zero effect here.
  MediaItem get _vodItem => SampleMedia.forBiggerFun;

  MediaItem get _currentSourceItem => _useLiveSource ? _liveItem : _vodItem;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'wired_config_verification_demo',
      config: MediaConfig(
        respectSafeArea: true,
        pipConfig: _pipConfig,
        hlsConfig: HlsConfig(enableDvr: _dvrEnabled, liveLatency: _liveLatency),
      ),
    );
    _controller.addListener(_onControllerChanged);
    _initAndLoad();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoShowNotification();
  }

  /// Posts the notification the first time playback actually starts,
  /// instead of requiring the user to find and tap "Show Notification"
  /// first. On a device, a notification that never appears looks
  /// identical to a broken one, and this page exists specifically to make
  /// wired behaviour visible without a hidden manual step -- see the class
  /// dartdoc. "Show Notification" / "Dismiss Notification" remain below as
  /// manual overrides (e.g. to re-show after a manual dismiss, or to force
  /// an update while paused).
  bool _autoShowInFlight = false;
  void _maybeAutoShowNotification() {
    if (_notifShowing || _autoShowInFlight) return;
    if (_notificationService == null) return;
    if (_controller.state.state != PlayerState.playing) return;
    _autoShowInFlight = true;
    _showNotification().whenComplete(() => _autoShowInFlight = false);
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _controller.initialize();

      _pipStatusSub = _controller.player.pipStatusStream.listen((status) {
        if (mounted) setState(() => _pipStatus = status);
      });
      _pipActionSub = _controller.player.pipActionStream.listen((event) {
        if (mounted) {
          setState(() {
            _pipActionEvents.insert(0, event.actionId);
            if (_pipActionEvents.length > 10) _pipActionEvents.removeLast();
          });
        }
      });

      await _controller.load(_currentSourceItem);

      _pipAvailable = await _controller.checkPipAvailability();

      await _setUpNotificationService();
      // Covers the case where autoPlay already reached PlayerState.playing
      // before _notificationService existed to catch the transition via
      // _onControllerChanged -- without this, a fast/cached load could
      // start playing and settle before there was ever a listener able to
      // notice.
      _maybeAutoShowNotification();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------
  // Section 1/2: live seek gating + liveLatency
  // ---------------------------------------------------------------------

  /// Rebuilds [MediaConfig.hlsConfig] from [_dvrEnabled]/[_liveLatency] and
  /// reloads the current source. `enableDvr`/`liveLatency` are only read by
  /// `MediaPlayer.load()` (see `_applyStreamingConfigForLoad`), so changing
  /// either without a reload would have no observable effect — this is the
  /// exact mechanism the task calls out as easy to get wrong.
  Future<void> _reloadWithCurrentSettings() async {
    setState(() {
      _reloading = true;
      _seekOutcome = null;
    });
    try {
      await _controller.updateConfig(
        _controller.config.copyWith(
          hlsConfig: HlsConfig(
            enableDvr: _dvrEnabled,
            liveLatency: _liveLatency,
          ),
        ),
      );
      await _controller.load(_currentSourceItem);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<void> _trySeek() async {
    final player = _controller.player;
    final target = _controller.position + const Duration(seconds: 30);
    setState(() => _seekOutcome = 'Seeking to $target ...');
    try {
      await player.seekTo(target);
      if (mounted) {
        setState(() => _seekOutcome = 'SUCCESS: seekTo($target) completed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _seekOutcome = 'REJECTED: ${e.runtimeType} -- $e');
      }
    }
  }

  // ---------------------------------------------------------------------
  // Section 3: notifications
  // ---------------------------------------------------------------------

  NotificationConfig _buildNotificationConfig() {
    return NotificationConfig(
      enabled: true,
      channelId: 'zmedia_wired_config_demo',
      channelName: 'Wired Config Demo',
      channelDescription: 'C-verification: customActions/priority/dismissible',
      showPlayPause: true,
      showNext: false,
      showPrevious: false,
      customActions: const [
        NotificationAction(id: 'wired_demo_like', title: 'Like'),
        NotificationAction(id: 'wired_demo_bookmark', title: 'Bookmark'),
      ],
      priority: _notifPriority,
      dismissible: _notifDismissible,
    );
  }

  /// Builds the service once. The config it is constructed with reaches native
  /// at [NotificationService.initialize] time; every later change goes through
  /// [_applyNotificationConfig].
  Future<void> _setUpNotificationService() async {
    await _notifActionSub?.cancel();
    _notificationService?.dispose();

    final service = NotificationService(_buildNotificationConfig());
    await service.initialize(_controller.playerId,
        mediaPlayer: _controller.player);
    _notifActionSub = service.actionEventStream.listen((event) {
      if (mounted) {
        setState(() {
          final label = event.position != null
              ? '${event.action} (${event.position})'
              : event.action;
          _notifActionEvents.insert(0, label);
          if (_notifActionEvents.length > 10) _notifActionEvents.removeLast();
        });
      }
    });

    _notificationService = service;
    _notifShowing = false;
    if (mounted) setState(() {});
  }

  /// [NotificationConfig] is immutable and is only handed to native by
  /// [NotificationService.initialize] -- `show()` renders from whatever config
  /// native already holds -- so a runtime change has to go through
  /// [NotificationService.updateConfig], which re-sends it and re-renders a
  /// notification that is already showing.
  ///
  /// Caveat specific to `priority`: it also drives the Android
  /// `NotificationChannel` importance, and the OS ignores importance changes to
  /// an already-created channel. Re-sending the config re-applies
  /// `NotificationCompat.setPriority`, but the channel importance the user sees
  /// only changes for a channel Android has not created yet (new `channelId`,
  /// fresh install, or notification settings reset). `dismissible` and
  /// `customActions` are read on every post and do change immediately.
  Future<void> _applyNotificationConfig() async {
    final service = _notificationService;
    if (service == null) return;
    await service.updateConfig(
      _buildNotificationConfig(),
      playerId: _controller.playerId,
    );
    if (mounted) setState(() {});
  }

  Future<void> _showNotification() async {
    final item = _controller.currentItem;
    final service = _notificationService;
    if (item == null || service == null) return;
    try {
      await service.show(
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
    final service = _notificationService;
    if (service == null) return;
    try {
      await service.dismiss(_controller.playerId);
      if (mounted) setState(() => _notifShowing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dismiss failed: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Section 4: PiP
  // ---------------------------------------------------------------------

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
    _controller.removeListener(_onControllerChanged);
    _pipStatusSub?.cancel();
    _pipActionSub?.cancel();
    _notifActionSub?.cancel();
    _notificationService?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Wired Config Verification',
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
    final player = _controller.player;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('1. Live Seek Gating (headline fix)'),
        _buildSourceAndDvrControls(),
        const SizedBox(height: 12),
        _SeekabilityCard(
          isLive: player.isLive,
          dvrEnabled: player.dvrEnabled,
          isSeekable: player.isSeekable,
          currentItemTitle: _controller.currentItem?.title ?? '(none)',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('try_seek_button'),
          icon: const Icon(Icons.fast_forward),
          label: const Text('Try Seek (+30s)'),
          onPressed: _reloading ? null : _trySeek,
        ),
        if (_seekOutcome != null) ...[
          const SizedBox(height: 8),
          _OutcomeBanner(text: _seekOutcome!),
        ],
        const SizedBox(height: 12),
        const _LiveSeekInstructions(),
        const SizedBox(height: 24),
        const SectionHeader('2. Live Latency (HlsConfig.liveLatency)'),
        _buildLiveLatencyControls(),
        const SizedBox(height: 12),
        _PositionReadout(state: _controller.state),
        const SizedBox(height: 8),
        const _LiveLatencyDisclaimer(),
        const SizedBox(height: 24),
        const SectionHeader(
            '3. Notifications — customActions/priority/dismissible'),
        if (!_isAndroid)
          const _AndroidOnlyNote(
              feature: 'NotificationConfig.customActions/priority/dismissible'),
        const SizedBox(height: 8),
        _buildNotificationControls(),
        const SizedBox(height: 12),
        if (_notifActionEvents.isNotEmpty)
          _EventLog(
              title: 'Received notification actions',
              events: _notifActionEvents),
        const SizedBox(height: 24),
        const SectionHeader('4. Picture-in-Picture — PipConfig.actions'),
        if (!_isAndroid) const _AndroidOnlyNote(feature: 'PipConfig.actions'),
        const SizedBox(height: 8),
        _buildPipControls(),
        const SizedBox(height: 12),
        if (_pipActionEvents.isNotEmpty)
          _EventLog(title: 'Received PiP actions', events: _pipActionEvents),
      ],
    );
  }

  Widget _buildSourceAndDvrControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Source', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Live HLS')),
            ButtonSegment(value: false, label: Text('VOD MP4')),
          ],
          selected: {_useLiveSource},
          onSelectionChanged: _reloading
              ? null
              : (selected) {
                  setState(() => _useLiveSource = selected.first);
                  _reloadWithCurrentSettings();
                },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('dvr_toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('HlsConfig.enableDvr'),
          subtitle: const Text(
            'Rebuilds MediaConfig and reloads on every change (enableDvr is '
            'only read during load()).',
          ),
          value: _dvrEnabled,
          onChanged: _reloading
              ? null
              : (v) {
                  setState(() => _dvrEnabled = v);
                  _reloadWithCurrentSettings();
                },
        ),
        if (_reloading) ...[
          const SizedBox(height: 4),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Widget _buildLiveLatencyControls() {
    return SegmentedButton<Duration?>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: null, label: Text('off')),
        ButtonSegment(value: Duration(seconds: 3), label: Text('3s')),
        ButtonSegment(value: Duration(seconds: 8), label: Text('8s')),
      ],
      selected: {_liveLatency},
      onSelectionChanged: _reloading
          ? null
          : (selected) {
              setState(() => _liveLatency = selected.first);
              _reloadWithCurrentSettings();
            },
    );
  }

  Widget _buildNotificationControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(
          label: 'Posted',
          value: _notifShowing
              ? 'Yes (auto-posted once playback starts)'
              : 'No -- will post automatically once playback starts',
        ),
        const SizedBox(height: 8),
        Text('Priority', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<NotificationPriority?>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: null, label: Text('unset (low)')),
            ButtonSegment(
                value: NotificationPriority.defaultPriority,
                label: Text('default')),
            ButtonSegment(
                value: NotificationPriority.high, label: Text('high')),
            ButtonSegment(value: NotificationPriority.max, label: Text('max')),
          ],
          selected: {_notifPriority},
          onSelectionChanged: (selected) {
            setState(() => _notifPriority = selected.first);
            _applyNotificationConfig();
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('dismissible_toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('NotificationConfig.dismissible'),
          value: _notifDismissible,
          onChanged: (v) {
            setState(() => _notifDismissible = v);
            _applyNotificationConfig();
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: const Text('Show / Update now'),
              onPressed: _showNotification,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.notifications_off),
              label: const Text('Dismiss'),
              onPressed: _notifShowing ? _dismissNotification : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPipControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(label: 'Available', value: _pipAvailable ? 'Yes' : 'No'),
        InfoRow(label: 'Active', value: _pipStatus.isActive ? 'Yes' : 'No'),
        const SizedBox(height: 8),
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
      ],
    );
  }
}

class _SeekabilityCard extends StatelessWidget {
  final bool isLive;
  final bool dvrEnabled;
  final bool isSeekable;
  final String currentItemTitle;

  const _SeekabilityCard({
    required this.isLive,
    required this.dvrEnabled,
    required this.isSeekable,
    required this.currentItemTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(label: 'Item', value: currentItemTitle),
            KeyedSubtree(
              key: const Key('isLive_row'),
              child: InfoRow(label: 'isLive', value: isLive.toString()),
            ),
            KeyedSubtree(
              key: const Key('dvrEnabled_row'),
              child: InfoRow(label: 'dvrEnabled', value: dvrEnabled.toString()),
            ),
            KeyedSubtree(
              key: const Key('isSeekable_row'),
              child: InfoRow(label: 'isSeekable', value: isSeekable.toString()),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  final String text;
  const _OutcomeBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final isRejected = text.startsWith('REJECTED');
    final isSuccess = text.startsWith('SUCCESS');
    final color = isRejected
        ? Colors.orange.shade900
        : isSuccess
            ? Colors.green.shade900
            : Theme.of(context).colorScheme.secondaryContainer;
    return Container(
      key: const Key('seek_outcome_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _LiveSeekInstructions extends StatelessWidget {
  const _LiveSeekInstructions();

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
        'Also check the lock screen / notification shade (use section 3 '
        'below to show it): with DVR OFF on the live source there must be '
        'NO scrubber and no seek control there; with DVR ON, the scrubber '
        'must be present. Switching to VOD MP4 must always allow seeking '
        'regardless of the DVR toggle -- that is the key regression risk '
        'this page checks.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _PositionReadout extends StatelessWidget {
  final PlaybackState state;
  const _PositionReadout({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(label: 'position', value: state.position.toString()),
            InfoRow(label: 'duration', value: state.duration.toString()),
            InfoRow(
                label: 'bufferedPosition',
                value: state.bufferedPosition.toString()),
          ],
        ),
      ),
    );
  }
}

class _LiveLatencyDisclaimer extends StatelessWidget {
  const _LiveLatencyDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade900.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'This package exposes no explicit "distance from live edge" value. '
        'position/duration/bufferedPosition above are the only observable '
        'proxies -- liveLatency\'s actual effect (how close to the live '
        'edge playback starts, Android: LiveConfiguration.targetOffsetMs, '
        'iOS 14+: configuredTimeOffsetFromLive) must be judged by ear/eye '
        'against the real stream after reloading with each option, not '
        'asserted from a Dart-exposed field.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _AndroidOnlyNote extends StatelessWidget {
  final String feature;
  const _AndroidOnlyNote({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$feature is Android-only by design (see its dartdoc for why iOS '
        'has no faithful equivalent). Controls below are still usable on '
        'iOS, but they will not be observably different from the '
        'framework default there -- that is expected, not broken.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  final String title;
  final List<String> events;
  const _EventLog({required this.title, required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        ...events.map((event) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.arrow_forward_ios, size: 12),
                  const SizedBox(width: 4),
                  Expanded(child: Text(event)),
                ],
              ),
            )),
      ],
    );
  }
}

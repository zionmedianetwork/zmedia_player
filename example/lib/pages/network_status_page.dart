import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Manual verification harness for Phase 3's `NetworkMonitor` wiring (H-06):
/// [MediaPlayer.networkStatus], [MediaPlayer.networkStatusStream] and
/// [MediaPlayer.networkChangeStream], backed natively by
/// `ConnectivityManager.NetworkCallback` (Android) / `NWPathMonitor` (iOS).
///
/// This page intentionally does **not** load or play any media — connectivity
/// monitoring is independent of playback. A single [MediaController] is
/// created and initialized purely so its underlying [MediaPlayer] instance
/// is registered as "active" with native and therefore receives connectivity
/// broadcasts; see the note below on why that registration timing matters.
///
/// ### Why the status can start (and stay) "Unknown"
/// Both native `NetworkMonitor`s start monitoring once, at plugin
/// attach/app-launch, and immediately fire one "current status" callback —
/// but only to *currently active* player ids
/// (`ZMediaPlayerPlugin.activePlayerIds`). At app launch that set is empty,
/// so that very first callback is dropped on the floor. A player that
/// initializes afterwards (like this page's) is **not** sent a fresh
/// snapshot on registration — it only receives *future* events. In practice
/// this means: after opening this page, [networkStatus] reads as
/// [NetworkQuality.unknown] and nothing appears in the log until an actual
/// connectivity transition happens (toggle airplane mode, switch
/// WiFi↔cellular, etc.) — even if the device already has a perfectly good
/// connection. This is expected behavior, not a bug in this page.
///
/// ### Log line format
/// - `[NET] STATUS quality=<q> type=<t> metered=<bool> downloadKbps=<n> rtt=<ms|-> signal=<0-1|-> @<HH:mm:ss>`
///   — every [networkStatusStream] emission (raw push from native).
/// - `[NET] CHANGE <summary> (prev=<q|none> -> now=<q>) lost=<bool> restored=<bool> improved=<bool> degraded=<bool> @<HH:mm:ss>`
///   — every [networkChangeStream] emission (only "significant" transitions:
///   connection lost/restored or quality bucket changed).
///
/// Both are mirrored on screen (primary readout — this runs as a release
/// build on a physical device where `debugPrint` capture is not guaranteed)
/// and printed to the console with the same `[NET]` prefix so they stay
/// greppable when console capture *is* available.
class NetworkStatusPage extends StatefulWidget {
  const NetworkStatusPage({super.key});

  @override
  State<NetworkStatusPage> createState() => _NetworkStatusPageState();
}

class _NetworkStatusPageState extends State<NetworkStatusPage> {
  late final MediaController _controller;
  StreamSubscription<NetworkStatus>? _statusSub;
  StreamSubscription<NetworkChangeEvent>? _changeSub;

  NetworkStatus? _currentStatus;
  bool _initError = false;
  String? _initErrorMessage;
  final List<String> _eventLog = [];

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'network_status',
    );
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      final player = _controller.player;

      // Snapshot whatever native has reported so far (likely `unknown()` —
      // see class doc). Refreshed from every stream event below.
      setState(() => _currentStatus = player.networkStatus);

      _statusSub = player.networkStatusStream.listen(_onStatus);
      _changeSub = player.networkChangeStream.listen(_onChange);

      _log('[NET] listening on networkStatusStream + networkChangeStream '
          '(playerId=${_controller.playerId})');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = true;
        _initErrorMessage = e.toString();
      });
      _log('[NET] INIT ERROR: $e');
    }
  }

  void _onStatus(NetworkStatus status) {
    if (mounted) setState(() => _currentStatus = status);
    _log('[NET] STATUS ${_describeStatus(status)}');
  }

  void _onChange(NetworkChangeEvent change) {
    _log(
      '[NET] CHANGE ${change.toString()} '
      '(prev=${change.previousStatus?.quality.name ?? 'none'} -> '
      'now=${change.currentStatus.quality.name}) '
      'lost=${change.connectionLost} restored=${change.connectionRestored} '
      'improved=${change.qualityImproved} degraded=${change.qualityDegraded} '
      '@${_timeOf(DateTime.now())}',
    );
  }

  String _describeStatus(NetworkStatus status) {
    final downloadKbps = (status.downloadSpeed * 8) / 1000;
    return 'quality=${status.quality.name} '
        'type=${status.connectionType.name} '
        'metered=${status.isMetered} '
        'downloadKbps=${downloadKbps.toStringAsFixed(0)} '
        'rtt=${status.rtt ?? '-'} '
        'signal=${status.signalStrength?.toStringAsFixed(2) ?? '-'} '
        '@${_timeOf(status.timestamp)}';
  }

  String _timeOf(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  void _log(String line) {
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      _eventLog.insert(0, line);
      if (_eventLog.length > 60) _eventLog.removeLast();
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _changeSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network Status (H-06)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IntroCard(),
              const SizedBox(height: 16),
              Text('Current status',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_initError)
                _ErrorBanner(message: _initErrorMessage ?? 'Unknown error')
              else
                _CurrentStatusCard(status: _currentStatus),
              const SizedBox(height: 16),
              Text(
                'Event log (mirrors console [NET] lines, newest first)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 340),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _eventLog.isEmpty
                    ? const Text('No events yet. Toggle airplane mode or '
                        'switch WiFi/cellular to trigger one.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _eventLog.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            _eventLog[index],
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

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
        'No media is loaded on this page — it only exercises OS-level '
        'connectivity monitoring (ConnectivityManager on Android, '
        'NWPathMonitor on iOS), independent of playback. The status below '
        'starts as UNKNOWN and only updates on a real connectivity '
        'transition (this page\'s player is not sent a snapshot merely by '
        'opening the page — see the page-level doc comment). Toggle '
        'airplane mode on/off, or switch WiFi ↔ cellular, to generate '
        'events.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Failed to initialize: $message',
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _CurrentStatusCard extends StatelessWidget {
  final NetworkStatus? status;
  const _CurrentStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Initializing...'),
        ),
      );
    }
    final downloadKbps = (s.downloadSpeed * 8) / 1000;
    final isUnknown = s.quality == NetworkQuality.unknown;
    return Card(
      margin: EdgeInsets.zero,
      color: isUnknown
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : (s.isAvailable
              ? null
              : Theme.of(context).colorScheme.errorContainer),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row('Quality', s.quality.name),
            _Row('Connection type', s.connectionType.name),
            _Row('Metered', s.isMetered ? 'Yes' : 'No'),
            _Row('Download speed', '${downloadKbps.toStringAsFixed(0)} Kbps'),
            if (s.uploadSpeed != null)
              _Row('Upload speed',
                  '${((s.uploadSpeed! * 8) / 1000).toStringAsFixed(0)} Kbps'),
            if (s.rtt != null) _Row('RTT', '${s.rtt} ms'),
            if (s.signalStrength != null)
              _Row('Signal strength', s.signalStrength!.toStringAsFixed(2)),
            _Row('Can stream', s.canStream ? 'Yes' : 'No'),
            _Row(
              'Last updated',
              '${s.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${s.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${s.timestamp.second.toString().padLeft(2, '0')}',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

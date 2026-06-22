import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates cast device discovery and media streaming to Chromecast/AirPlay:
/// - [MediaController.startCastDiscovery] / [MediaController.stopCastDiscovery]
/// - [MediaPlayer.castDevicesStream] — list of discovered [CastDevice]s
/// - [MediaController.connectToCastDevice] / [MediaController.connectAndLoadMedia]
/// - [MediaController.disconnectFromCastDevice]
/// - [MediaController.castStatus] / [MediaController.castStatusStream]
/// - [AirPlayButton] — native iOS route picker for AirPlay
///
/// REQUIREMENTS:
///   Android (Chromecast): Requires Google Play Services and a Chromecast on
///   the same Wi-Fi network. The app must declare the CAST receiver app ID in
///   the manifest or in [CastConfig.chromecastAppId].
///
///   iOS (AirPlay): Requires a physical Apple TV or AirPlay-compatible display
///   on the same Wi-Fi network.  [AirPlayButton] uses native AVRoutePickerView.
///
/// No hardware cast devices are needed to explore the API — discovery will
/// simply return an empty list.
class CastingPage extends StatefulWidget {
  const CastingPage({super.key});

  @override
  State<CastingPage> createState() => _CastingPageState();
}

class _CastingPageState extends State<CastingPage> {
  late final MediaController _controller;
  StreamSubscription<CastStatus>? _castStatusSub;
  StreamSubscription<List<CastDevice>>? _devicesSub;

  CastStatus _castStatus = const CastStatus(
    state: CastState.disconnected,
    isAvailable: false,
    isCasting: false,
  );
  List<CastDevice> _devices = [];
  bool _isDiscovering = false;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'casting_demo',
      config: const MediaConfig(
        castConfig: CastConfig(
          enabled: true,
          enableChromecast: true,
          enableAirPlay: true,
          showCastButton: true,
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

      _castStatusSub?.cancel();
      _castStatusSub = _controller.castStatusStream.listen((status) {
        if (mounted) setState(() => _castStatus = status);
      });

      _devicesSub?.cancel();
      _devicesSub = _controller.player.castDevicesStream.listen((devices) {
        if (mounted) setState(() => _devices = devices);
      });

      await _controller.load(SampleMedia.bigBuckBunny);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDiscovery() async {
    try {
      if (_isDiscovering) {
        await _controller.stopCastDiscovery();
        if (mounted) setState(() => _isDiscovering = false);
      } else {
        await _controller.startCastDiscovery();
        if (mounted) setState(() => _isDiscovering = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Discovery error: $e')),
        );
      }
    }
  }

  Future<void> _connectDevice(CastDevice device) async {
    try {
      await _controller.connectAndLoadMedia(device);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connect failed: $e')),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    try {
      await _controller.disconnectFromCastDevice();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disconnect failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _castStatusSub?.cancel();
    _devicesSub?.cancel();
    if (_isDiscovering) {
      _controller.stopCastDiscovery().ignore();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Casting',
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
    final isIos = !kIsWeb && Platform.isIOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cast status
        const SectionHeader('Cast Status'),
        _CastStatusCard(status: _castStatus),

        // AirPlay button — iOS only native route picker
        if (isIos) ...[
          const SizedBox(height: 16),
          const SectionHeader('AirPlay (iOS)'),
          const _AirPlaySection(),
        ],

        const SizedBox(height: 16),
        const SectionHeader('Device Discovery'),
        Row(
          children: [
            FilledButton.icon(
              icon: Icon(_isDiscovering ? Icons.stop : Icons.search),
              label:
                  Text(_isDiscovering ? 'Stop Discovery' : 'Start Discovery'),
              onPressed: _toggleDiscovery,
            ),
            if (_castStatus.isCasting) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.cast_connected),
                label: const Text('Disconnect'),
                onPressed: _disconnect,
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),
        _DeviceList(
          devices: _devices,
          castStatus: _castStatus,
          isDiscovering: _isDiscovering,
          onConnect: _connectDevice,
          onDisconnect: _disconnect,
        ),

        const SizedBox(height: 16),
        const _CastNote(),
      ],
    );
  }
}

class _CastStatusCard extends StatelessWidget {
  final CastStatus status;
  const _CastStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(label: 'State', value: status.state.name),
            InfoRow(
                label: 'Available', value: status.isAvailable ? 'Yes' : 'No'),
            InfoRow(label: 'Casting', value: status.isCasting ? 'Yes' : 'No'),
            if (status.device != null)
              InfoRow(label: 'Device', value: status.device!.name),
            if (status.errorMessage != null)
              InfoRow(label: 'Error', value: status.errorMessage!),
          ],
        ),
      ),
    );
  }
}

class _AirPlaySection extends StatelessWidget {
  const _AirPlaySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tap the AirPlay button to open the native iOS route picker.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        // AirPlayButton uses AVRoutePickerView — iOS native widget
        AirPlayButton(
          size: 40,
          tintColor: Theme.of(context).colorScheme.primary,
          activeTintColor: Theme.of(context).colorScheme.tertiary,
          prioritizesVideoDevices: true,
        ),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<CastDevice> devices;
  final CastStatus castStatus;
  final bool isDiscovering;
  final ValueChanged<CastDevice> onConnect;
  final VoidCallback onDisconnect;

  const _DeviceList({
    required this.devices,
    required this.castStatus,
    required this.isDiscovering,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (isDiscovering && devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Scanning for cast devices...'),
          ],
        ),
      );
    }

    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No devices found. Start discovery to search for Chromecast / AirPlay devices.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: devices.map((device) {
        final isConnected = castStatus.device?.id == device.id;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            device.type == CastDeviceType.chromecast
                ? Icons.cast
                : device.type == CastDeviceType.airplay
                    ? Icons.airplay
                    : Icons.cast_connected,
          ),
          title: Text(device.name),
          subtitle: Text(device.type.name),
          trailing: isConnected
              ? FilledButton.tonal(
                  onPressed: onDisconnect,
                  child: const Text('Disconnect'),
                )
              : OutlinedButton(
                  onPressed: () => onConnect(device),
                  child: const Text('Connect'),
                ),
        );
      }).toList(),
    );
  }
}

class _CastNote extends StatelessWidget {
  const _CastNote();

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
        'Chromecast: requires Google Play Services + Chromecast on same Wi-Fi.\n'
        'AirPlay: requires physical Apple TV or AirPlay display on same Wi-Fi.\n'
        'API: startCastDiscovery() / connectToCastDevice(device) / '
        'connectAndLoadMedia(device) / disconnectFromCastDevice().\n'
        'Monitor via castStatusStream / castDevicesStream.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

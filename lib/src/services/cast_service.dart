import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/cast_device.dart';
import '../models/media_item.dart';
import '../core/media_player.dart';

/// Service for managing screencast (Chromecast, AirPlay, etc.)
class CastService {
  static const MethodChannel _channel = MethodChannel('flutter_media_player');

  final CastConfig _config;
  final StreamController<List<CastDevice>> _devicesController =
      StreamController<List<CastDevice>>.broadcast();
  final StreamController<CastStatus> _statusController =
      StreamController<CastStatus>.broadcast();

  List<CastDevice> _availableDevices = [];
  CastStatus _currentStatus = const CastStatus(
    state: CastState.disconnected,
    isAvailable: false,
    isCasting: false,
  );

  StreamSubscription<List<CastDevice>>? _devicesSubscription;
  StreamSubscription<CastStatus>? _statusSubscription;

  CastService(this._config);

  /// Stream of available cast devices
  Stream<List<CastDevice>> get devicesStream => _devicesController.stream;

  /// Stream of cast status updates
  Stream<CastStatus> get statusStream => _statusController.stream;

  /// Current cast status
  CastStatus get status => _currentStatus;

  /// Available cast devices
  List<CastDevice> get availableDevices => List.unmodifiable(_availableDevices);

  /// Whether currently casting
  bool get isCasting => _currentStatus.isCasting;

  /// Connected cast device
  CastDevice? get connectedDevice => _currentStatus.device;

  /// Initialize the cast service
  Future<void> initialize(String playerId, MediaPlayer mediaPlayer) async {
    if (!_config.enabled) {
      debugPrint('CastService: Casting is disabled');
      return;
    }

    try {
      await _channel.invokeMethod('initializeCast', {
        'playerId': playerId,
        'config': _config.toMap(),
      });

      // Subscribe to MediaPlayer's cast streams
      _devicesSubscription = mediaPlayer.castDevicesStream.listen((devices) {
        _availableDevices = devices;
        if (!_devicesController.isClosed) {
          _devicesController.add(devices);
        }
        debugPrint(
            'CastService: Devices updated from MediaPlayer: ${devices.length}');
      });

      _statusSubscription = mediaPlayer.castStatusStream.listen((status) {
        _currentStatus = status;
        if (!_statusController.isClosed) {
          _statusController.add(status);
        }
        debugPrint(
            'CastService: Status updated from MediaPlayer: ${status.state}');
      });

      debugPrint('CastService: Initialized successfully');
    } catch (e) {
      debugPrint('CastService: Failed to initialize: $e');
    }
  }

  /// Start discovering cast devices
  Future<void> startDiscovery(String playerId) async {
    if (!_config.enabled) return;

    try {
      await _channel.invokeMethod('startCastDiscovery', {
        'playerId': playerId,
      });

      _updateStatus(_currentStatus.copyWith(state: CastState.discovering));
      debugPrint('CastService: Started discovery');
    } catch (e) {
      debugPrint('CastService: Failed to start discovery: $e');
    }
  }

  /// Stop discovering cast devices
  Future<void> stopDiscovery(String playerId) async {
    if (!_config.enabled) return;

    try {
      await _channel.invokeMethod('stopCastDiscovery', {
        'playerId': playerId,
      });

      debugPrint('CastService: Stopped discovery');
    } catch (e) {
      debugPrint('CastService: Failed to stop discovery: $e');
    }
  }

  /// Connect to a cast device
  Future<bool> connect({
    required CastDevice device,
    required String playerId,
  }) async {
    if (!_config.enabled) return false;

    try {
      _updateStatus(_currentStatus.copyWith(
        state: CastState.connecting,
        device: device,
      ));

      final result = await _channel.invokeMethod('connectToCastDevice', {
        'playerId': playerId,
        'deviceId': device.id,
        'deviceType': device.type.name,
      });

      if (result == true) {
        debugPrint('CastService: Connected to ${device.name}');
        return true;
      } else {
        _updateStatus(_currentStatus.copyWith(
          state: CastState.failed,
          errorMessage: 'Failed to connect to device',
        ));
        return false;
      }
    } catch (e) {
      debugPrint('CastService: Failed to connect: $e');
      _updateStatus(_currentStatus.copyWith(
        state: CastState.failed,
        errorMessage: e.toString(),
      ));
      return false;
    }
  }

  /// Disconnect from current cast device
  Future<void> disconnect(String playerId) async {
    if (!_config.enabled || !_currentStatus.isCasting) return;

    try {
      _updateStatus(_currentStatus.copyWith(state: CastState.disconnecting));

      await _channel.invokeMethod('disconnectFromCastDevice', {
        'playerId': playerId,
      });

      debugPrint('CastService: Disconnected from cast device');
    } catch (e) {
      debugPrint('CastService: Failed to disconnect: $e');
    }
  }

  /// Load media on cast device
  Future<void> loadMedia({
    required MediaItem mediaItem,
    required String playerId,
  }) async {
    if (!_config.enabled || !_currentStatus.isCasting) return;

    try {
      await _channel.invokeMethod('loadMediaOnCastDevice', {
        'playerId': playerId,
        'mediaItem': {
          'id': mediaItem.id,
          'title': mediaItem.title,
          'url': mediaItem.url,
          'artworkUrl': mediaItem.artworkUrl,
          'duration': mediaItem.duration?.inMilliseconds,
        },
      });

      debugPrint('CastService: Loaded media on cast device');
    } catch (e) {
      debugPrint('CastService: Failed to load media: $e');
    }
  }

  /// Control playback on cast device
  Future<void> play(String playerId) async {
    if (!_currentStatus.isCasting) return;

    try {
      await _channel.invokeMethod('castPlay', {'playerId': playerId});
    } catch (e) {
      debugPrint('CastService: Failed to play: $e');
    }
  }

  Future<void> pause(String playerId) async {
    if (!_currentStatus.isCasting) return;

    try {
      await _channel.invokeMethod('castPause', {'playerId': playerId});
    } catch (e) {
      debugPrint('CastService: Failed to pause: $e');
    }
  }

  Future<void> seekTo(Duration position, String playerId) async {
    if (!_currentStatus.isCasting) return;

    try {
      await _channel.invokeMethod('castSeekTo', {
        'playerId': playerId,
        'position': position.inMilliseconds,
      });
    } catch (e) {
      debugPrint('CastService: Failed to seek: $e');
    }
  }

  Future<void> setVolume(double volume, String playerId) async {
    if (!_currentStatus.isCasting) return;

    try {
      await _channel.invokeMethod('castSetVolume', {
        'playerId': playerId,
        'volume': volume,
      });
    } catch (e) {
      debugPrint('CastService: Failed to set volume: $e');
    }
  }

  /// Update cast status and notify listeners
  void _updateStatus(CastStatus newStatus) {
    _currentStatus = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  /// Dispose the service
  void dispose() {
    _devicesSubscription?.cancel();
    _statusSubscription?.cancel();
    _devicesController.close();
    _statusController.close();
  }
}

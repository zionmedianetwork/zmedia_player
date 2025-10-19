import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/cast_device.dart';
import '../models/media_item.dart';

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
  Future<void> initialize(String playerId) async {
    if (!_config.enabled) {
      debugPrint('CastService: Casting is disabled');
      return;
    }

    try {
      await _channel.invokeMethod('initializeCast', {
        'playerId': playerId,
        'config': _config.toMap(),
      });

      // Setup method call handler for cast events
      _channel.setMethodCallHandler(_handleMethodCall);

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

  /// Handle method calls from platform
  Future<void> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onCastDevicesChanged':
          _handleDevicesChanged(call.arguments);
          break;
        case 'onCastStatusChanged':
          _handleStatusChanged(call.arguments);
          break;
        default:
          debugPrint('CastService: Unhandled method call: ${call.method}');
      }
    } catch (e) {
      debugPrint('CastService: Error handling method call: $e');
    }
  }

  /// Handle cast devices list update
  void _handleDevicesChanged(dynamic arguments) {
    try {
      final devicesData = arguments['devices'] as List<dynamic>;
      _availableDevices = devicesData
          .map((data) => CastDevice.fromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_devicesController.isClosed) {
        _devicesController.add(_availableDevices);
      }

      debugPrint('CastService: Found ${_availableDevices.length} devices');
    } catch (e) {
      debugPrint('CastService: Error processing devices: $e');
    }
  }

  /// Handle cast status update
  void _handleStatusChanged(dynamic arguments) {
    try {
      final statusMap = Map<String, dynamic>.from(arguments);
      final newStatus = CastStatus.fromMap(statusMap);
      _updateStatus(newStatus);

      debugPrint('CastService: Status changed to ${newStatus.state}');
    } catch (e) {
      debugPrint('CastService: Error processing status: $e');
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
    _devicesController.close();
    _statusController.close();
  }
}

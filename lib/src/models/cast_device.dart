/// Represents a cast device (Chromecast, AirPlay, etc.)
class CastDevice {
  /// Unique device ID
  final String id;

  /// Device name
  final String name;

  /// Device type
  final CastDeviceType type;

  /// Device model
  final String? model;

  /// Device manufacturer
  final String? manufacturer;

  /// Device capabilities
  final List<String> capabilities;

  /// Whether device is currently connected
  final bool isConnected;

  /// Signal strength (0.0 to 1.0)
  final double? signalStrength;

  const CastDevice({
    required this.id,
    required this.name,
    required this.type,
    this.model,
    this.manufacturer,
    this.capabilities = const [],
    this.isConnected = false,
    this.signalStrength,
  });

  CastDevice copyWith({
    String? id,
    String? name,
    CastDeviceType? type,
    String? model,
    String? manufacturer,
    List<String>? capabilities,
    bool? isConnected,
    double? signalStrength,
  }) {
    return CastDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      capabilities: capabilities ?? this.capabilities,
      isConnected: isConnected ?? this.isConnected,
      signalStrength: signalStrength ?? this.signalStrength,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'model': model,
      'manufacturer': manufacturer,
      'capabilities': capabilities,
      'isConnected': isConnected,
      'signalStrength': signalStrength,
    };
  }

  factory CastDevice.fromMap(Map<String, dynamic> map) {
    return CastDevice(
      id: map['id'] as String,
      name: map['name'] as String,
      type: CastDeviceType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => CastDeviceType.unknown,
      ),
      model: map['model'] as String?,
      manufacturer: map['manufacturer'] as String?,
      capabilities: (map['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isConnected: map['isConnected'] as bool? ?? false,
      signalStrength: (map['signalStrength'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CastDevice && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CastDevice(id: $id, name: $name, type: $type)';
}

/// Type of cast device
enum CastDeviceType {
  /// Google Chromecast
  chromecast,

  /// Apple AirPlay
  airplay,

  /// Unknown/other device
  unknown,
}

/// Cast connection state
enum CastState {
  /// Not connected to any device
  disconnected,

  /// Searching for devices
  discovering,

  /// Connecting to a device
  connecting,

  /// Successfully connected
  connected,

  /// Media is actively casting/playing
  casting,

  /// Connection failed or error occurred
  failed,

  /// Error state (alias concept - use failed in code)
  error,

  /// Disconnecting from device
  disconnecting,
}

/// Cast session status
class CastStatus {
  /// Current cast state
  final CastState state;

  /// Connected device (if any)
  final CastDevice? device;

  /// Whether casting is available
  final bool isAvailable;

  /// Whether currently casting
  final bool isCasting;

  /// Current media position on cast device
  final Duration? position;

  /// Error message if any
  final String? errorMessage;

  const CastStatus({
    required this.state,
    this.device,
    this.isAvailable = false,
    this.isCasting = false,
    this.position,
    this.errorMessage,
  });

  /// Convenience getter for connected device (alias for device)
  CastDevice? get connectedDevice => device;

  CastStatus copyWith({
    CastState? state,
    CastDevice? device,
    bool? isAvailable,
    bool? isCasting,
    Duration? position,
    String? errorMessage,
  }) {
    return CastStatus(
      state: state ?? this.state,
      device: device ?? this.device,
      isAvailable: isAvailable ?? this.isAvailable,
      isCasting: isCasting ?? this.isCasting,
      position: position ?? this.position,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory CastStatus.fromMap(Map<String, dynamic> map) {
    return CastStatus(
      state: CastState.values.firstWhere(
        (s) => s.name == map['state'],
        orElse: () => CastState.disconnected,
      ),
      device: map['device'] != null
          ? CastDevice.fromMap(Map<String, dynamic>.from(map['device']))
          : null,
      isAvailable: map['isAvailable'] as bool? ?? false,
      isCasting: map['isCasting'] as bool? ?? false,
      position: map['position'] != null
          ? Duration(milliseconds: map['position'] as int)
          : null,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'state': state.name,
      'device': device?.toMap(),
      'isAvailable': isAvailable,
      'isCasting': isCasting,
      'position': position?.inMilliseconds,
      'errorMessage': errorMessage,
    };
  }
}

/// Configuration for cast/screencast
///
/// This config is forwarded verbatim to the native `initializeCast` channel
/// call (see [MediaPlayer]'s internal `_ensureCastInitialized`), where
/// [CastHandler] (Android) and [AirPlayHandler] (iOS) each read the fields
/// relevant to their platform. Fields with no honest native implementation
/// have been deliberately removed rather than left as silent no-ops — see
/// the removal of `enableDlna` (no DLNA support anywhere in this package)
/// and `autoConnect` (would require persisting a last-used-device identifier
/// and reacting to discovery results; no such mechanism exists yet).
class CastConfig {
  /// Whether casting is enabled
  final bool enabled;

  /// Enable Chromecast
  final bool enableChromecast;

  /// Enable AirPlay
  final bool enableAirPlay;

  /// Chromecast receiver app ID. Falls back to Google's Default Media
  /// Receiver (`CC1AD845`) on Android when unset. Meaningless for AirPlay.
  final String? chromecastAppId;

  /// Discovery timeout in seconds. Honoured on Android's Chromecast
  /// discovery path.
  final int discoveryTimeout;

  /// Whether to show cast button in controls
  final bool showCastButton;

  const CastConfig({
    this.enabled = true,
    this.enableChromecast = true,
    this.enableAirPlay = true,
    this.chromecastAppId,
    this.discoveryTimeout = 10,
    this.showCastButton = true,
  });

  CastConfig copyWith({
    bool? enabled,
    bool? enableChromecast,
    bool? enableAirPlay,
    String? chromecastAppId,
    int? discoveryTimeout,
    bool? showCastButton,
  }) {
    return CastConfig(
      enabled: enabled ?? this.enabled,
      enableChromecast: enableChromecast ?? this.enableChromecast,
      enableAirPlay: enableAirPlay ?? this.enableAirPlay,
      chromecastAppId: chromecastAppId ?? this.chromecastAppId,
      discoveryTimeout: discoveryTimeout ?? this.discoveryTimeout,
      showCastButton: showCastButton ?? this.showCastButton,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'enableChromecast': enableChromecast,
      'enableAirPlay': enableAirPlay,
      'chromecastAppId': chromecastAppId,
      'discoveryTimeout': discoveryTimeout,
      'showCastButton': showCastButton,
    };
  }
}

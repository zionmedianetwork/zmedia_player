/// Network status and quality monitoring
///
/// Provides real-time network quality assessment based on bandwidth
/// measurements and connection state. Used for adaptive streaming
/// and network-aware buffering decisions.
library;

/// Network quality levels based on bandwidth
enum NetworkQuality {
  /// Excellent network (> 5 Mbps)
  excellent,

  /// Good network (1-5 Mbps)
  good,

  /// Fair network (500 Kbps - 1 Mbps)
  fair,

  /// Poor network (< 500 Kbps)
  poor,

  /// Offline or no connection
  offline,

  /// Unknown network quality
  unknown;

  /// Gets network quality from bandwidth in bytes per second
  static NetworkQuality fromBandwidth(int bytesPerSecond) {
    // Convert bytes/sec to Mbps
    final mbps = (bytesPerSecond * 8) / 1000000;

    if (mbps > 5) return NetworkQuality.excellent;
    if (mbps > 1) return NetworkQuality.good;
    if (mbps > 0.5) return NetworkQuality.fair;
    if (mbps > 0) return NetworkQuality.poor;
    return NetworkQuality.offline;
  }

  /// Checks if network is available
  bool get isAvailable => this != NetworkQuality.offline;

  /// Checks if quality is adequate for streaming
  bool get canStream =>
      this != NetworkQuality.offline && this != NetworkQuality.poor;

  /// Gets minimum bitrate recommendation for this quality (in bps)
  int get recommendedMinBitrate {
    switch (this) {
      case NetworkQuality.excellent:
        return 5000000; // 5 Mbps
      case NetworkQuality.good:
        return 1000000; // 1 Mbps
      case NetworkQuality.fair:
        return 500000; // 500 Kbps
      case NetworkQuality.poor:
        return 250000; // 250 Kbps
      case NetworkQuality.offline:
      case NetworkQuality.unknown:
        return 0;
    }
  }

  /// Gets maximum bitrate recommendation for this quality (in bps)
  int get recommendedMaxBitrate {
    switch (this) {
      case NetworkQuality.excellent:
        return 20000000; // 20 Mbps
      case NetworkQuality.good:
        return 5000000; // 5 Mbps
      case NetworkQuality.fair:
        return 1000000; // 1 Mbps
      case NetworkQuality.poor:
        return 500000; // 500 Kbps
      case NetworkQuality.offline:
      case NetworkQuality.unknown:
        return 0;
    }
  }
}

/// Current network connection status
class NetworkStatus {
  /// Network quality level
  final NetworkQuality quality;

  /// Download speed in bytes per second
  final int downloadSpeed;

  /// Upload speed in bytes per second (if available)
  final int? uploadSpeed;

  /// Whether connection is metered (cellular data)
  final bool isMetered;

  /// Connection type (wifi, cellular, ethernet, etc.)
  final ConnectionType connectionType;

  /// Signal strength (0.0 - 1.0, if available)
  final double? signalStrength;

  /// Timestamp when status was measured
  final DateTime timestamp;

  /// Round-trip time (ping) in milliseconds
  final int? rtt;

  const NetworkStatus({
    required this.quality,
    required this.downloadSpeed,
    this.uploadSpeed,
    required this.isMetered,
    required this.connectionType,
    this.signalStrength,
    required this.timestamp,
    this.rtt,
  });

  /// Creates NetworkStatus from platform data
  factory NetworkStatus.fromPlatform(Map<String, dynamic> data) {
    final downloadSpeed = data['downloadSpeed'] as int? ?? 0;
    final quality = NetworkQuality.fromBandwidth(downloadSpeed);

    return NetworkStatus(
      quality: quality,
      downloadSpeed: downloadSpeed,
      uploadSpeed: data['uploadSpeed'] as int?,
      isMetered: data['isMetered'] as bool? ?? false,
      connectionType: ConnectionType.fromString(
        data['connectionType'] as String? ?? 'unknown',
      ),
      signalStrength: (data['signalStrength'] as num?)?.toDouble(),
      timestamp: DateTime.now(),
      rtt: data['rtt'] as int?,
    );
  }

  /// Creates an offline status
  factory NetworkStatus.offline() {
    return NetworkStatus(
      quality: NetworkQuality.offline,
      downloadSpeed: 0,
      isMetered: false,
      connectionType: ConnectionType.none,
      timestamp: DateTime.now(),
    );
  }

  /// Creates an unknown status
  factory NetworkStatus.unknown() {
    return NetworkStatus(
      quality: NetworkQuality.unknown,
      downloadSpeed: 0,
      isMetered: false,
      connectionType: ConnectionType.unknown,
      timestamp: DateTime.now(),
    );
  }

  /// Checks if network is available
  bool get isAvailable => quality.isAvailable;

  /// Checks if suitable for streaming
  bool get canStream => quality.canStream;

  /// Gets human-readable description
  String get description {
    if (!isAvailable) return 'No connection';

    final speedMbps = (downloadSpeed * 8) / 1000000;
    final metered = isMetered ? ' (metered)' : '';

    return '${quality.name.toUpperCase()}: ${speedMbps.toStringAsFixed(1)} Mbps$metered';
  }

  /// Converts to map for platform communication
  Map<String, dynamic> toMap() {
    return {
      'quality': quality.name,
      'downloadSpeed': downloadSpeed,
      'uploadSpeed': uploadSpeed,
      'isMetered': isMetered,
      'connectionType': connectionType.name,
      'signalStrength': signalStrength,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'rtt': rtt,
    };
  }

  @override
  String toString() => 'NetworkStatus($description)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkStatus &&
          runtimeType == other.runtimeType &&
          quality == other.quality &&
          downloadSpeed == other.downloadSpeed &&
          isMetered == other.isMetered &&
          connectionType == other.connectionType;

  @override
  int get hashCode =>
      quality.hashCode ^
      downloadSpeed.hashCode ^
      isMetered.hashCode ^
      connectionType.hashCode;

  /// Creates a copy with updated fields
  NetworkStatus copyWith({
    NetworkQuality? quality,
    int? downloadSpeed,
    int? uploadSpeed,
    bool? isMetered,
    ConnectionType? connectionType,
    double? signalStrength,
    DateTime? timestamp,
    int? rtt,
  }) {
    return NetworkStatus(
      quality: quality ?? this.quality,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      isMetered: isMetered ?? this.isMetered,
      connectionType: connectionType ?? this.connectionType,
      signalStrength: signalStrength ?? this.signalStrength,
      timestamp: timestamp ?? this.timestamp,
      rtt: rtt ?? this.rtt,
    );
  }
}

/// Type of network connection
enum ConnectionType {
  /// WiFi connection
  wifi,

  /// Cellular/mobile data
  cellular,

  /// Ethernet connection
  ethernet,

  /// Bluetooth connection
  bluetooth,

  /// VPN connection
  vpn,

  /// No connection
  none,

  /// Unknown connection type
  unknown;

  /// Creates from string identifier
  static ConnectionType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'wifi':
        return ConnectionType.wifi;
      case 'cellular':
      case 'mobile':
        return ConnectionType.cellular;
      case 'ethernet':
        return ConnectionType.ethernet;
      case 'bluetooth':
        return ConnectionType.bluetooth;
      case 'vpn':
        return ConnectionType.vpn;
      case 'none':
        return ConnectionType.none;
      default:
        return ConnectionType.unknown;
    }
  }

  /// Checks if connection is typically metered
  bool get isTypicallyMetered {
    return this == ConnectionType.cellular || this == ConnectionType.bluetooth;
  }
}

/// Network change event
class NetworkChangeEvent {
  /// Previous network status
  final NetworkStatus? previousStatus;

  /// Current network status
  final NetworkStatus currentStatus;

  /// Whether connection was lost
  final bool connectionLost;

  /// Whether connection was restored
  final bool connectionRestored;

  /// Whether quality improved
  final bool qualityImproved;

  /// Whether quality degraded
  final bool qualityDegraded;

  NetworkChangeEvent({
    this.previousStatus,
    required this.currentStatus,
  })  : connectionLost =
            previousStatus?.isAvailable == true && !currentStatus.isAvailable,
        connectionRestored =
            previousStatus?.isAvailable == false && currentStatus.isAvailable,
        qualityImproved = previousStatus != null &&
            currentStatus.quality.index > previousStatus.quality.index,
        qualityDegraded = previousStatus != null &&
            currentStatus.quality.index < previousStatus.quality.index;

  /// Checks if this is a significant change requiring action
  bool get isSignificant {
    return connectionLost ||
        connectionRestored ||
        qualityImproved ||
        qualityDegraded;
  }

  @override
  String toString() {
    if (connectionLost) return 'Network connection lost';
    if (connectionRestored) return 'Network connection restored';
    if (qualityImproved) {
      return 'Network quality improved: ${previousStatus?.quality.name} -> ${currentStatus.quality.name}';
    }
    if (qualityDegraded) {
      return 'Network quality degraded: ${previousStatus?.quality.name} -> ${currentStatus.quality.name}';
    }
    return 'Network status: ${currentStatus.description}';
  }
}

import 'package:flutter/material.dart';
import '../../models/network_status.dart';

/// Network quality indicator with signal strength and connection type
///
/// Displays:
/// - Real-time network quality badge
/// - Signal strength bars
/// - Connection type icon (WiFi, 4G, 5G, etc.)
/// - Bandwidth estimation display
///
/// Example usage:
/// ```dart
/// NetworkQualityIndicator(
///   networkStatus: networkStatus,
///   showDetails: true,
/// )
/// ```
class NetworkQualityIndicator extends StatelessWidget {
  /// Current network status
  final NetworkStatus networkStatus;

  /// Whether to show detailed information
  final bool showDetails;

  /// Size of the indicator
  final double size;

  /// Layout orientation
  final Axis orientation;

  const NetworkQualityIndicator({
    super.key,
    required this.networkStatus,
    this.showDetails = true,
    this.size = 24.0,
    this.orientation = Axis.horizontal,
  });

  Color _getQualityColor() {
    switch (networkStatus.quality) {
      case NetworkQuality.excellent:
        return const Color(0xFF4CAF50); // Green
      case NetworkQuality.good:
        return const Color(0xFF8BC34A); // Light green
      case NetworkQuality.fair:
        return const Color(0xFFFFC107); // Amber
      case NetworkQuality.poor:
        return const Color(0xFFFF9800); // Orange
      case NetworkQuality.offline:
        return const Color(0xFF9E9E9E); // Gray
      case NetworkQuality.unknown:
        return const Color(0xFF9E9E9E); // Gray
    }
  }

  IconData _getConnectionTypeIcon() {
    switch (networkStatus.connectionType) {
      case ConnectionType.wifi:
        return Icons.wifi;
      case ConnectionType.cellular:
        return Icons.signal_cellular_alt;
      case ConnectionType.ethernet:
        return Icons.settings_ethernet;
      case ConnectionType.bluetooth:
        return Icons.bluetooth;
      case ConnectionType.vpn:
        return Icons.vpn_key;
      case ConnectionType.none:
        return Icons.signal_wifi_off;
      case ConnectionType.unknown:
        return Icons.network_check;
    }
  }

  String _getQualityLabel() {
    switch (networkStatus.quality) {
      case NetworkQuality.excellent:
        return 'Excellent';
      case NetworkQuality.good:
        return 'Good';
      case NetworkQuality.fair:
        return 'Fair';
      case NetworkQuality.poor:
        return 'Poor';
      case NetworkQuality.offline:
        return 'Offline';
      case NetworkQuality.unknown:
        return 'Unknown';
    }
  }

  String _getBandwidthText() {
    final mbps = (networkStatus.downloadSpeed * 8) / 1000000;
    if (mbps >= 1) {
      return '${mbps.toStringAsFixed(1)} Mbps';
    }
    final kbps = (networkStatus.downloadSpeed * 8) / 1000;
    return '${kbps.toStringAsFixed(0)} Kbps';
  }

  @override
  Widget build(BuildContext context) {
    if (orientation == Axis.vertical) {
      return _buildVerticalLayout();
    }
    return _buildHorizontalLayout();
  }

  Widget _buildHorizontalLayout() {
    final qualityColor = _getQualityColor();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Connection type icon
        Icon(
          _getConnectionTypeIcon(),
          color: qualityColor,
          size: size,
        ),

        const SizedBox(width: 8),

        // Signal strength bars
        _SignalStrengthBars(
          strength: networkStatus.signalStrength ?? _estimateSignalStrength(),
          color: qualityColor,
          size: size,
        ),

        if (showDetails) ...[
          const SizedBox(width: 12),

          // Quality and bandwidth
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getQualityLabel(),
                style: TextStyle(
                  color: qualityColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (networkStatus.downloadSpeed > 0)
                Text(
                  _getBandwidthText(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildVerticalLayout() {
    final qualityColor = _getQualityColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Connection type icon
        Icon(
          _getConnectionTypeIcon(),
          color: qualityColor,
          size: size,
        ),

        const SizedBox(height: 4),

        // Signal strength bars
        _SignalStrengthBars(
          strength: networkStatus.signalStrength ?? _estimateSignalStrength(),
          color: qualityColor,
          size: size * 0.6,
        ),

        if (showDetails) ...[
          const SizedBox(height: 8),

          // Quality label
          Text(
            _getQualityLabel(),
            style: TextStyle(
              color: qualityColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Bandwidth
          if (networkStatus.downloadSpeed > 0)
            Text(
              _getBandwidthText(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
              ),
            ),
        ],
      ],
    );
  }

  /// Estimate signal strength from network quality when not provided
  double _estimateSignalStrength() {
    switch (networkStatus.quality) {
      case NetworkQuality.excellent:
        return 1.0;
      case NetworkQuality.good:
        return 0.75;
      case NetworkQuality.fair:
        return 0.5;
      case NetworkQuality.poor:
        return 0.25;
      case NetworkQuality.offline:
      case NetworkQuality.unknown:
        return 0.0;
    }
  }
}

/// Signal strength bars widget
class _SignalStrengthBars extends StatelessWidget {
  /// Signal strength (0.0 - 1.0)
  final double strength;

  /// Color of the bars
  final Color color;

  /// Size of the bars
  final double size;

  const _SignalStrengthBars({
    required this.strength,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    const barCount = 4;
    final activeBars = (strength * barCount).ceil();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(barCount, (index) {
        final isActive = index < activeBars;
        final barHeight = size * (0.4 + (index * 0.2));

        return Container(
          width: size * 0.2,
          height: barHeight,
          margin: EdgeInsets.only(left: index > 0 ? 2 : 0),
          decoration: BoxDecoration(
            color: isActive ? color : color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

/// Compact network quality badge
class CompactNetworkQualityBadge extends StatelessWidget {
  /// Current network status
  final NetworkStatus networkStatus;

  /// Size of the badge
  final double size;

  const CompactNetworkQualityBadge({
    super.key,
    required this.networkStatus,
    this.size = 16.0,
  });

  Color _getQualityColor() {
    switch (networkStatus.quality) {
      case NetworkQuality.excellent:
        return const Color(0xFF4CAF50);
      case NetworkQuality.good:
        return const Color(0xFF8BC34A);
      case NetworkQuality.fair:
        return const Color(0xFFFFC107);
      case NetworkQuality.poor:
        return const Color(0xFFFF9800);
      case NetworkQuality.offline:
      case NetworkQuality.unknown:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _getConnectionTypeIcon() {
    switch (networkStatus.connectionType) {
      case ConnectionType.wifi:
        return Icons.wifi;
      case ConnectionType.cellular:
        return Icons.signal_cellular_alt;
      case ConnectionType.ethernet:
        return Icons.settings_ethernet;
      case ConnectionType.bluetooth:
        return Icons.bluetooth;
      case ConnectionType.vpn:
        return Icons.vpn_key;
      case ConnectionType.none:
        return Icons.signal_wifi_off;
      case ConnectionType.unknown:
        return Icons.network_check;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: _getQualityColor().withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getQualityColor().withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getConnectionTypeIcon(),
            color: _getQualityColor(),
            size: size,
          ),
          const SizedBox(width: 4),
          Text(
            networkStatus.quality.name.toUpperCase()[0],
            style: TextStyle(
              color: _getQualityColor(),
              fontSize: size * 0.75,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Network quality indicator with tooltip
class NetworkQualityTooltip extends StatelessWidget {
  /// Current network status
  final NetworkStatus networkStatus;

  /// Child widget
  final Widget child;

  const NetworkQualityTooltip({
    super.key,
    required this.networkStatus,
    required this.child,
  });

  String _getTooltipMessage() {
    final quality = networkStatus.quality.name.toUpperCase();
    final type = networkStatus.connectionType.name;
    final mbps = (networkStatus.downloadSpeed * 8) / 1000000;
    final speed = mbps >= 1
        ? '${mbps.toStringAsFixed(1)} Mbps'
        : '${((networkStatus.downloadSpeed * 8) / 1000).toStringAsFixed(0)} Kbps';

    final buffer = StringBuffer();
    buffer.writeln('Network Quality: $quality');
    buffer.writeln('Connection: ${type[0].toUpperCase()}${type.substring(1)}');
    if (networkStatus.downloadSpeed > 0) {
      buffer.writeln('Speed: $speed');
    }
    if (networkStatus.isMetered) {
      buffer.write('⚠️ Metered connection');
    }

    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _getTooltipMessage(),
      child: child,
    );
  }
}

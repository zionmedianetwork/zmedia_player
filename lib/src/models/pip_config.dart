/// Configuration for Picture-in-Picture mode
class PipConfig {
  /// Whether PiP is enabled
  final bool enabled;

  /// Aspect ratio for PiP window (width / height)
  final double aspectRatio;

  /// Whether to automatically enter PiP when app goes to background
  final bool autoEnterOnBackground;

  /// Custom actions to show in PiP mode
  final List<PipAction> actions;

  /// Whether to show playback controls in PiP
  final bool showPlaybackControls;

  const PipConfig({
    this.enabled = true,
    this.aspectRatio = 16 / 9,
    this.autoEnterOnBackground = false,
    this.actions = const [],
    this.showPlaybackControls = true,
  });

  PipConfig copyWith({
    bool? enabled,
    double? aspectRatio,
    bool? autoEnterOnBackground,
    List<PipAction>? actions,
    bool? showPlaybackControls,
  }) {
    return PipConfig(
      enabled: enabled ?? this.enabled,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      autoEnterOnBackground:
          autoEnterOnBackground ?? this.autoEnterOnBackground,
      actions: actions ?? this.actions,
      showPlaybackControls: showPlaybackControls ?? this.showPlaybackControls,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'aspectRatio': aspectRatio,
      'autoEnterOnBackground': autoEnterOnBackground,
      'actions': actions.map((a) => a.toMap()).toList(),
      'showPlaybackControls': showPlaybackControls,
    };
  }
}

/// Custom PiP action
class PipAction {
  /// Unique action ID
  final String id;

  /// Action title
  final String title;

  /// Icon resource name
  final String? icon;

  const PipAction({
    required this.id,
    required this.title,
    this.icon,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'icon': icon,
    };
  }

  factory PipAction.fromMap(Map<String, dynamic> map) {
    return PipAction(
      id: map['id'] as String,
      title: map['title'] as String,
      icon: map['icon'] as String?,
    );
  }
}

/// Picture-in-Picture state
enum PipState {
  /// PiP is not available on this device
  unavailable,

  /// PiP is available but not active
  available,

  /// Currently in PiP mode
  active,

  /// Exiting PiP mode
  exiting,
}

/// PiP status information
class PipStatus {
  /// Current PiP state
  final PipState state;

  /// Whether PiP is supported on this device
  final bool isSupported;

  /// Whether currently in PiP mode
  final bool isActive;

  /// Error message if any
  final String? errorMessage;

  const PipStatus({
    required this.state,
    required this.isSupported,
    required this.isActive,
    this.errorMessage,
  });

  PipStatus copyWith({
    PipState? state,
    bool? isSupported,
    bool? isActive,
    String? errorMessage,
  }) {
    return PipStatus(
      state: state ?? this.state,
      isSupported: isSupported ?? this.isSupported,
      isActive: isActive ?? this.isActive,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory PipStatus.fromMap(Map<String, dynamic> map) {
    return PipStatus(
      state: PipState.values.firstWhere(
        (s) => s.name == map['state'],
        orElse: () => PipState.unavailable,
      ),
      isSupported: map['isSupported'] as bool? ?? false,
      isActive: map['isActive'] as bool? ?? false,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'state': state.name,
      'isSupported': isSupported,
      'isActive': isActive,
      'errorMessage': errorMessage,
    };
  }
}

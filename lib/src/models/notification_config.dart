/// Configuration for media notifications
class NotificationConfig {
  /// Whether to show media notifications
  final bool enabled;

  /// Notification channel ID (Android)
  final String channelId;

  /// Notification channel name (Android)
  final String channelName;

  /// Notification channel description (Android)
  final String? channelDescription;

  /// Show play/pause action
  final bool showPlayPause;

  /// Show next action
  final bool showNext;

  /// Show previous action
  final bool showPrevious;

  /// Show stop action
  final bool showStop;

  /// Show seek forward action
  final bool showSeekForward;

  /// Show seek backward action
  final bool showSeekBackward;

  /// Seek forward/backward interval in seconds
  final int seekInterval;

  /// Whether to show notification when paused
  final bool showWhenPaused;

  /// Custom actions to add to notification
  final List<NotificationAction> customActions;

  /// Priority for the notification (Android)
  final NotificationPriority priority;

  /// Small icon resource name (Android)
  final String? smallIcon;

  /// Whether notification is dismissible
  final bool dismissible;

  const NotificationConfig({
    this.enabled = true,
    this.channelId = 'media_playback',
    this.channelName = 'Media Playback',
    this.channelDescription,
    this.showPlayPause = true,
    this.showNext = true,
    this.showPrevious = true,
    this.showStop = false,
    this.showSeekForward = false,
    this.showSeekBackward = false,
    this.seekInterval = 10,
    this.showWhenPaused = true,
    this.customActions = const [],
    this.priority = NotificationPriority.high,
    this.smallIcon,
    this.dismissible = false,
  });

  NotificationConfig copyWith({
    bool? enabled,
    String? channelId,
    String? channelName,
    String? channelDescription,
    bool? showPlayPause,
    bool? showNext,
    bool? showPrevious,
    bool? showStop,
    bool? showSeekForward,
    bool? showSeekBackward,
    int? seekInterval,
    bool? showWhenPaused,
    List<NotificationAction>? customActions,
    NotificationPriority? priority,
    String? smallIcon,
    bool? dismissible,
  }) {
    return NotificationConfig(
      enabled: enabled ?? this.enabled,
      channelId: channelId ?? this.channelId,
      channelName: channelName ?? this.channelName,
      channelDescription: channelDescription ?? this.channelDescription,
      showPlayPause: showPlayPause ?? this.showPlayPause,
      showNext: showNext ?? this.showNext,
      showPrevious: showPrevious ?? this.showPrevious,
      showStop: showStop ?? this.showStop,
      showSeekForward: showSeekForward ?? this.showSeekForward,
      showSeekBackward: showSeekBackward ?? this.showSeekBackward,
      seekInterval: seekInterval ?? this.seekInterval,
      showWhenPaused: showWhenPaused ?? this.showWhenPaused,
      customActions: customActions ?? this.customActions,
      priority: priority ?? this.priority,
      smallIcon: smallIcon ?? this.smallIcon,
      dismissible: dismissible ?? this.dismissible,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'channelId': channelId,
      'channelName': channelName,
      'channelDescription': channelDescription,
      'showPlayPause': showPlayPause,
      'showNext': showNext,
      'showPrevious': showPrevious,
      'showStop': showStop,
      'showSeekForward': showSeekForward,
      'showSeekBackward': showSeekBackward,
      'seekInterval': seekInterval,
      'showWhenPaused': showWhenPaused,
      'customActions': customActions.map((a) => a.toMap()).toList(),
      'priority': priority.name,
      'smallIcon': smallIcon,
      'dismissible': dismissible,
    };
  }
}

/// Custom notification action
class NotificationAction {
  /// Unique action ID
  final String id;

  /// Display title
  final String title;

  /// Icon resource name
  final String? icon;

  const NotificationAction({
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

  factory NotificationAction.fromMap(Map<String, dynamic> map) {
    return NotificationAction(
      id: map['id'] as String,
      title: map['title'] as String,
      icon: map['icon'] as String?,
    );
  }
}

/// Notification priority levels
enum NotificationPriority {
  /// Minimum priority (no sound, no heads-up)
  min,

  /// Low priority (no sound, no heads-up)
  low,

  /// Default priority
  defaultPriority,

  /// High priority (sound, may show heads-up)
  high,

  /// Maximum priority (sound, heads-up)
  max,
}

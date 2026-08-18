/// Event describing a tap on a custom Picture-in-Picture action.
///
/// **Android only.** See `PipConfig.actions` (`lib/src/models/pip_config.dart`)
/// for how these actions are declared and rendered as `RemoteAction`s in the
/// system PiP window. Tapping one broadcasts to a native receiver, which
/// invokes the `onPipAction` method-channel call with
/// `{"playerId": ..., "actionId": ...}` — this class parses that payload.
/// iOS never sends this event: `AVPictureInPictureController`'s overlay is
/// entirely system-owned and AVKit exposes no API for custom action buttons.
///
/// Delivered via [MediaPlayer.pipActionStream]. Mirrors, in spirit,
/// [NotificationActionEvent] (`lib/src/models/notification_config.dart`) —
/// the same "native broadcasts an action id, Dart surfaces it as a typed
/// stream event" shape.
class PipActionEvent {
  /// The [PipAction.id] of the action that was tapped.
  final String actionId;

  const PipActionEvent(this.actionId);

  /// Parses the raw arguments map delivered by the platform's `onPipAction`
  /// method channel call (`{"playerId", "actionId"}`).
  factory PipActionEvent.fromMap(Map<dynamic, dynamic> map) {
    return PipActionEvent(map['actionId'] as String);
  }

  @override
  String toString() => 'PipActionEvent(actionId: $actionId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PipActionEvent && other.actionId == actionId);

  @override
  int get hashCode => actionId.hashCode;
}

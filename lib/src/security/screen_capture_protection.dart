/// Screen-capture / screen-recording protection (B-12).
///
/// Opt-in (default OFF) API for content that must not be freely
/// screenshotted or screen-recorded, e.g. DRM-protected premium video.
///
/// **This is intentionally asymmetric across platforms — read carefully
/// before relying on it:**
///
///  - **Android** maps [MediaPlayer.setSecureSurface] to `FLAG_SECURE` on
///    the host `Activity`'s window. This is a hard OS-level *block*:
///    screenshots of the window come back black, the window is excluded
///    from the recent-apps thumbnail, and screen recording / casting APIs
///    cannot capture its contents. There is nothing to detect on Android —
///    a blocked capture never produces any content — so
///    [MediaPlayer.screenCaptureStream] never emits there.
///  - **iOS** has no OS-level API to block screen recording or AirPlay
///    mirroring of arbitrary app content the way `FLAG_SECURE` does (Apple
///    only allows this for a small set of system-owned surfaces, e.g.
///    passwords/payment sheets). [MediaPlayer.setSecureSurface] on iOS is
///    therefore **detection-only**: it observes `UIScreen.isCaptured`
///    (backed by `UIScreen.capturedDidChangeNotification`) and reports
///    changes via [MediaPlayer.screenCaptureStream]. The host app is
///    responsible for reacting — e.g. blanking the video surface or
///    showing a warning overlay — for as long as [isCaptured] is `true`.
///
/// Do not assume iOS content is protected merely because
/// `setSecureSurface(true)` was called; on iOS it only tells you *that*
/// capture is happening, not prevent it.
library;

/// Screen-capture status for a player's video surface, reported via
/// [MediaPlayer.screenCaptureStream] after [MediaPlayer.setSecureSurface]
/// has been enabled.
///
/// See the library-level documentation in this file for the full
/// Android/iOS asymmetry this type is part of.
class ScreenCaptureStatus {
  /// Creates a screen-capture status snapshot.
  const ScreenCaptureStatus({required this.isCaptured});

  /// Whether the screen is currently believed to be captured
  /// (screen-recorded, AirPlay/screen-mirrored, etc.).
  ///
  /// Always `false` on Android: `FLAG_SECURE` prevents the capture from
  /// producing any content in the first place, so there is nothing to
  /// report. On iOS this reflects the live value of `UIScreen.isCaptured`
  /// at the time of the most recent `UIScreen.capturedDidChangeNotification`
  /// (or the value queried immediately when monitoring was enabled).
  final bool isCaptured;

  /// Parses a [ScreenCaptureStatus] from the native MethodChannel payload.
  factory ScreenCaptureStatus.fromMap(Map<String, dynamic> map) {
    return ScreenCaptureStatus(
      isCaptured: map['isCaptured'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScreenCaptureStatus && other.isCaptured == isCaptured;
  }

  @override
  int get hashCode => isCaptured.hashCode;

  @override
  String toString() => 'ScreenCaptureStatus(isCaptured: $isCaptured)';
}

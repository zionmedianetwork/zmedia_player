import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, MissingPluginException, PlatformException;
import '../models/media_item.dart';
import '../models/player_state.dart';
import '../models/playlist.dart';
import '../models/subtitle_track.dart';
import '../models/streaming_config.dart';
import '../models/pip_config.dart';
import '../models/pip_action_event.dart';
import '../models/cast_device.dart';
import '../models/drm_config.dart';
import '../models/buffering_config.dart';
import '../models/buffer_health.dart';
import '../models/network_status.dart';
import '../models/notification_config.dart';
import '../services/buffering_service.dart';
import '../services/network_resilience_service.dart';
import '../security/input_validation.dart';
import '../security/screen_capture_protection.dart';
import 'media_config.dart';
import 'crash_reporter.dart';
import 'exceptions.dart';

/// Reason a `paused` [PlaybackState] transition happened, when known.
///
/// H-01: [PlaybackState] itself carries no field for this (it lives in
/// `lib/src/models/`, outside this fix's scope), so the reason is surfaced
/// out-of-band via [MediaPlayer.pauseReasonStream] instead of changing the
/// state string itself. This mirrors, in spirit, how Phase 2 disambiguated
/// stall-vs-pause on iOS by choosing between the `buffering` and `paused`
/// state strings — here both "user paused" and "OS revoked audio focus" are
/// legitimately `paused`, so the disambiguation has to travel alongside the
/// state event rather than replace it.
enum PlayerPauseReason {
  /// A normal user- or API-driven pause (or any other/unknown cause).
  user,

  /// Android only, currently: the OS paused playback by revoking audio
  /// focus (e.g. another app started playing audio). See
  /// `MediaPlayerInstance.onPlayWhenReadyChanged`/`onIsPlayingChanged` in
  /// `android/.../MediaPlayerManager.kt`.
  audioFocusLoss,
}

/// M-09: strips the query string and fragment from [url] before it is
/// handed to the crash reporter (custom keys / error context). Signed
/// cookies and auth tokens for authenticated media/license URLs commonly
/// live in the query string, and crash reports are frequently stored and
/// transmitted by a third-party service outside this app's control — so
/// the full URL must never reach it.
///
/// Deliberately does plain substring truncation at the first `?`/`#`
/// rather than round-tripping through [Uri] — `Uri.replace(query: '',
/// fragment: '')` sets an *empty* query/fragment component rather than
/// removing it, which leaves a dangling `?`/`#` in the output (and would
/// still leak the fact that query params existed, though not their
/// content). Never throws: an unparseable/malformed [url] is truncated the
/// same way, rather than being passed through unredacted.
String _redactUrlForCrashReporting(String url) {
  final queryIndex = url.indexOf('?');
  final fragmentIndex = url.indexOf('#');
  var cut = url.length;
  if (queryIndex != -1 && queryIndex < cut) cut = queryIndex;
  if (fragmentIndex != -1 && fragmentIndex < cut) cut = fragmentIndex;
  return url.substring(0, cut);
}

/// Main media player controller class
///
/// This class provides the primary interface for controlling media playbook,
/// managing playlists, and configuring player behavior.
class MediaPlayer {
  static const MethodChannel _channel = MethodChannel('zmedia_player');
  static final Map<String, MediaPlayer> _instances = {};

  /// Guard that ensures the static method call handler is registered only once.
  static bool _channelHandlerRegistered = false;

  /// Activity tracking for memory leak prevention
  static final Map<String, DateTime> _lastActivity = {};
  static Timer? _cleanupTimer;

  /// Monotonically increasing counter used to generate collision-free
  /// player ids when no explicit [playerId] is supplied to the factory.
  ///
  /// A plain millisecond timestamp is not sufficient: constructing several
  /// players within the same event-loop tick (e.g. building a `ListView` of
  /// players in one frame) can produce identical timestamps, which would
  /// silently alias two independent players onto the same native instance.
  /// The counter never resets — including after instances are disposed and
  /// swept by [_cleanupStaleInstances] — so a recycled counter value can
  /// never collide with, or resurrect, a previously-used id.
  static int _autoIdCounter = 0;

  /// Global crash reporter (set once at app startup)
  static CrashReporter? crashReporter;

  /// M-16: wire protocol version for the MethodChannel contract between
  /// this Dart package and the native (Android/Kotlin, iOS/Swift)
  /// implementations. [initialize] sends this to native; native compares it
  /// against its own NATIVE_PROTOCOL_VERSION /
  /// MIN_SUPPORTED_DART_PROTOCOL_VERSION (see `ZMediaPlayerPlugin.kt` /
  /// `ZMediaPlayerPlugin.swift`) and rejects an incompatible pairing with a
  /// `PROTOCOL_VERSION_MISMATCH` error instead of silently misbehaving or
  /// failing later with an unrelated-looking error. Bump this whenever a
  /// change to the MethodChannel contract requires native to be rebuilt to
  /// stay compatible (new required arguments, renamed methods, changed
  /// event payload shapes, etc.), and bump the native constants to match.
  static const int protocolVersion = 1;

  /// Oldest native protocol version this Dart package can still talk to.
  /// Native reports its own version back from a successful `initialize`
  /// call; if it's older than this floor, [initialize] throws
  /// [ProtocolMismatchException] rather than proceeding against native code
  /// that may not understand calls this package is about to make. A native
  /// build that predates protocol negotiation entirely reports no version
  /// at all — that case is intentionally allowed through unchanged, since
  /// there is nothing to compare it against.
  static const int minSupportedNativeProtocolVersion = 1;

  /// Unique identifier for this player instance
  final String playerId;

  /// Configuration for this player instance
  MediaConfig _config;

  /// Current playlist
  Playlist? _currentPlaylist;

  /// Current media item
  MediaItem? _currentItem;

  /// Stream controllers for state management
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<double> _speedController =
      StreamController<double>.broadcast();
  final StreamController<List<SubtitleTrack>> _subtitleTracksController =
      StreamController<List<SubtitleTrack>>.broadcast();
  final StreamController<List<QualityTrack>> _qualityTracksController =
      StreamController<List<QualityTrack>>.broadcast();
  final StreamController<List<AudioTrack>> _audioTracksController =
      StreamController<List<AudioTrack>>.broadcast();
  final StreamController<PipStatus> _pipStatusController =
      StreamController<PipStatus>.broadcast();
  final StreamController<PipActionEvent> _pipActionController =
      StreamController<PipActionEvent>.broadcast();
  final StreamController<CastStatus> _castStatusController =
      StreamController<CastStatus>.broadcast();
  final StreamController<List<CastDevice>> _castDevicesController =
      StreamController<List<CastDevice>>.broadcast();
  final StreamController<DrmSession> _drmSessionController =
      StreamController<DrmSession>.broadcast();
  final StreamController<String> _notificationActionController =
      StreamController<String>.broadcast();
  final StreamController<NotificationActionEvent>
      _notificationActionEventController =
      StreamController<NotificationActionEvent>.broadcast();
  final StreamController<int> _bandwidthController =
      StreamController<int>.broadcast();
  final StreamController<BufferHealth> _bufferHealthController =
      StreamController<BufferHealth>.broadcast();
  final StreamController<MediaPlayerException> _errorController =
      StreamController<MediaPlayerException>.broadcast();
  final StreamController<PlayerPauseReason> _pauseReasonController =
      StreamController<PlayerPauseReason>.broadcast();
  final StreamController<ScreenCaptureStatus> _screenCaptureController =
      StreamController<ScreenCaptureStatus>.broadcast();

  /// Buffering service for adaptive buffer management
  late final BufferingService _bufferingService;

  /// H-06: network resilience/retry service, fed live by native connectivity
  /// push events (`onNetworkStatusChanged` — see `_handleNetworkStatusChanged`
  /// and `NetworkMonitor` on each platform). Unlike [BufferingService], this
  /// is *not* started via a `startMonitoring()` poll: native already drives
  /// it purely by calling [NetworkResilienceService.updateNetworkStatus]
  /// whenever a connectivity event arrives, so [NetworkResilienceService]'s
  /// own `Timer.periodic`-based `startMonitoring`/`stopMonitoring` (which
  /// require a `platformNetworkStatusCallback` this constructor deliberately
  /// omits) are simply unused here.
  late final NetworkResilienceService _networkResilienceService;

  /// Current playback state
  PlaybackState _currentState = const PlaybackState(state: PlayerState.idle);

  /// Current bandwidth estimate in bits per second
  int _currentBandwidth = 0;

  /// Whether current media is live
  bool _isLive = false;

  /// Whether DVR is enabled for the current live media, allowing seeking on
  /// an otherwise non-seekable live stream.
  ///
  /// Recomputed on every [load] from whichever streaming config applies to
  /// the loaded [MediaItem.url] — `HlsConfig.enableDvr` for a `.m3u8` URL
  /// (via [MediaConfig.hlsConfig]), `DashConfig.enableDvr` for a `.mpd` URL
  /// (via [MediaConfig.dashConfig]), or `false` when neither applies (no
  /// streaming config configured, or a progressive URL). See
  /// [_applyStreamingConfigForLoad]. Every consumer of this field
  /// ([isSeekable], [seekTo], and the notification/lock-screen surface via
  /// [NotificationService]) reads it unchanged from before this wiring
  /// landed.
  bool _dvrEnabled = false;

  /// Current PiP status
  PipStatus _pipStatus = const PipStatus(
    state: PipState.unavailable,
    isSupported: false,
    isActive: false,
  );

  /// Current cast status
  CastStatus _castStatus = const CastStatus(
    state: CastState.disconnected,
    isAvailable: false,
    isCasting: false,
  );

  /// Whether opt-in screen-capture protection (B-12) is currently enabled
  /// for this player. See [setSecureSurface].
  bool _secureSurfaceEnabled = false;

  /// Most recently reported screen-capture status. Always reflects
  /// `isCaptured: false` until a native `onScreenCaptureChanged` event
  /// arrives (iOS only — see [screenCaptureStream]).
  ScreenCaptureStatus _screenCaptureStatus =
      const ScreenCaptureStatus(isCaptured: false);

  /// Available subtitle tracks
  List<SubtitleTrack> _subtitleTracks = [];

  /// Currently selected subtitle track
  SubtitleTrack? _selectedSubtitleTrack;

  /// Available quality tracks
  List<QualityTrack> _qualityTracks = [];

  /// Currently selected quality track
  QualityTrack? _selectedQualityTrack;

  /// Available audio tracks
  List<AudioTrack> _audioTracks = [];

  /// Currently selected audio track
  AudioTrack? _selectedAudioTrack;

  /// Available cast devices
  List<CastDevice> _castDevices = [];

  /// Whether the player has been initialized
  bool _isInitialized = false;

  /// Whether the native cast handler has been initialized for this player
  /// instance. Guards lazy initialization so [_ensureCastInitialized] only
  /// invokes 'initializeCast' once per player lifetime.
  bool _castInitialized = false;

  /// Whether the player has been disposed
  bool _isDisposed = false;

  /// Completer for initialization
  Completer<void>? _initializationCompleter;

  /// H-10: explicit reference count of external consumers holding this
  /// instance across otherwise-idle periods. The periodic stale-instance
  /// sweep ([_cleanupStaleInstances]) previously inferred "abandoned" purely
  /// from `!isPlaying` + a 15-minute inactivity timeout, which disposes a
  /// perfectly live, paused instance the app still holds (e.g. `pause()` a
  /// player, leave the app idle 15 minutes, `play()` again -> throws
  /// [PlayerDisposedException]).
  ///
  /// Callers that keep a [MediaPlayer] reference around without necessarily
  /// listening to any of its streams should call [attach] once they take
  /// ownership and [detach] once they release it, so the sweep never
  /// disposes an instance a caller still intends to use, regardless of its
  /// current playback state. See [_isReferencedByLiveConsumer].
  int _referenceCount = 0;

  /// Registers this caller as an active consumer of this player instance,
  /// protecting it from the stale-instance sweep regardless of its current
  /// playback state (H-10). Each [attach] must be paired with exactly one
  /// [detach]; safe to call multiple times for multiple independent owners.
  void attach() {
    _throwIfDisposed();
    _referenceCount++;
    _markActivity();
  }

  /// Releases a reference previously registered via [attach]. Once the
  /// reference count returns to zero — and there is no other live consumer,
  /// e.g. an active stream subscription (see [_isReferencedByLiveConsumer])
  /// — this instance becomes eligible again for the stale-instance sweep
  /// after the normal 15-minute inactivity threshold.
  void detach() {
    if (_referenceCount > 0) {
      _referenceCount--;
    }
    // Give a fresh 15-minute inactivity grace period from the moment of
    // release, rather than letting the sweep judge staleness against
    // whatever [_lastActivity] happened to be when this instance was last
    // (possibly long ago) protected by a live reference.
    _markActivity();
  }

  /// H-10: whether some live consumer still holds/uses this instance, and so
  /// it must survive the stale-instance sweep regardless of playback state
  /// or elapsed inactivity.
  ///
  /// Two independent signals are honored:
  ///  1. [_referenceCount] > 0 — an explicit [attach]/[detach] registration.
  ///     This is the honest signal: it doesn't depend on *how* the consumer
  ///     uses the player, only on whether it declared ownership.
  ///  2. A live subscription on one of the "primary" broadcast streams a
  ///     typical consumer listens to for the lifetime of its own object —
  ///     e.g. `MediaController` subscribes to [stateStream] (and others) in
  ///     its constructor and only cancels them in its own `dispose()`. This
  ///     fallback protects existing consumers that hold a [MediaPlayer]
  ///     reference and observe it reactively without calling [attach]
  ///     explicitly.
  bool get _isReferencedByLiveConsumer {
    if (_referenceCount > 0) return true;
    return _stateController.hasListener || _positionController.hasListener;
  }

  /// Private constructor for factory pattern
  MediaPlayer._(this.playerId, this._config) {
    _instances[playerId] = this;
    _markActivity();
    _ensureCleanupTimer();
    _setupMethodCallHandler();
    _initializeBufferingService();
    _networkResilienceService = NetworkResilienceService();
  }

  /// Initialize buffering service with configuration
  void _initializeBufferingService() {
    // Convert old BufferConfig to new BufferingConfig if provided
    final bufferingConfig = _config.bufferConfig != null
        ? BufferingConfig(
            minBufferMs: _config.bufferConfig!.minBufferDuration.inMilliseconds,
            maxBufferMs: _config.bufferConfig!.maxBufferDuration.inMilliseconds,
            targetBufferMs:
                _config.bufferConfig!.targetBufferDuration.inMilliseconds,
            rebufferMs: _config.bufferConfig!.rebufferDuration.inMilliseconds,
          )
        : const BufferingConfig(); // Use default config

    _bufferingService = BufferingService(
      config: bufferingConfig,
      platformBufferStatusCallback: _getPlatformBufferStatus,
    );

    // Listen to buffer health updates and forward to public stream
    _bufferingService.bufferHealthStream.listen((health) {
      if (!_bufferHealthController.isClosed) {
        _bufferHealthController.add(health);
      }
    });
  }

  /// Get buffer status from platform
  Future<Map<String, dynamic>> _getPlatformBufferStatus() async {
    try {
      final result = await _invokeMethod<Map<dynamic, dynamic>>(
        'getBufferHealth',
        {'playerId': playerId},
      );

      if (result == null) {
        return {};
      }

      // Convert dynamic map to String map
      return result.map((key, value) => MapEntry(key.toString(), value));
    } catch (e) {
      debugPrint('Error getting buffer status: $e');
      return {};
    }
  }

  /// Enable crash reporting (call once at app startup)
  ///
  /// [reporter] - The crash reporter implementation to use
  ///
  /// Example:
  /// ```dart
  /// MediaPlayer.enableCrashReporting(ConsoleOnlyCrashReporter());
  /// ```
  static void enableCrashReporting(CrashReporter reporter) {
    crashReporter = reporter;
    crashReporter?.log('MediaPlayer crash reporting enabled');
  }

  /// Disable crash reporting
  static void disableCrashReporting() {
    crashReporter?.log('MediaPlayer crash reporting disabled');
    crashReporter = null;
  }

  /// Track activity to prevent premature cleanup
  void _markActivity() {
    _lastActivity[playerId] = DateTime.now();
  }

  /// Ensure cleanup timer is running
  static void _ensureCleanupTimer() {
    _cleanupTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupStaleInstances(),
    );
  }

  /// Clean up stale player instances (thread-safe)
  static void _cleanupStaleInstances() {
    final now = DateTime.now();
    const staleThreshold = Duration(minutes: 15);

    // Create defensive copy of entries to avoid concurrent modification
    final activitySnapshot = Map<String, DateTime>.from(_lastActivity);
    final staleKeys = <String>[];

    for (final entry in activitySnapshot.entries) {
      if (now.difference(entry.value) > staleThreshold) {
        staleKeys.add(entry.key);
      }
    }

    // Process stale instances
    for (final key in staleKeys) {
      // Check instance still exists before cleanup
      final instance = _instances[key];
      if (instance != null &&
          !instance.isPlaying &&
          !instance._isDisposed &&
          !instance._isReferencedByLiveConsumer) {
        debugPrint('MediaPlayer: Auto-cleaning stale instance: $key');

        // Atomic removal pattern: remove from tracking first
        _lastActivity.remove(key);
        _instances.remove(key);

        // Then dispose (this may take time)
        instance.dispose().catchError((e) {
          debugPrint('Error during auto-cleanup of $key: $e');
          crashReporter?.reportError(
            e,
            StackTrace.current,
            context: {'playerId': key, 'operation': 'auto_cleanup'},
            fatal: false,
          );
        });
      }
    }

    // Stop timer if no instances
    if (_instances.isEmpty) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }
  }

  /// Test-only hook: immediately runs the stale-instance sweep that
  /// normally only fires via [_cleanupTimer] every 5 minutes, so tests can
  /// assert its behaviour (H-10) without waiting on real wall-clock time.
  @visibleForTesting
  static void debugRunStaleSweepForTest() => _cleanupStaleInstances();

  /// Test-only hook: back-dates [playerId]'s last-activity timestamp so the
  /// stale-instance sweep considers it eligible on the next run, without
  /// requiring the test to wait out the real 15-minute inactivity threshold
  /// (H-10). No-op if [playerId] has no tracked activity (e.g. unknown id).
  @visibleForTesting
  static void debugMarkStaleForTest(String playerId) {
    if (!_lastActivity.containsKey(playerId)) return;
    _lastActivity[playerId] =
        DateTime.now().subtract(const Duration(minutes: 20));
  }

  /// Factory constructor to create a new media player instance
  factory MediaPlayer({
    String? playerId,
    MediaConfig? config,
  }) {
    // An explicitly-passed playerId keeps its documented singleton-per-id
    // behaviour: reuse the existing (non-disposed) instance if present.
    if (playerId != null) {
      if (_instances.containsKey(playerId) &&
          !_instances[playerId]!._isDisposed) {
        return _instances[playerId]!;
      }

      final playerConfig = config ?? const MediaConfig();
      return MediaPlayer._(playerId, playerConfig);
    }

    // No explicit id: generate a collision-free id. A monotonic counter
    // (rather than a bare timestamp) guarantees uniqueness even when
    // multiple players are constructed within the same millisecond, and
    // never repeats, so a swept/disposed instance's id can never be
    // reissued to a new instance.
    final id =
        'player_${DateTime.now().millisecondsSinceEpoch}_${_autoIdCounter++}';

    final playerConfig = config ?? const MediaConfig();
    return MediaPlayer._(id, playerConfig);
  }

  // Getters with validation
  /// Current configuration
  MediaConfig get config {
    _throwIfDisposed();
    return _config;
  }

  /// Current playlist
  Playlist? get currentPlaylist {
    _throwIfDisposed();
    return _currentPlaylist;
  }

  /// Current media item
  MediaItem? get currentItem {
    _throwIfDisposed();
    return _currentItem;
  }

  /// Current playback state
  PlaybackState get currentState {
    _throwIfDisposed();
    return _currentState;
  }

  /// Whether the player is currently playing
  bool get isPlaying {
    if (_isDisposed) return false;
    return _currentState.state == PlayerState.playing;
  }

  /// Stream of playbook state changes
  Stream<PlaybackState> get stateStream {
    _throwIfDisposed();
    return _stateController.stream;
  }

  /// Stream of position updates
  Stream<Duration> get positionStream {
    _throwIfDisposed();
    return _positionController.stream;
  }

  /// Stream of duration updates
  Stream<Duration> get durationStream {
    _throwIfDisposed();
    return _durationController.stream;
  }

  /// Stream of volume changes
  Stream<double> get volumeStream {
    _throwIfDisposed();
    return _volumeController.stream;
  }

  /// Stream of speed changes
  Stream<double> get speedStream {
    _throwIfDisposed();
    return _speedController.stream;
  }

  /// Stream of subtitle track updates
  Stream<List<SubtitleTrack>> get subtitleTracksStream {
    _throwIfDisposed();
    return _subtitleTracksController.stream;
  }

  /// Stream of quality track updates
  Stream<List<QualityTrack>> get qualityTracksStream {
    _throwIfDisposed();
    return _qualityTracksController.stream;
  }

  /// Stream of audio track updates
  Stream<List<AudioTrack>> get audioTracksStream {
    _throwIfDisposed();
    return _audioTracksController.stream;
  }

  /// Stream of bandwidth updates (in bits per second)
  Stream<int> get bandwidthStream {
    _throwIfDisposed();
    return _bandwidthController.stream;
  }

  /// Stream of buffer health updates
  Stream<BufferHealth> get bufferHealthStream {
    _throwIfDisposed();
    return _bufferHealthController.stream;
  }

  /// Stream of typed playback errors (H-01).
  ///
  /// This is the reachable half of the typed exception hierarchy for
  /// failures that occur *after* an operation's method call has already
  /// returned successfully — which, for native media playback, is most
  /// failures: ExoPlayer/AVPlayer report network, HTTP, DRM, decoder, and
  /// source errors asynchronously via a player-error callback, not as the
  /// result of the `load`/`play` method call itself. Listen here (in
  /// addition to catching exceptions thrown directly by methods like
  /// [load]) to reliably observe every category in [MediaErrorCategory]:
  ///
  /// ```dart
  /// player.errorStream.listen((e) {
  ///   if (e is NetworkException) showOfflineBanner();
  ///   if (e is DrmException) showDrmError(e);
  /// });
  /// ```
  ///
  /// Also receives a [DrmException] whenever [drmSessionStream] reports
  /// [DrmSessionState.error], so DRM failures are reachable through this
  /// stream too rather than only as an untyped session state.
  Stream<MediaPlayerException> get errorStream {
    _throwIfDisposed();
    return _errorController.stream;
  }

  /// Stream of [PlayerPauseReason]s, emitted alongside a `paused`
  /// [PlaybackState] transition when the reason for the pause is known
  /// (currently: Android audio-focus loss). See [PlayerPauseReason].
  Stream<PlayerPauseReason> get pauseReasonStream {
    _throwIfDisposed();
    return _pauseReasonController.stream;
  }

  /// Stream of [ScreenCaptureStatus] updates (B-12).
  ///
  /// Only emits on iOS, and only after [setSecureSurface] has been called
  /// with `enabled: true` — Android's `FLAG_SECURE` blocks capture at the OS
  /// level so there is nothing to detect/report there. See
  /// `lib/src/security/screen_capture_protection.dart` for the full
  /// Android/iOS asymmetry.
  Stream<ScreenCaptureStatus> get screenCaptureStream {
    _throwIfDisposed();
    return _screenCaptureController.stream;
  }

  /// Most recently known [ScreenCaptureStatus]. See [screenCaptureStream].
  ScreenCaptureStatus get screenCaptureStatus {
    _throwIfDisposed();
    return _screenCaptureStatus;
  }

  /// Whether opt-in screen-capture protection (B-12) is currently enabled
  /// for this player. See [setSecureSurface].
  bool get isSecureSurfaceEnabled {
    _throwIfDisposed();
    return _secureSurfaceEnabled;
  }

  /// Current network quality based on bandwidth measurements
  NetworkQuality get networkQuality {
    _throwIfDisposed();
    return _bufferingService.networkQuality;
  }

  /// Buffer statistics for the current session
  BufferStatistics get bufferStatistics {
    _throwIfDisposed();
    return _bufferingService.statistics;
  }

  /// Last known buffer health status
  BufferHealth? get lastBufferHealth {
    _throwIfDisposed();
    return _bufferingService.lastBufferHealth;
  }

  /// H-06: current device connectivity status, driven by native push events
  /// (`ConnectivityManager.NetworkCallback` on Android, `NWPathMonitor` on
  /// iOS — see `NetworkMonitor` on each platform). This is
  /// [NetworkStatus.unknown] until the first native event arrives.
  ///
  /// Distinct from [networkQuality] above: that getter is derived from
  /// ExoPlayer/AVPlayer's own bandwidth *meter* (how fast media is actually
  /// downloading), whereas this reflects the OS-level connectivity signal
  /// (is there a network at all, and what kind).
  NetworkStatus get networkStatus {
    _throwIfDisposed();
    return _networkResilienceService.networkStatus;
  }

  /// Stream of [NetworkStatus] updates — emits every time native reports the
  /// device's connectivity changed (available/lost) or its quality bucket
  /// changed. See [networkStatus].
  Stream<NetworkStatus> get networkStatusStream {
    _throwIfDisposed();
    return _networkResilienceService.networkStatusStream;
  }

  /// Stream of [NetworkChangeEvent]s — a filtered, semantically-labeled view
  /// of [networkStatusStream] that only emits "significant" transitions
  /// (connection lost/restored, quality improved/degraded). See
  /// [NetworkChangeEvent.isSignificant].
  Stream<NetworkChangeEvent> get networkChangeStream {
    _throwIfDisposed();
    return _networkResilienceService.networkChangeStream;
  }

  /// H-06: the [NetworkResilienceService] instance backing [networkStatus] /
  /// [networkStatusStream] / [networkChangeStream], exposed directly so
  /// callers can also use its retry/backoff helpers
  /// ([NetworkResilienceService.withRetry],
  /// [NetworkResilienceService.shouldRetry]) against the same live
  /// connectivity signal this player observes, instead of constructing a
  /// disconnected instance of their own. This is what makes
  /// [NetworkResilienceService] reachable from the normal `MediaPlayer` /
  /// `MediaController` path — previously it had zero call sites outside its
  /// own file and tests.
  NetworkResilienceService get networkResilienceService {
    _throwIfDisposed();
    return _networkResilienceService;
  }

  /// Stream of PiP status updates
  Stream<PipStatus> get pipStatusStream {
    _throwIfDisposed();
    return _pipStatusController.stream;
  }

  /// Stream of [PipActionEvent]s — one per tap on a custom PiP action
  /// declared via `PipConfig.actions` (Android only; see [PipActionEvent]'s
  /// dartdoc). Delivered from the native `onPipAction` method-channel call.
  Stream<PipActionEvent> get pipActionStream {
    _throwIfDisposed();
    return _pipActionController.stream;
  }

  /// Stream of cast status updates
  Stream<CastStatus> get castStatusStream {
    _throwIfDisposed();
    return _castStatusController.stream;
  }

  /// Stream of available cast devices
  Stream<List<CastDevice>> get castDevicesStream {
    _throwIfDisposed();
    return _castDevicesController.stream;
  }

  /// Available subtitle tracks
  List<SubtitleTrack> get subtitleTracks {
    _throwIfDisposed();
    return List.unmodifiable(_subtitleTracks);
  }

  /// Currently selected subtitle track
  SubtitleTrack? get selectedSubtitleTrack {
    _throwIfDisposed();
    return _selectedSubtitleTrack;
  }

  /// Available quality tracks
  List<QualityTrack> get qualityTracks {
    _throwIfDisposed();
    return List.unmodifiable(_qualityTracks);
  }

  /// Currently selected quality track
  QualityTrack? get selectedQualityTrack {
    _throwIfDisposed();
    return _selectedQualityTrack;
  }

  /// Available audio tracks
  List<AudioTrack> get audioTracks {
    _throwIfDisposed();
    return List.unmodifiable(_audioTracks);
  }

  /// Currently selected audio track
  AudioTrack? get selectedAudioTrack {
    _throwIfDisposed();
    return _selectedAudioTrack;
  }

  /// Current bandwidth estimate in bits per second
  int get currentBandwidth {
    _throwIfDisposed();
    return _currentBandwidth;
  }

  /// Whether the current media is a live stream
  bool get isLive {
    _throwIfDisposed();
    return _isLive;
  }

  /// Whether DVR is enabled for the current live media. See [_dvrEnabled]
  /// for how this is derived from the active `HlsConfig`/`DashConfig` on
  /// every [load].
  bool get dvrEnabled {
    _throwIfDisposed();
    return _dvrEnabled;
  }

  /// Whether the current media can be seeked.
  ///
  /// `false` only for a live stream without DVR enabled ([isLive] `&&`
  /// `!`[dvrEnabled]) — every other case (VOD, or live with DVR) is
  /// seekable. [seekTo] throws [InvalidStateException] rather than
  /// attempting a seek when this is `false`.
  bool get isSeekable {
    _throwIfDisposed();
    return !(_isLive && !_dvrEnabled);
  }

  /// Current PiP status
  PipStatus get pipStatus {
    _throwIfDisposed();
    return _pipStatus;
  }

  /// Whether PiP is available
  bool get isPipAvailable => _pipStatus.isSupported;

  /// Whether currently in PiP mode
  bool get isInPipMode => _pipStatus.isActive;

  /// Current cast status
  CastStatus get castStatus {
    _throwIfDisposed();
    return _castStatus;
  }

  /// Whether casting is available
  bool get isCastAvailable => _castStatus.isAvailable;

  /// Whether currently casting
  bool get isCasting => _castStatus.isCasting;

  /// Available cast devices
  List<CastDevice> get castDevices => List.unmodifiable(_castDevices);

  /// Stream of DRM session updates
  Stream<DrmSession> get drmSessionStream {
    _throwIfDisposed();
    return _drmSessionController.stream;
  }

  /// Stream of notification action identifiers only (no position).
  ///
  /// Cannot carry the position a `"seekTo"` (lock-screen / Control Center scrub
  /// bar) action was requested at. Prefer [notificationActionEventStream], which
  /// emits [NotificationActionEvent] and carries [NotificationActionEvent.position]
  /// for that action.
  @Deprecated(
    'Use notificationActionEventStream instead, which carries '
    'NotificationActionEvent.position for "seekTo" — required to make '
    'lock-screen/Control Center scrub-bar seeking work. Kept for backward '
    'compatibility; still receives every action (including "seekTo", with no '
    'position).',
  )
  Stream<String> get notificationActionStream {
    _throwIfDisposed();
    return _notificationActionController.stream;
  }

  /// Stream of notification action events, typed as [NotificationActionEvent].
  ///
  /// Carries [NotificationActionEvent.position] for `"seekTo"` (dragging the
  /// lock-screen / Control Center scrub bar) — see that class's dartdoc. This
  /// stream does not perform the seek itself; whoever consumes it (typically
  /// [NotificationService.actionEventStream], forwarded to the host app) is
  /// responsible for calling `seekTo(event.position)`.
  Stream<NotificationActionEvent> get notificationActionEventStream {
    _throwIfDisposed();
    return _notificationActionEventController.stream;
  }

  /// Whether the player is initialized
  bool get isInitialized {
    _throwIfDisposed();
    return _isInitialized;
  }

  /// Whether the player is disposed
  bool get isDisposed => _isDisposed;

  /// Thin wrapper around `_channel.invokeMethod` that converts a raw
  /// [MissingPluginException] into the typed [ProtocolMismatchException]
  /// (M-16). A [MissingPluginException] means the *compiled* native plugin
  /// does not implement [method] at all — typically because the installed
  /// native platform code is older than this Dart package (the package is
  /// distributed by git ref, so this skew is easy to hit in practice).
  /// Without this wrapper that exception escapes the sealed
  /// [MediaPlayerException] hierarchy entirely and surprises callers who
  /// only catch [MediaPlayerException]. Every other exception — in
  /// particular [PlatformException], which each call site's own catch
  /// block maps to a specific typed exception — passes through unchanged.
  Future<T?> _invokeMethod<T>(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw ProtocolMismatchException(
        'Native plugin does not implement "$method". The installed native '
        'platform code appears to be older than this zmedia_player Dart '
        'package (protocol v$protocolVersion); rebuild the app to pick up '
        'a matching native implementation.',
        dartProtocolVersion: protocolVersion,
        missingMethod: method,
      );
    }
  }

  /// Initialize the player
  Future<void> initialize() async {
    _throwIfDisposed();

    if (_isInitialized) return;

    // If initialization is already in progress, wait for it
    if (_initializationCompleter != null) {
      return _initializationCompleter!.future;
    }

    _initializationCompleter = Completer<void>();
    // Every catch branch below both completes this completer with an error
    // AND (re)throws the same exception to the direct caller. If this is
    // the *only* caller (i.e. no concurrent second call is awaiting
    // `_initializationCompleter!.future` via the branch above), the
    // completer's future would otherwise have no listener at all and Dart
    // reports it as an unhandled zone error even though the direct caller
    // *did* handle it via its own try/catch. Futures support multiple
    // independent listeners, so attaching this no-op handler up front does
    // not suppress the error for a genuine second, concurrent caller.
    unawaited(_initializationCompleter!.future.catchError((_) {}));

    try {
      crashReporter?.log('Initializing MediaPlayer', context: {
        'playerId': playerId,
        'autoPlay': _config.autoPlay,
      });

      // M-16: send this package's protocol version so native can reject an
      // incompatible pairing (e.g. a stale cached native build that
      // predates a required contract change) up front, with a clear error,
      // instead of failing ambiguously on a later call.
      final rawResult = await _invokeMethod<dynamic>('initialize', {
        'playerId': playerId,
        'protocolVersion': protocolVersion,
        'config': _configToMap(_config),
      });

      final nativeProtocolVersion = (rawResult is Map)
          ? (rawResult['protocolVersion'] as num?)?.toInt()
          : null;

      // A native build that predates protocol negotiation returns null
      // (or a bare success with no map) — that's allowed through
      // unchanged, since there is nothing to compare it against yet.
      if (nativeProtocolVersion != null &&
          nativeProtocolVersion < minSupportedNativeProtocolVersion) {
        throw ProtocolMismatchException(
          'Native plugin protocol v$nativeProtocolVersion is older than the '
          'minimum v$minSupportedNativeProtocolVersion this Dart package '
          '(protocol v$protocolVersion) requires. Rebuild the app against a '
          'matching zmedia_player native version.',
          dartProtocolVersion: protocolVersion,
          nativeProtocolVersion: nativeProtocolVersion,
        );
      }

      _isInitialized = true;
      _initializationCompleter!.complete();

      crashReporter?.log('MediaPlayer initialized successfully', context: {
        'playerId': playerId,
        'nativeProtocolVersion': nativeProtocolVersion,
      });

      // B-12: apply the config-declared initial secureSurface value now that
      // the player is initialized. Best-effort — a failure here must not
      // fail initialize() itself, matching how other post-init convenience
      // calls in this package (e.g. reclaimVideoSurface) are treated as
      // non-fatal.
      if (_config.secureSurface) {
        try {
          await setSecureSurface(true);
        } catch (e) {
          debugPrint(
              'MediaPlayer: failed to apply initial secureSurface=true: $e');
        }
      }
    } on ProtocolMismatchException catch (exception, stack) {
      crashReporter?.reportError(exception, stack,
          context: {
            'operation': 'initialize',
            'playerId': playerId,
          },
          fatal: true);

      _initializationCompleter!.completeError(exception);
      _initializationCompleter = null;
      rethrow;
    } on PlatformException catch (e, stack) {
      crashReporter?.reportError(e, stack,
          context: {
            'operation': 'initialize',
            'playerId': playerId,
            'config': _config.toString(),
            'errorCode': e.code,
          },
          fatal: true);

      final MediaPlayerException exception;
      if (e.code == 'PROTOCOL_VERSION_MISMATCH') {
        final details = e.details as Map<dynamic, dynamic>?;
        exception = ProtocolMismatchException(
          e.message ?? 'Native/Dart protocol version mismatch',
          dartProtocolVersion:
              (details?['dartProtocolVersion'] as num?)?.toInt() ??
                  protocolVersion,
          nativeProtocolVersion:
              (details?['nativeProtocolVersion'] as num?)?.toInt(),
          details: details?.map((k, v) => MapEntry(k.toString(), v)),
        );
      } else {
        exception = ConfigurationException(
          'Failed to initialize player: ${e.message ?? e.code}',
          parameter: 'initialization',
          value: playerId,
          details: e.details as Map<String, dynamic>?,
        );
      }
      _initializationCompleter!.completeError(exception);
      _initializationCompleter = null;
      throw exception;
    } catch (e, stack) {
      crashReporter?.reportError(e, stack,
          context: {
            'operation': 'initialize',
            'playerId': playerId,
            'config': _config.toString(),
          },
          fatal: true);

      final exception = ConfigurationException(
        'Failed to initialize player: $e',
        parameter: 'initialization',
        value: playerId,
      );
      _initializationCompleter!.completeError(exception);
      _initializationCompleter = null;
      throw exception;
    }
  }

  /// Load a single media item
  Future<void> load(MediaItem item) async {
    await _ensureInitialized();
    _markActivity();

    // Enforce HTTPS for DRM-protected media URLs before touching any state.
    InputValidator.validateMediaItemWithDrm(item);

    try {
      crashReporter?.setCustomKey('media_id', item.id);
      // M-09: strip the query string (and fragment) before this ever
      // reaches a crash reporter — signed cookies/tokens for authenticated
      // media URLs commonly live there, and crash reports are frequently
      // stored/transmitted by a third-party service outside this app's
      // control.
      crashReporter?.setCustomKey(
          'media_url', _redactUrlForCrashReporting(item.url));
      crashReporter?.setCustomKey('drm_enabled', item.drmConfig != null);

      _currentItem = item;

      // Derives _isLive/_dvrEnabled from item.isLive plus whichever streaming
      // config (HlsConfig/DashConfig) applies to item.url — see the method
      // doc.
      _applyStreamingConfigForLoad(item);

      // Clear previous track data immediately to prevent stale UI
      _subtitleTracks = [];
      _audioTracks = [];
      _qualityTracks = [];
      if (!_subtitleTracksController.isClosed) {
        _subtitleTracksController.add(_subtitleTracks);
      }
      if (!_audioTracksController.isClosed) {
        _audioTracksController.add(_audioTracks);
      }
      if (!_qualityTracksController.isClosed) {
        _qualityTracksController.add(_qualityTracks);
      }

      // Reset playback speed to normal (1.0x) when loading new media.
      // Skipped when already 1.0: the round trip is pure overhead, and on iOS
      // this call was what defeated `autoPlay: false` before the
      // rate/defaultRate split.
      if (_currentState.speed != 1.0) {
        try {
          await setSpeed(1.0);
        } catch (e) {
          // Ignore errors from speed reset - don't block media loading
          debugPrint('Failed to reset speed: $e');
        }
      }

      await _invokeMethod('load', {
        'playerId': playerId,
        'mediaItem': item.toMap(),
        // Fixes the "config only reaches native at initialize()/
        // updateConfig() time" bug: `_config` (HlsConfig/DashConfig -- the
        // `enableDvr`/`liveLatency`/bitrate constraints, plus every other
        // top-level MediaConfig field) is inherently per-item, since
        // whether it even applies is decided by `item.url` (`.m3u8` vs
        // `.mpd` -- the same inference [_applyStreamingConfigForLoad] just
        // used above, and [_configToMap]'s own doc). Sending the full,
        // current config snapshot on every load() means native's copy can
        // never disagree with what Dart just computed for THIS item, even
        // when a host builds a fresh MediaConfig and calls load() again
        // without an intervening updateConfig() call -- previously the only
        // two call sites that ever sent 'config' to native were
        // 'initialize' and 'updateConfig', so a host that only ever calls
        // load() again (exactly what changing hlsConfig.enableDvr and
        // reloading looks like) left native's copy permanently stale. See
        // MediaPlayerManager.kt's/.swift's loadMediaItem for how this is
        // applied (config field replaced, but NOT re-run through
        // applyConfig() -- reapplying volume/speed/mute on every load would
        // undo runtime setVolume()/setSpeed()/setMuted() calls the config
        // snapshot doesn't know about for mute, see those methods' docs).
        // 'config' sent here and via 'updateConfig' share one source of
        // truth (this same `_config` field) so there is nothing to
        // reconcile between them -- whichever of load()/updateConfig() ran
        // most recently is what native holds, exactly mirroring this
        // instance's own `_config` field.
        'config': _configToMap(_config),
      });

      _updateState(_currentState.copyWith(state: PlayerState.buffering));

      crashReporter?.log('Media loaded successfully', context: {
        'mediaId': item.id,
        'duration': item.duration?.inSeconds,
        'mediaType': item.mediaType.name,
      });
    } on PlatformException catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'load',
        'mediaId': item.id,
        // M-09: redacted — see _redactUrlForCrashReporting.
        'url': _redactUrlForCrashReporting(item.url),
        'playerId': playerId,
        'errorCode': e.code,
      });

      _handleLoadError('Failed to load media: ${e.message ?? e.code}');

      // H-01: real native `load` failures are almost always reported
      // *asynchronously* (see MediaPlayer.errorStream) — ExoPlayer/AVPlayer
      // build the media source synchronously but only start actually
      // reading it (and can only detect network/HTTP/decoder/DRM problems)
      // after this call has already returned success. What lands here is a
      // *synchronous* failure while building that source/config (invalid
      // arguments, a rejected DRM config, etc.), reported with the
      // per-operation code (`LOAD_ERROR`) plus, best-effort, a `category`
      // detail (see MediaErrorCategory / native categorizeSynchronousLoadError).
      // Older cached native builds won't send `category` at all — fall back
      // to the historical MediaLoadException-for-everything behaviour, which
      // is still correct: the operation was `load` and it failed.
      final rawDetails = e.details as Map<dynamic, dynamic>?;
      final details = rawDetails?.map((k, v) => MapEntry(k.toString(), v));
      final category =
          MediaErrorCategory.fromWireValue(details?['category'] as String?);
      final message = e.message ?? 'Failed to load media';

      // Network/DRM are distinctive and useful enough to surface as their
      // dedicated type even from this synchronous path. Everything else
      // (including a missing/unrecognized category from an older cached
      // native build) keeps the historical, still-correct
      // MediaLoadException-for-everything behaviour — the operation was
      // `load` and it failed, which is exactly what that type communicates.
      switch (category) {
        case MediaErrorCategory.network:
          throw NetworkException(
            message,
            isOffline: message.toLowerCase().contains('offline'),
            isTimeout: message.toLowerCase().contains('timeout'),
            details: details,
          );
        case MediaErrorCategory.drm:
          throw DrmException(
            message,
            drmType: item.drmConfig?.scheme.toString().split('.').last,
            errorCode: e.code,
            isLicenseError: message.toLowerCase().contains('license'),
            isCertificateError: message.toLowerCase().contains('certificate') ||
                message.toLowerCase().contains('provisioning'),
            details: details,
          );
        case MediaErrorCategory.http:
        case MediaErrorCategory.decoder:
        case MediaErrorCategory.source:
        case MediaErrorCategory.unknown:
          throw MediaLoadException(
            message,
            url: item.url,
            statusCode: details?['httpStatusCode'] as int?,
            details: details,
          );
      }
    } catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'load',
        'mediaId': item.id,
        // M-09: redacted — see _redactUrlForCrashReporting.
        'url': _redactUrlForCrashReporting(item.url),
        'playerId': playerId,
      });

      _handleLoadError('Failed to load media: $e');

      // Re-throw if it's already a MediaPlayerException
      if (e is MediaPlayerException) rethrow;

      throw MediaLoadException(
        'Failed to load media: $e',
        url: item.url,
      );
    }
  }

  /// Set and load a playlist
  Future<void> setPlaylist(Playlist playlist, {int? startIndex}) async {
    await _ensureInitialized();
    _markActivity();

    if (playlist.items.isEmpty) {
      throw const ConfigurationException(
        'Playlist cannot be empty',
        parameter: 'playlist.items',
        value: [],
      );
    }

    final index = (startIndex ?? playlist.currentIndex)
        .clamp(0, playlist.items.length - 1);

    // B-11: setPlaylist() was the one bulk-load entry point that skipped
    // InputValidator entirely — every item's url/drmConfig/httpHeaders was
    // serialized and sent to native unvalidated, so the "DRM requires
    // HTTPS" invariant did not actually hold for playlist-driven playback.
    // Validate every item up front, before any state changes, exactly like
    // load() does for a single item. Left outside the try/catch below (like
    // load()) so a validation failure surfaces as its own typed
    // [ConfigurationException] rather than being re-wrapped as a generic
    // [MediaLoadException].
    for (final item in playlist.items) {
      InputValidator.validateMediaItemWithDrm(item);
    }

    try {
      _currentPlaylist = playlist.copyWith(currentIndex: index);

      // Clear previous track data immediately to prevent stale UI
      _subtitleTracks = [];
      _audioTracks = [];
      _qualityTracks = [];
      if (!_subtitleTracksController.isClosed) {
        _subtitleTracksController.add(_subtitleTracks);
      }
      if (!_audioTracksController.isClosed) {
        _audioTracksController.add(_audioTracks);
      }
      if (!_qualityTracksController.isClosed) {
        _qualityTracksController.add(_qualityTracks);
      }

      // Reset playback speed to normal (1.0x) when loading new playlist.
      // Skipped when already 1.0: the round trip is pure overhead, and on iOS
      // this call was what defeated `autoPlay: false` before the
      // rate/defaultRate split.
      if (_currentState.speed != 1.0) {
        try {
          await setSpeed(1.0);
        } catch (e) {
          // Ignore errors from speed reset - don't block playlist loading
          debugPrint('Failed to reset speed: $e');
        }
      }

      await _invokeMethod('setPlaylist', {
        'playerId': playerId,
        'playlist': _playlistToMap(_currentPlaylist!),
        'startIndex': index,
      });

      _currentItem = _currentPlaylist!.items[index];
      _updateState(_currentState.copyWith(state: PlayerState.buffering));
    } on PlatformException catch (e) {
      _handleLoadError('Failed to set playlist: ${e.message ?? e.code}');
      throw MediaLoadException(
        'Failed to set playlist: ${e.message ?? e.code}',
        details: {
          'itemCount': playlist.items.length,
          ...?e.details as Map<String, dynamic>?
        },
      );
    } catch (e) {
      _handleLoadError('Failed to set playlist: $e');

      // Re-throw if it's already a MediaPlayerException
      if (e is MediaPlayerException) rethrow;

      throw MediaLoadException(
        'Failed to set playlist: $e',
        details: {'itemCount': playlist.items.length},
      );
    }
  }

  /// Start or resume playback
  Future<void> play() async {
    await _ensureInitialized();
    _markActivity();

    try {
      // If playback has finished, restart from the beginning so that calling
      // play() (e.g. from a lock-screen control or the play button) resumes
      // instead of no-opping at the end of the media.
      if (_currentState.state == PlayerState.completed) {
        await _invokeMethod('seekTo', {
          'playerId': playerId,
          'position': 0,
        });
      }

      await _invokeMethod('play', {'playerId': playerId});

      // Start buffer health monitoring
      _bufferingService.startMonitoring();

      crashReporter?.log('Playback started', context: {
        'playerId': playerId,
        'mediaId': _currentItem?.id,
      });
    } on PlatformException catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'play',
        'playerId': playerId,
        'state': _currentState.state.name,
        'mediaId': _currentItem?.id,
      });

      throw PlaybackException(
        'Failed to start playback: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _ensureInitialized();
    _markActivity();

    try {
      await _invokeMethod('pause', {'playerId': playerId});

      // Stop buffer health monitoring when paused
      _bufferingService.stopMonitoring();

      crashReporter?.log('Playback paused', context: {
        'playerId': playerId,
        'position': _currentState.position.inSeconds,
      });
    } on PlatformException catch (e, stack) {
      crashReporter?.reportError(e, stack, context: {
        'operation': 'pause',
        'playerId': playerId,
        'state': _currentState.state.name,
      });

      throw PlaybackException(
        'Failed to pause: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Stop playback
  Future<void> stop() async {
    await _ensureInitialized();
    _markActivity();

    try {
      await _invokeMethod('stop', {'playerId': playerId});
      _updateState(_currentState.copyWith(state: PlayerState.idle));

      // H-08: stop() leaves the playing state just as surely as pause() does
      // — without this, buffer-health polling (a 500ms native channel
      // round-trip; see BufferingService.startMonitoring) kept running
      // indefinitely for any stopped-but-not-disposed player.
      _bufferingService.stopMonitoring();
    } on PlatformException catch (e) {
      throw PlaybackException(
        'Failed to stop: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    await _ensureInitialized();
    // H-10: scrubbing/seeking is ordinary interaction and must count as
    // activity — otherwise a user actively seeking around a paused player
    // could still have it swept as "stale" mid-interaction.
    _markActivity();

    if (position.isNegative) {
      throw ConfigurationException(
        'Seek position cannot be negative',
        parameter: 'position',
        value: position,
      );
    }

    // Live streams without DVR are not seekable — reject rather than
    // silently forwarding a seek native will not honour (see [isSeekable]).
    // This is the single choke point every seek path funnels through,
    // including a lock-screen/Control Center "seekTo" notification action:
    // NotificationService never calls seekTo itself (see its class dartdoc),
    // so a host app forwarding that action here is caught by this guard the
    // same as a direct call.
    if (_isLive && !_dvrEnabled) {
      throw const InvalidStateException(
        'Cannot seek: current media is a live stream without DVR enabled',
        currentState: 'live-no-dvr',
        requiredState: 'seekable',
      );
    }

    try {
      await _invokeMethod('seekTo', {
        'playerId': playerId,
        'position': position.inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw PlaybackException(
        'Failed to seek: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set playbook volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _ensureInitialized();
    // H-10: adjusting volume is ordinary interaction; count it as activity.
    _markActivity();

    final clampedVolume = volume.clamp(0.0, 1.0);

    try {
      await _invokeMethod('setVolume', {
        'playerId': playerId,
        'volume': clampedVolume,
      });

      _config = _config.copyWith(volume: clampedVolume);
      _volumeController.add(clampedVolume);
      _updateState(_currentState.copyWith(volume: clampedVolume));
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set volume: ${e.message ?? e.code}',
        parameter: 'volume',
        value: volume,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    await _ensureInitialized();
    // H-10: changing speed is ordinary interaction; count it as activity.
    _markActivity();

    final clampedSpeed = speed.clamp(0.25, 4.0);

    try {
      await _invokeMethod('setSpeed', {
        'playerId': playerId,
        'speed': clampedSpeed,
      });

      _config = _config.copyWith(speed: clampedSpeed);
      _speedController.add(clampedSpeed);
      _updateState(_currentState.copyWith(speed: clampedSpeed));
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set speed: ${e.message ?? e.code}',
        parameter: 'speed',
        value: speed,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Mute or unmute the player
  Future<void> setMuted(bool muted) async {
    await _ensureInitialized();
    _markActivity();

    try {
      await _invokeMethod('setMuted', {
        'playerId': playerId,
        'muted': muted,
      });

      _updateState(_currentState.copyWith(isMuted: muted));
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set muted: ${e.message ?? e.code}',
        parameter: 'muted',
        value: muted,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Enable or disable screen-capture protection for this player's video
  /// surface (B-12). Opt-in, defaults to off — see
  /// `lib/src/security/screen_capture_protection.dart` for the full,
  /// deliberately-asymmetric behaviour this maps to on each platform:
  ///
  ///  - **Android**: `enabled: true` adds `FLAG_SECURE` to the host
  ///    `Activity`'s window, blocking screenshots/screen recording of it at
  ///    the OS level for as long as ANY player in that Activity has this
  ///    enabled (the flag is window-scoped, not per-surface — `false`
  ///    clears it only once no player in that Activity still wants it).
  ///  - **iOS**: `enabled: true` starts observing `UIScreen.isCaptured` and
  ///    reports changes via [screenCaptureStream]. This is detection only;
  ///    it does not prevent capture.
  ///
  /// Safe to call before or after media is loaded.
  Future<void> setSecureSurface(bool enabled) async {
    await _ensureInitialized();
    _markActivity();

    try {
      await _invokeMethod('setSecureSurface', {
        'playerId': playerId,
        'enabled': enabled,
      });

      _secureSurfaceEnabled = enabled;
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set secure surface: ${e.message ?? e.code}',
        parameter: 'secureSurface',
        value: enabled,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Notify the native layer that a new platform-view host has been attached
  /// and that it should re-assert the player onto the newly-active surface.
  ///
  /// Call this from [MediaPlayerWidget]'s [_onPlatformViewCreated] callback
  /// (and from [didChangeDependencies] when returning from a fullscreen route)
  /// so the newest host always wins the surface.
  ///
  /// On iOS this is a no-op: AVPlayer supports multiple AVPlayerLayers
  /// simultaneously, and each new [UiKitView] host already creates its own
  /// [MediaPlayerView] with a fresh [AVPlayerLayer] wired to the shared
  /// [AVPlayer].  The call succeeds silently even on iOS because the native
  /// handler returns `nil` for unknown methods gracefully.
  ///
  /// On Android the native handler calls `playerView?.setPlayer(exoPlayer)`
  /// so that the newest [PlayerView] (created by [getPlayerView()]) has the
  /// ExoPlayer reference re-attached after it was detached from the old host.
  Future<void> reclaimVideoSurface() async {
    if (!isInitialized) return;
    _markActivity();

    try {
      await _invokeMethod('reclaimVideoSurface', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      // Non-fatal: log and continue.  A failure here means the native side
      // did not handle the call (e.g. older plugin version).
      debugPrint(
          'MediaPlayer.reclaimVideoSurface: ignored PlatformException: ${e.message}');
    } catch (e) {
      debugPrint('MediaPlayer.reclaimVideoSurface: ignored error: $e');
    }
  }

  /// Set video BoxFit mode
  Future<void> setBoxFit(BoxFit boxFit) async {
    await _ensureInitialized();
    _markActivity();

    try {
      await _invokeMethod('setBoxFit', {
        'playerId': playerId,
        'boxFit': _boxFitToString(boxFit),
      });

      _config = _config.copyWith(boxFit: boxFit);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set BoxFit: ${e.message ?? e.code}',
        parameter: 'boxFit',
        value: boxFit.toString(),
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set subtitle track
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    await _ensureInitialized();
    _markActivity();

    // Validate track exists in available tracks
    if (track != null && !_subtitleTracks.any((t) => t.id == track.id)) {
      throw InvalidStateException(
        'Subtitle track not found: ${track.id}',
        currentState:
            'Available tracks: ${_subtitleTracks.map((t) => t.id).join(", ")}',
        requiredState: 'Valid track ID',
      );
    }

    try {
      await _invokeMethod('setSubtitleTrack', {
        'playerId': playerId,
        'subtitleTrack': track?.toMap(),
      });

      _selectedSubtitleTrack = track;
      _updateSubtitleTracksSelection(track?.id);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set subtitle track: ${e.message ?? e.code}',
        parameter: 'subtitleTrack',
        value: track?.id,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set quality track
  Future<void> setQualityTrack(QualityTrack track) async {
    await _ensureInitialized();
    _markActivity();

    // Validate track exists in available tracks
    if (!_qualityTracks.any((t) => t.id == track.id)) {
      throw InvalidStateException(
        'Quality track not found: ${track.id}',
        currentState:
            'Available tracks: ${_qualityTracks.map((t) => t.id).join(", ")}',
        requiredState: 'Valid track ID',
      );
    }

    try {
      await _invokeMethod('setQualityTrack', {
        'playerId': playerId,
        'qualityTrack': _qualityTrackToMap(track),
      });

      _selectedQualityTrack = track;
      _updateQualityTracksSelection(track.id);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set quality track: ${e.message ?? e.code}',
        parameter: 'qualityTrack',
        value: track.id,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Set audio track
  Future<void> setAudioTrack(AudioTrack track) async {
    await _ensureInitialized();
    _markActivity();

    // Validate track exists in available tracks
    if (!_audioTracks.any((t) => t.id == track.id)) {
      throw InvalidStateException(
        'Audio track not found: ${track.id}',
        currentState:
            'Available tracks: ${_audioTracks.map((t) => t.id).join(", ")}',
        requiredState: 'Valid track ID',
      );
    }

    try {
      await _invokeMethod('setAudioTrack', {
        'playerId': playerId,
        'audioTrack': _audioTrackToMap(track),
      });

      _selectedAudioTrack = track;
      _updateAudioTracksSelection(track.id);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to set audio track: ${e.message ?? e.code}',
        parameter: 'audioTrack',
        value: track.id,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Enable automatic quality selection (adaptive bitrate)
  Future<void> enableAutoQuality() async {
    await _ensureInitialized();
    _markActivity();

    try {
      await _invokeMethod('enableAutoQuality', {
        'playerId': playerId,
      });

      _selectedQualityTrack = null;
      _updateQualityTracksSelection(null);
    } on PlatformException catch (e) {
      throw ConfigurationException(
        'Failed to enable auto quality: ${e.message ?? e.code}',
        parameter: 'autoQuality',
        value: true,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Check if Picture-in-Picture is available
  Future<bool> checkPipAvailability() async {
    await _ensureInitialized();

    try {
      debugPrint(
          'MediaPlayer: Checking PiP availability for player: $playerId');
      final result = await _invokeMethod<bool>('checkPipAvailability', {
        'playerId': playerId,
        if (_config.pipConfig != null) 'config': _config.pipConfig!.toMap(),
      });

      debugPrint('MediaPlayer: PiP availability check result: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint(
          'MediaPlayer: Failed to check PiP availability: ${e.message ?? e.code}');
      debugPrint('MediaPlayer: Error details: ${e.details}');
      return false;
    }
  }

  /// Enter Picture-in-Picture mode
  Future<bool> enterPictureInPicture() async {
    await _ensureInitialized();

    if (!_pipStatus.isSupported) {
      throw const ConfigurationException(
        'Picture-in-Picture not supported on this device',
        parameter: 'pip',
        value: 'unavailable',
      );
    }

    try {
      final result = await _invokeMethod<bool>('enterPictureInPicture', {
        'playerId': playerId,
        if (_config.pipConfig != null) 'config': _config.pipConfig!.toMap(),
      });

      return result ?? false;
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to enter PiP mode: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Exit Picture-in-Picture mode
  Future<void> exitPictureInPicture() async {
    await _ensureInitialized();

    try {
      await _invokeMethod('exitPictureInPicture', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to exit PiP mode: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Start cast device discovery
  Future<void> startCastDiscovery() async {
    await _ensureInitialized();
    await _ensureCastInitialized();

    try {
      await _invokeMethod('startCastDiscovery', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to start cast discovery: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Stop cast device discovery
  Future<void> stopCastDiscovery() async {
    await _ensureInitialized();

    try {
      await _invokeMethod('stopCastDiscovery', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to stop cast discovery: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Connect to a cast device
  Future<bool> connectToCastDevice(CastDevice device) async {
    await _ensureInitialized();
    await _ensureCastInitialized();

    try {
      final result = await _invokeMethod<bool>('connectToCastDevice', {
        'playerId': playerId,
        'deviceId': device.id,
        'deviceType': device.type.name,
      });

      return result ?? false;
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to connect to cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Disconnect from current cast device
  Future<void> disconnectFromCastDevice() async {
    await _ensureInitialized();

    try {
      await _invokeMethod('disconnectFromCastDevice', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to disconnect from cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Load media on cast device
  Future<void> loadMediaOnCastDevice(MediaItem mediaItem) async {
    await _ensureInitialized();
    await _ensureCastInitialized();

    // M-07: the cast path forwards only id/title/url/artwork/duration to
    // the receiver device — there is no DRM session on this path at all.
    // Casting a DRM-protected item would either fail opaquely on the
    // receiver or, worse, could expose a stream that was assumed to be
    // protected to an unauthenticated receiver. Refuse outright rather than
    // silently stripping the drmConfig and casting anyway.
    if (mediaItem.drmConfig != null) {
      throw ConfigurationException(
        'Cannot cast DRM-protected media: casting has no DRM session and '
        'would expose protected content to an unauthenticated receiver.',
        parameter: 'drmConfig',
        value: mediaItem.id,
      );
    }

    // B-11: validate the url/headers before handing them to native, same as
    // load()/setPlaylist(). validateMediaItemWithDrm() would no-op here
    // (drmConfig is already known-null above), so validate the URL/headers
    // directly instead.
    InputValidator.validateUrl(mediaItem.url);

    // C-02 Stage 1: validateUrl() now accepts file:// media URLs for local
    // playback on this device, but a cast receiver is a separate device with
    // no access to this device's filesystem — a file:// URL cannot possibly
    // work there. Refuse explicitly rather than letting native fail opaquely.
    if (Uri.parse(mediaItem.url).scheme.toLowerCase() == 'file') {
      throw ConfigurationException(
        'Cannot cast a local file:// URL: the cast receiver has no access '
        "to this device's filesystem.",
        parameter: 'url',
        value: mediaItem.url,
      );
    }
    if (mediaItem.httpHeaders != null) {
      InputValidator.validateHeaders(mediaItem.httpHeaders!);
    }

    try {
      await _invokeMethod('loadMediaOnCastDevice', {
        'playerId': playerId,
        'mediaItem': {
          'id': mediaItem.id,
          'title': mediaItem.title,
          'url': mediaItem.url,
          'artworkUrl': mediaItem.artworkUrl,
          'duration': mediaItem.duration?.inMilliseconds,
        },
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to load media on cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Play on cast device
  Future<void> castPlay() async {
    await _ensureInitialized();

    try {
      await _invokeMethod('castPlay', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to play on cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Pause on cast device
  Future<void> castPause() async {
    await _ensureInitialized();

    try {
      await _invokeMethod('castPause', {
        'playerId': playerId,
      });
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to pause on cast device: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Skip to next item in playlist
  Future<void> skipToNext() async {
    _validatePlaylistOperation();

    final nextIndex = _currentPlaylist!.nextIndex;
    if (nextIndex == null) {
      throw const InvalidStateException(
        'No next item available',
        currentState: 'At last item',
        requiredState: 'More items in playlist',
      );
    }

    await skipToIndex(nextIndex);
  }

  /// Skip to previous item in playlist
  Future<void> skipToPrevious() async {
    _validatePlaylistOperation();

    final previousIndex = _currentPlaylist!.previousIndex;
    if (previousIndex == null) {
      throw const InvalidStateException(
        'No previous item available',
        currentState: 'At first item',
        requiredState: 'More items in playlist',
      );
    }

    await skipToIndex(previousIndex);
  }

  /// Skip to specific index in playlist
  Future<void> skipToIndex(int index) async {
    _validatePlaylistOperation();

    if (index < 0 || index >= _currentPlaylist!.items.length) {
      throw ConfigurationException(
        'Invalid playlist index: $index',
        parameter: 'index',
        value: index,
        details: {'playlistLength': _currentPlaylist!.items.length},
      );
    }

    try {
      await _invokeMethod('skipToIndex', {
        'playerId': playerId,
        'index': index,
      });

      _currentPlaylist = _currentPlaylist!.copyWith(currentIndex: index);
      _currentItem = _currentPlaylist!.items[index];
    } on PlatformException catch (e) {
      throw PlaybackException(
        'Failed to skip to index: ${e.message ?? e.code}',
        errorCode: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Update player configuration
  Future<void> updateConfig(MediaConfig config) async {
    _throwIfDisposed();

    final oldConfig = _config;
    _config = config;

    if (_isInitialized) {
      try {
        await _invokeMethod('updateConfig', {
          'playerId': playerId,
          'config': _configToMap(config),
        });
      } on PlatformException catch (e) {
        // Revert config on failure
        _config = oldConfig;
        throw ConfigurationException(
          'Failed to update config: ${e.message ?? e.code}',
          parameter: 'config',
          value: config,
          details: e.details as Map<String, dynamic>?,
        );
      }

      // B-12: secureSurface is applied via the dedicated setSecureSurface
      // MethodChannel call (see setSecureSurface's doc for why — it needs
      // Activity/window access on Android that generic config application
      // doesn't have), not through the 'updateConfig' map above. Mirror any
      // change here too so updateConfig() stays a complete way to change
      // this setting. Best-effort: a failure here does not roll back the
      // rest of the config update that already succeeded above.
      if (config.secureSurface != oldConfig.secureSurface) {
        try {
          await setSecureSurface(config.secureSurface);
        } catch (e) {
          debugPrint('MediaPlayer: failed to apply secureSurface change '
              'from updateConfig: $e');
        }
      }
    }
  }

  /// Dispose the player and release resources
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _instances.remove(playerId);
    _lastActivity.remove(playerId);

    // Close platform channel
    if (_isInitialized) {
      try {
        await _invokeMethod('dispose', {'playerId': playerId});
      } catch (e) {
        // Ignore disposal errors but log them
        debugPrint('Warning: Error disposing MediaPlayer: $e');
      }
    }

    // Dispose buffering service
    _bufferingService.dispose();

    // H-06: dispose network resilience service (closes its own stream
    // controllers, cancels active retries and any monitoring timer).
    _networkResilienceService.dispose();

    // Close stream controllers safely
    await _safeCloseStreams();

    _isInitialized = false;
  }

  /// Safely close all stream controllers
  Future<void> _safeCloseStreams() async {
    final controllers = [
      _stateController,
      _positionController,
      _durationController,
      _volumeController,
      _speedController,
      _subtitleTracksController,
      _qualityTracksController,
      _audioTracksController,
      _bandwidthController,
      _bufferHealthController,
      _pipStatusController,
      _pipActionController,
      _castStatusController,
      _castDevicesController,
      _drmSessionController,
      _notificationActionController,
      _notificationActionEventController,
      _errorController,
      _pauseReasonController,
      _screenCaptureController,
    ];

    final errors = <String, dynamic>{};

    for (var i = 0; i < controllers.length; i++) {
      final controller = controllers[i];
      try {
        if (!controller.isClosed) {
          await controller.close();
        }
      } catch (e, stackTrace) {
        final controllerName = _getControllerName(i);
        errors[controllerName] = e.toString();
        debugPrint('Error closing $controllerName: $e');

        // Report to crash reporter if available (non-fatal)
        crashReporter?.reportError(
          e,
          stackTrace,
          context: {
            'playerId': playerId,
            'controller': controllerName,
            'operation': 'stream_cleanup',
          },
          fatal: false,
        );
      }
    }

    // Log summary if there were errors
    if (errors.isNotEmpty) {
      debugPrint(
        'MediaPlayer($playerId): Failed to close ${errors.length}/${controllers.length} controllers: ${errors.keys.join(", ")}',
      );
    }
  }

  /// Helper method for error reporting in stream cleanup
  String _getControllerName(int index) {
    const names = [
      'stateController',
      'positionController',
      'durationController',
      'volumeController',
      'speedController',
      'subtitleTracksController',
      'qualityTracksController',
      'audioTracksController',
      'bandwidthController',
      'bufferHealthController',
      'pipStatusController',
      'pipActionController',
      'castStatusController',
      'castDevicesController',
      'drmSessionController',
      'notificationActionController',
      'notificationActionEventController',
      'errorController',
      'pauseReasonController',
      'screenCaptureController',
    ];
    return index < names.length ? names[index] : 'unknownController';
  }

  // Private helper methods

  /// Derives [_isLive] and [_dvrEnabled] for a freshly-[load]ed [item].
  ///
  /// The applicable streaming config is inferred from [item.url] the same
  /// way native infers the media source type: a URL containing `.m3u8`
  /// selects [MediaConfig.hlsConfig], one containing `.mpd` selects
  /// [MediaConfig.dashConfig]; anything else (progressive playback) has no
  /// applicable streaming config at all.
  ///
  ///  - [_dvrEnabled] becomes that config's `enableDvr` (`false` when no
  ///    config applies), gating [isSeekable]/[seekTo] for this item.
  ///  - [_isLive] becomes `item.isLive` OR'd with that config's deprecated
  ///    `enableLiveStream` — see `HlsConfig.enableLiveStream`'s dartdoc for
  ///    why this is an OR rather than a replacement: `MediaItem.isLive` is
  ///    the canonical field, but an app that already set the deprecated flag
  ///    must not have media silently stop being treated as live during the
  ///    deprecation period.
  void _applyStreamingConfigForLoad(MediaItem item) {
    final url = item.url;
    var dvrEnabled = false;
    var configEnablesLive = false;

    if (url.contains('.m3u8')) {
      final hls = _config.hlsConfig;
      dvrEnabled = hls?.enableDvr ?? false;
      // ignore: deprecated_member_use_from_same_package
      configEnablesLive = hls?.enableLiveStream ?? false;
    } else if (url.contains('.mpd')) {
      final dash = _config.dashConfig;
      dvrEnabled = dash?.enableDvr ?? false;
      // ignore: deprecated_member_use_from_same_package
      configEnablesLive = dash?.enableLiveStream ?? false;
    }

    _dvrEnabled = dvrEnabled;
    _isLive = item.isLive || configEnablesLive;
  }

  /// Validate playlist operation
  void _validatePlaylistOperation() {
    _throwIfDisposed();
    if (_currentPlaylist == null) {
      throw const InvalidStateException(
        'No playlist set',
        currentState: 'No playlist',
        requiredState: 'Playlist loaded',
      );
    }
  }

  /// Handle load errors consistently
  void _handleLoadError(String errorMessage) {
    _updateState(_currentState.copyWith(
      state: PlayerState.error,
      errorMessage: errorMessage,
    ));
  }

  /// Update subtitle tracks selection state
  void _updateSubtitleTracksSelection(String? selectedId) {
    _subtitleTracks = _subtitleTracks
        .map((t) => t.copyWith(isSelected: t.id == selectedId))
        .toList();
    _subtitleTracksController.add(_subtitleTracks);
  }

  /// Update quality tracks selection state
  void _updateQualityTracksSelection(String? selectedId) {
    _qualityTracks = _qualityTracks
        .map((t) => t.copyWith(isSelected: t.id == selectedId))
        .toList();
    _qualityTracksController.add(_qualityTracks);
  }

  /// Update audio tracks selection state
  void _updateAudioTracksSelection(String selectedId) {
    _audioTracks = _audioTracks
        .map((t) => t.copyWith(isSelected: t.id == selectedId))
        .toList();
    _audioTracksController.add(_audioTracks);
  }

  /// Throw if disposed
  void _throwIfDisposed() {
    if (_isDisposed) {
      throw const PlayerDisposedException();
    }
  }

  /// Setup method call handler for platform events.
  ///
  /// Registers the static dispatch handler once at the class level, then
  /// routes each incoming call to the correct instance via playerId.
  void _setupMethodCallHandler() {
    if (!_channelHandlerRegistered) {
      _channelHandlerRegistered = true;
      _channel.setMethodCallHandler(_staticMethodCallHandler);
    }
  }

  /// Static handler registered once on the channel.
  /// Dispatches each call to the matching MediaPlayer instance.
  static Future<void> _staticMethodCallHandler(MethodCall call) async {
    final arguments = call.arguments as Map<dynamic, dynamic>?;
    final playerId = arguments?['playerId'] as String?;

    if (playerId == null) {
      debugPrint(
          'MediaPlayer: incoming call "${call.method}" missing playerId');
      return;
    }

    final instance = _instances[playerId];
    if (instance == null) {
      debugPrint(
          'MediaPlayer: no instance for playerId "$playerId" (call: ${call.method})');
      return;
    }

    await instance._handleMethodCall(call);
  }

  /// Handle method calls from platform for THIS instance.
  Future<void> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments as Map<dynamic, dynamic>?;

    try {
      switch (call.method) {
        case 'onStateChanged':
          _handleStateChanged(arguments!);
          break;
        case 'onPositionChanged':
          _handlePositionChanged(arguments!);
          break;
        case 'onDurationChanged':
          _handleDurationChanged(arguments!);
          break;
        case 'onSubtitleTracksChanged':
          _handleSubtitleTracksChanged(arguments!);
          break;
        case 'onQualityTracksChanged':
          _handleQualityTracksChanged(arguments!);
          break;
        case 'onAudioTracksChanged':
          _handleAudioTracksChanged(arguments!);
          break;
        case 'onPipStatusChanged':
          _handlePipStatusChanged(arguments!);
          break;
        case 'onPipAction':
          _handlePipAction(arguments!);
          break;
        case 'onCastStatusChanged':
          _handleCastStatusChanged(arguments!);
          break;
        case 'onCastDevicesChanged':
          _handleCastDevicesChanged(arguments!);
          break;
        case 'onNotificationAction':
          _handleNotificationAction(arguments!);
          break;
        case 'onBandwidthChanged':
          _handleBandwidthChanged(arguments!);
          break;
        case 'onNetworkStatusChanged':
          _handleNetworkStatusChanged(arguments!);
          break;
        case 'onDrmSessionUpdate':
          _handleDrmSessionUpdate(arguments!);
          break;
        case 'onScreenCaptureChanged':
          _handleScreenCaptureChanged(arguments!);
          break;
        case 'onError':
          _handleError(arguments!);
          break;
        default:
          debugPrint('Unhandled method call: ${call.method}');
      }
    } catch (e) {
      debugPrint('Error handling method call ${call.method}: $e');
    }
  }

  /// Handle state change events from platform
  void _handleStateChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final stateString = arguments['state'] as String;
    final state = _stringToPlayerState(stateString);
    final wasCompleted = _currentState.state == PlayerState.completed;

    _updateState(_currentState.copyWith(
      state: state,
      isBuffering: arguments['isBuffering'] as bool? ?? false,
      bufferPercentage:
          (arguments['bufferPercentage'] as num?)?.toDouble() ?? 0.0,
    ));

    // H-08: buffer-health polling (BufferingService.startMonitoring) makes a
    // native channel round-trip every 500ms and must not keep running once
    // playback is no longer actively progressing. play()/pause() already
    // start/stop it for the Dart-driven path, but native can also drive a
    // transition away from `playing` entirely on its own — audio focus loss
    // (-> paused), natural completion (-> completed), a player error
    // (-> error), or a native-initiated stop (-> idle) — without either of
    // those methods ever being called. `buffering` is deliberately excluded:
    // that's exactly the state where buffer health visibility matters most
    // (e.g. a mid-playback rebuffer stall).
    if (state != PlayerState.playing && state != PlayerState.buffering) {
      _bufferingService.stopMonitoring();
    }

    // H-01: only present on Android, and only for a "paused" event caused
    // by the OS revoking audio focus — see
    // MediaPlayerInstance.onPlayWhenReadyChanged/onIsPlayingChanged in
    // android/.../MediaPlayerManager.kt. Absent otherwise, in which case a
    // paused state is left to mean an ordinary user/API pause.
    final pauseReasonString = arguments['pauseReason'] as String?;
    if (pauseReasonString == 'audioFocusLoss' &&
        !_pauseReasonController.isClosed) {
      _pauseReasonController.add(PlayerPauseReason.audioFocusLoss);
    }

    // Auto-advance the playlist (respecting repeat/shuffle) when an item
    // finishes, or loop the current item when looping is enabled. Guarded by
    // wasCompleted so repeated 'completed' events don't advance more than once.
    if (state == PlayerState.completed && !wasCompleted) {
      _handlePlaybackCompleted();
    }
  }

  /// Called once when playback transitions into [PlayerState.completed].
  ///
  /// If a playlist is loaded and has a next index (per its repeat/shuffle
  /// rules), advances to it and plays. Otherwise, if [MediaConfig.looping] is
  /// enabled, restarts the current item.
  void _handlePlaybackCompleted() {
    if (_isDisposed) return;

    final playlist = _currentPlaylist;
    final nextIndex = playlist?.nextIndex;
    if (playlist != null && nextIndex != null) {
      skipToIndex(nextIndex).then((_) => play()).catchError(
            (Object e) => debugPrint('MediaPlayer: auto-advance failed: $e'),
          );
      return;
    }

    if (_config.looping) {
      seekTo(Duration.zero).then((_) => play()).catchError(
            (Object e) => debugPrint('MediaPlayer: loop restart failed: $e'),
          );
    }
  }

  /// Handle position change events from platform
  void _handlePositionChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final positionMs = arguments['position'] as int;
    final position = Duration(milliseconds: positionMs);

    _updateState(_currentState.copyWith(position: position));

    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
  }

  /// Handle duration change events from platform
  void _handleDurationChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final durationMs = arguments['duration'] as int;
    final duration = Duration(milliseconds: durationMs);

    // Update isLive flag if provided
    if (arguments.containsKey('isLive')) {
      _isLive = arguments['isLive'] as bool? ?? false;
      debugPrint(
          'MediaPlayer: Duration changed - duration: ${duration.inMilliseconds}ms, isLive: $_isLive');
    } else {
      debugPrint(
          'MediaPlayer: Duration changed - duration: ${duration.inMilliseconds}ms, isLive key not found in arguments');
    }

    _updateState(_currentState.copyWith(duration: duration));

    if (!_durationController.isClosed) {
      _durationController.add(duration);
    }
  }

  /// Handle bandwidth change events from platform
  void _handleBandwidthChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final bandwidth = arguments['bandwidth'] as int? ?? 0;
    _currentBandwidth = bandwidth;

    // Update buffering service with bandwidth measurement
    _bufferingService.updateFromBandwidth(bandwidth);

    if (!_bandwidthController.isClosed) {
      _bandwidthController.add(bandwidth);
    }
  }

  /// H-06: handle native connectivity push events (`NetworkMonitor` on
  /// Android/iOS). A single wire event covers "available", "lost", and
  /// "quality changed" — [NetworkStatus.fromPlatform] builds the new status
  /// and [NetworkResilienceService.updateNetworkStatus] derives the
  /// available/lost/quality-improved/quality-degraded distinction by diffing
  /// it against the previous one (see [NetworkChangeEvent]), so no
  /// information is lost by not having three separate method names on the
  /// wire.
  void _handleNetworkStatusChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final status = NetworkStatus.fromPlatform(
      arguments.map((key, value) => MapEntry(key.toString(), value)),
    );
    _networkResilienceService.updateNetworkStatus(status);
  }

  /// Handle subtitle tracks change events from platform
  void _handleSubtitleTracksChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final tracksData = arguments['tracks'] as List<dynamic>;
      _subtitleTracks = tracksData
          .cast<Map<dynamic, dynamic>>()
          .map((data) => SubtitleTrack.fromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_subtitleTracksController.isClosed) {
        _subtitleTracksController.add(_subtitleTracks);
      }
    } catch (e) {
      debugPrint('Error processing subtitle tracks: $e');
    }
  }

  /// Handle quality tracks change events from platform
  void _handleQualityTracksChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final tracksData = arguments['tracks'] as List<dynamic>;
      debugPrint(
          'MediaPlayer: Received ${tracksData.length} quality tracks from native');

      _qualityTracks = tracksData
          .cast<Map<dynamic, dynamic>>()
          .map((data) => _qualityTrackFromMap(Map<String, dynamic>.from(data)))
          .toList();

      debugPrint('MediaPlayer: Parsed quality tracks:');
      for (var track in _qualityTracks) {
        debugPrint(
            '  - ${track.name}: ${track.width}x${track.height}, ${track.bitrate} bps');
      }

      if (!_qualityTracksController.isClosed) {
        _qualityTracksController.add(_qualityTracks);
      }
    } catch (e) {
      debugPrint('Error processing quality tracks: $e');
    }
  }

  /// Handle audio tracks change events from platform
  void _handleAudioTracksChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final tracksData = arguments['tracks'] as List<dynamic>;
      _audioTracks = tracksData
          .cast<Map<dynamic, dynamic>>()
          .map((data) => _audioTrackFromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_audioTracksController.isClosed) {
        _audioTracksController.add(_audioTracks);
      }
    } catch (e) {
      debugPrint('Error processing audio tracks: $e');
    }
  }

  /// Handle DRM session update events from platform
  void _handleDrmSessionUpdate(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final session = DrmSession.fromMap(Map<String, dynamic>.from(arguments));

      if (!_drmSessionController.isClosed) {
        _drmSessionController.add(session);
      }

      // H-01/C-01: bridge a DRM session error into the typed exception
      // hierarchy too, so DRM/license failures are reachable via
      // [errorStream] and not only as an untyped [DrmSessionState.error] on
      // [drmSessionStream]. [DrmSession] carries no structured error
      // classification (only a free-text [DrmSession.errorMessage]), so
      // isLicenseError/isCertificateError are best-effort text matches, same
      // pattern as the platform-code substring checks below in [load]'s
      // catch block.
      if (session.state == DrmSessionState.error) {
        final message = session.errorMessage ?? 'DRM session error';

        // C-01: unlike a synchronous `load()` failure or a native `onError`
        // callback (see [_handleError]), a DRM session error previously only
        // ever emitted on [_errorController] and never called [_updateState]
        // — so [PlaybackState.state] stayed wherever it was (typically
        // `buffering`) and never became [PlayerState.error]. That made a DRM
        // failure invisible to [MediaController.hasError] and to anything
        // driven by [stateStream]/[PlaybackState] rather than [errorStream]
        // directly. Mirror [_handleError]'s behaviour here so a DRM failure
        // is reachable through both surfaces, exactly like every other
        // playback error category.
        _updateState(_currentState.copyWith(
          state: PlayerState.error,
          errorMessage: message,
        ));

        if (!_errorController.isClosed) {
          final lowerMessage = message.toLowerCase();
          _errorController.add(DrmException(
            message,
            isLicenseError: lowerMessage.contains('license'),
            isCertificateError: lowerMessage.contains('certificate') ||
                lowerMessage.contains('provisioning'),
          ));
        }
      }
    } catch (e) {
      debugPrint('Error processing DRM session update: $e');
    }
  }

  /// Handle screen-capture status change events from platform (B-12,
  /// iOS-only — see [screenCaptureStream]).
  void _handleScreenCaptureChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final status = ScreenCaptureStatus.fromMap(
        Map<String, dynamic>.from(arguments),
      );
      _screenCaptureStatus = status;

      if (!_screenCaptureController.isClosed) {
        _screenCaptureController.add(status);
      }
    } catch (e) {
      debugPrint('Error processing screen capture status: $e');
    }
  }

  /// Handle error events from platform
  ///
  /// H-01: this is the *primary* path real playback errors take — native
  /// media playback errors (network, HTTP, DRM, decoder, source) are
  /// reported by ExoPlayer/AVPlayer asynchronously via a player-error
  /// callback, not as the result of the `load`/`play` method call that
  /// triggered them (which has usually already returned successfully by
  /// the time the failure is detected). In addition to the untyped
  /// [PlaybackState.errorMessage] this always set, build and emit the
  /// concrete typed [MediaPlayerException] via [errorStream] using the
  /// shared [MediaErrorCategory] wire-format vocabulary native now sends.
  void _handleError(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    final errorMessage = arguments['error'] as String;

    _updateState(_currentState.copyWith(
      state: PlayerState.error,
      errorMessage: errorMessage,
    ));

    if (!_errorController.isClosed) {
      final details = arguments['httpStatusCode'] != null
          ? {'httpStatusCode': arguments['httpStatusCode']}
          : null;
      _errorController.add(mapNativeMediaError(
        message: errorMessage,
        categoryWireValue: arguments['category'] as String?,
        nativeErrorCode: arguments['nativeErrorCode']?.toString(),
        details: details,
      ));
    }
  }

  /// Handle PiP status change events from platform
  void _handlePipStatusChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final statusMap = Map<String, dynamic>.from(arguments);
      debugPrint('MediaPlayer: Received PiP status from native: $statusMap');

      _pipStatus = PipStatus.fromMap(statusMap);

      if (!_pipStatusController.isClosed) {
        _pipStatusController.add(_pipStatus);
      }

      debugPrint(
          'PiP status changed: ${_pipStatus.state}, isSupported: ${_pipStatus.isSupported}, isActive: ${_pipStatus.isActive}, error: ${_pipStatus.errorMessage ?? "none"}');
    } catch (e) {
      debugPrint('Error processing PiP status: $e');
    }
  }

  /// Handle cast status change events from platform
  void _handleCastStatusChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final statusMap = Map<String, dynamic>.from(arguments);
      _castStatus = CastStatus.fromMap(statusMap);

      if (!_castStatusController.isClosed) {
        _castStatusController.add(_castStatus);
      }

      debugPrint('Cast status changed: ${_castStatus.state}');
    } catch (e) {
      debugPrint('Error processing cast status: $e');
    }
  }

  /// Handle cast devices change events from platform
  void _handleCastDevicesChanged(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final devicesData = arguments['devices'] as List<dynamic>;
      _castDevices = devicesData
          .map((data) => CastDevice.fromMap(Map<String, dynamic>.from(data)))
          .toList();

      if (!_castDevicesController.isClosed) {
        _castDevicesController.add(_castDevices);
      }

      debugPrint(
          'Cast devices updated: ${_castDevices.length} device(s) found');
    } catch (e) {
      debugPrint('Error processing cast devices: $e');
    }
  }

  /// Handle notification action events from platform
  void _handleNotificationAction(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final event = NotificationActionEvent.fromMap(arguments);

      if (!_notificationActionEventController.isClosed) {
        _notificationActionEventController.add(event);
      }
      if (!_notificationActionController.isClosed) {
        _notificationActionController.add(event.action);
      }

      debugPrint('Notification action received: ${event.action}'
          '${event.position != null ? ' (position: ${event.position})' : ''}');
    } catch (e) {
      debugPrint('Error processing notification action: $e');
    }
  }

  /// Handle Picture-in-Picture custom action taps from platform (Android
  /// only — see [PipActionEvent]).
  void _handlePipAction(Map<dynamic, dynamic> arguments) {
    if (_isDisposed) return;

    try {
      final event = PipActionEvent.fromMap(arguments);

      if (!_pipActionController.isClosed) {
        _pipActionController.add(event);
      }

      debugPrint('PiP action received: ${event.actionId}');
    } catch (e) {
      debugPrint('Error processing PiP action: $e');
    }
  }

  /// Update current state and notify listeners
  void _updateState(PlaybackState newState) {
    if (_isDisposed) return;

    _currentState = newState;

    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// Ensure player is initialized
  Future<void> _ensureInitialized() async {
    _throwIfDisposed();

    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Lazily initializes the native CastHandler for this player.
  ///
  /// The native plugin only creates a [CastHandler] when `initializeCast` is
  /// called via the method channel. Without this call, [startCastDiscovery]
  /// and related cast operations are silent no-ops at the native layer
  /// (`castHandlers[playerId]` is null, so `?.startDiscovery()` returns
  /// immediately without doing anything).
  ///
  /// This guard ensures the initialization channel call is made at most once
  /// per player instance. It is called lazily from [startCastDiscovery],
  /// [connectToCastDevice], and [loadMediaOnCastDevice] — the three entry
  /// points that actually require an active native handler.
  Future<void> _ensureCastInitialized() async {
    if (_castInitialized) return;
    try {
      await _invokeMethod('initializeCast', {
        'playerId': playerId,
        'config': (_config.castConfig ?? const CastConfig()).toMap(),
      });
      _castInitialized = true;
    } on PlatformException catch (e) {
      throw PlatformOperationException(
        'Failed to initialize cast handler: ${e.message ?? e.code}',
        code: e.code,
        details: e.details as Map<String, dynamic>?,
      );
    }
  }

  /// Convert MediaConfig to Map for platform communication
  Map<String, dynamic> _configToMap(MediaConfig config) {
    return {
      'autoPlay': config.autoPlay,
      'looping': config.looping,
      'boxFit': _boxFitToString(config.boxFit),
      'volume': config.volume,
      'speed': config.speed,
      'startMuted': config.startMuted,
      'httpHeaders': config.httpHeaders,
      'showControls': config.showControls,
      'controlsTimeout': config.controlsTimeout.inMilliseconds,
      'allowBackgroundPlayback': config.allowBackgroundPlayback,
      'useHardwareAcceleration': config.useHardwareAcceleration,
      // C-03b: Android-only transparent adaptive-stream segment cache.
      // Absent/null is treated by native as disabled; see
      // AdaptiveCacheConfig's dartdoc for the full Android-only contract
      // and the DRM fail-safe. iOS never reads this key.
      if (config.adaptiveCacheConfig != null)
        'adaptiveCacheConfig': config.adaptiveCacheConfig!.toMap(),
      // Both cross the channel unconditionally when set; native picks
      // whichever one applies to the media item currently being loaded by
      // inspecting its URL (`.m3u8` -> hlsConfig, `.mpd` -> dashConfig — the
      // same inference `MediaPlayer._applyStreamingConfigForLoad` uses on
      // the Dart side). See StreamingConfig/HlsConfig/DashConfig's dartdocs
      // for exactly which fields each platform actually reads.
      if (config.hlsConfig != null) 'hlsConfig': config.hlsConfig!.toMap(),
      if (config.dashConfig != null) 'dashConfig': config.dashConfig!.toMap(),
    };
  }

  /// Convert Playlist to Map for platform communication
  Map<String, dynamic> _playlistToMap(Playlist playlist) {
    return {
      'id': playlist.id,
      'title': playlist.title,
      'items': playlist.items.map((item) => item.toMap()).toList(),
      'currentIndex': playlist.currentIndex,
      'mode': playlist.mode.name,
      'repeatMode': playlist.repeatMode.name,
    };
  }

  /// Convert BoxFit to string
  String _boxFitToString(BoxFit boxFit) {
    return switch (boxFit) {
      BoxFit.contain => 'contain',
      BoxFit.cover => 'cover',
      BoxFit.fill => 'fill',
      BoxFit.fitWidth => 'fitWidth',
      BoxFit.fitHeight => 'fitHeight',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scaleDown',
    };
  }

  /// Convert string to PlayerState
  PlayerState _stringToPlayerState(String state) {
    return switch (state) {
      'idle' => PlayerState.idle,
      'buffering' => PlayerState.buffering,
      'ready' => PlayerState.ready,
      'playing' => PlayerState.playing,
      'paused' => PlayerState.paused,
      'completed' => PlayerState.completed,
      'error' => PlayerState.error,
      _ => PlayerState.idle,
    };
  }

  /// Convert QualityTrack to Map
  Map<String, dynamic> _qualityTrackToMap(QualityTrack track) {
    return {
      'id': track.id,
      'name': track.name,
      'bitrate': track.bitrate,
      'width': track.width,
      'height': track.height,
      'frameRate': track.frameRate,
      'isSelected': track.isSelected,
      'isAvailable': track.isAvailable,
      'codec': track.codec,
    };
  }

  /// Convert Map to QualityTrack
  QualityTrack _qualityTrackFromMap(Map<String, dynamic> map) {
    return QualityTrack(
      id: map['id'] as String,
      name: map['name'] as String,
      bitrate: map['bitrate'] as int,
      width: map['width'] as int?,
      height: map['height'] as int?,
      frameRate: (map['frameRate'] as num?)?.toDouble(),
      isSelected: map['isSelected'] as bool? ?? false,
      isAvailable: map['isAvailable'] as bool? ?? true,
      codec: map['codec'] as String?,
    );
  }

  /// Convert AudioTrack to Map
  Map<String, dynamic> _audioTrackToMap(AudioTrack track) {
    return {
      'id': track.id,
      'name': track.name,
      'language': track.language,
      'isSelected': track.isSelected,
      'isAvailable': track.isAvailable,
      'codec': track.codec,
      'channels': track.channels,
      'sampleRate': track.sampleRate,
    };
  }

  /// Convert Map to AudioTrack
  AudioTrack _audioTrackFromMap(Map<String, dynamic> map) {
    return AudioTrack(
      id: map['id'] as String,
      name: map['name'] as String,
      language: map['language'] as String?,
      isSelected: map['isSelected'] as bool? ?? false,
      isAvailable: map['isAvailable'] as bool? ?? true,
      codec: map['codec'] as String?,
      channels: map['channels'] as int?,
      sampleRate: map['sampleRate'] as int?,
    );
  }
}

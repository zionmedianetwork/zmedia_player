import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import '../services/subtitle_service.dart';
import '../services/cache_service.dart';
import '../core/media_config.dart';
import '../models/subtitle_track.dart';
import 'media_controls.dart';
import 'subtitle_view.dart';
import 'overlays/error_overlay.dart';

/// Main widget for displaying video content with optional controls
///
/// This widget provides the video surface and integrates with the media controls.
/// It handles touch interactions, aspect ratio, and control visibility.
class MediaPlayerWidget extends StatefulWidget {
  /// Media controller for this player widget
  final MediaController controller;

  /// Whether to show media controls overlay
  final bool showControls;

  /// Custom controls widget (if null, default controls will be used)
  final Widget? customControls;

  /// Placeholder widget shown when no media is loaded
  final Widget? placeholder;

  /// Widget shown when an error occurs
  final Widget? errorWidget;

  /// Widget shown during buffering
  final Widget? bufferingWidget;

  /// How the video should fit within the available space
  final BoxFit? boxFit;

  /// Background color of the player
  final Color backgroundColor;

  /// Callback when the player widget is tapped
  final VoidCallback? onTap;

  /// Callback when the player widget is double-tapped
  final VoidCallback? onDoubleTap;

  /// Callback when the player widget is long-pressed
  final VoidCallback? onLongPress;

  /// Whether to allow fullscreen mode
  final bool allowFullscreen;

  /// Aspect ratio for the video (if null, uses video's natural aspect ratio)
  final double? aspectRatio;

  /// Whether to expand to fill available space
  final bool expandToFill;

  const MediaPlayerWidget({
    super.key,
    required this.controller,
    this.showControls = true,
    this.customControls,
    this.placeholder,
    this.errorWidget,
    this.bufferingWidget,
    this.boxFit,
    this.backgroundColor = Colors.black,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.allowFullscreen = true,
    this.aspectRatio,
    this.expandToFill = false,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  /// Whether we have a native view
  bool _hasNativeView = false;

  /// The native view widget
  Widget? _nativeView;

  /// Whether the widget is disposed
  bool _isDisposed = false;

  /// Whether we're currently creating a native view
  bool _isCreatingNativeView = false;

  /// Current media item ID to track changes
  String? _currentMediaId;

  // ---------------------------------------------------------------------------
  // Immersive-landscape state
  // ---------------------------------------------------------------------------

  /// Last known orientation — used to detect orientation changes in build.
  Orientation? _lastOrientation;

  /// Whether we have applied immersive mode at least once.  Used in dispose()
  /// so we only restore if we actually changed the system UI.
  bool _appliedImmersive = false;

  /// Subtitle service for managing subtitle tracks
  late final SubtitleService _subtitleService;

  /// Cache service for media caching
  late final CacheService _cacheService;

  /// Keep alive for performance
  @override
  bool get wantKeepAlive => true;

  /// Whether we have a native view (for fullscreen reuse)
  bool get hasNativeView => _hasNativeView;

  /// The native view widget (for fullscreen reuse)
  Widget? get nativeView => _nativeView;

  @override
  void initState() {
    super.initState();

    // Initialize services
    _subtitleService = SubtitleService();
    _cacheService = CacheService(
        widget.controller.config.cacheConfig ?? const CacheConfig());

    // Listen to app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Initialize player after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _initializePlayer();
      }
    });

    // Listen for media loading events
    widget.controller.addListener(_onControllerChanged);
  }

  /// Force resize the native view to fix sizing issues
  void _forceResizeNativeView() {
    if (!_isDisposed && mounted) {
      setState(() {
        // Force a rebuild to ensure proper sizing
      });

      // Additional resize after a delay to ensure the platform view gets the correct size
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isDisposed) {
          setState(() {
            // Final resize to ensure video is properly sized
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle controller changes
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _refreshVideoSurface();
    }

    // Propagate boxFit changes to native when the platform view already exists.
    // creationParams are one-shot (sent only at view creation), so a prop change
    // must be forwarded explicitly via the method channel.
    final oldBoxFit = oldWidget.boxFit ?? oldWidget.controller.config.boxFit;
    final newBoxFit = widget.boxFit ?? widget.controller.config.boxFit;
    if (oldBoxFit != newBoxFit && _hasNativeView && !_isDisposed && mounted) {
      widget.controller.player.setBoxFit(newBoxFit).ignore();
    }

    // Force resize if we detect potential sizing issues
    if (oldWidget.key != widget.key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted) {
          _forceResizeNativeView();
        }
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Restore system UI if we ever applied immersive mode, so a popped player
    // never leaves the rest of the app stuck in immersive sticky.
    if (_appliedImmersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).ignore();
    }

    // Clean up observers and listeners
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);

    // Clean up services
    _subtitleService.dispose();
    _cacheService.dispose();

    // Clean up native view
    _cleanupNativeView();

    super.dispose();
  }

  void _onControllerChanged() {
    if (_isDisposed) return;

    final currentItem = widget.controller.currentItem;
    final currentMediaId = currentItem?.id ?? currentItem?.title;

    // Only recreate native view if media changed or we don't have one
    if (currentMediaId != _currentMediaId) {
      _currentMediaId = currentMediaId;

      if (currentItem != null && !_hasNativeView && !_isCreatingNativeView) {
        _createNativeView();
      } else if (currentItem == null) {
        _cleanupNativeView();
      }
    }

    // Don't force rebuild here - let the native view creation handle it
    // This prevents race conditions between media loading and UI updates
  }

  void _refreshVideoSurface() {
    if (_isDisposed) return;

    // Only cleanup and recreate if we don't have a valid native view
    // This prevents unnecessary surface destruction during orientation changes
    if (!_hasNativeView || _nativeView == null) {
      // Clean up existing view
      _cleanupNativeView();

      // Recreate the native view if we have media
      if (widget.controller.currentItem != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed) {
            _createNativeView();
          }
        });
      }
    }
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;

    try {
      if (!widget.controller.player.isInitialized) {
        await widget.controller.initialize();
      }

      // Create native view if we have media
      if (widget.controller.currentItem != null && !_hasNativeView) {
        await _createNativeView();
      }
    } catch (e) {
      debugPrint('Error initializing player: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _hasNativeView = false;
          _nativeView = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Listen to orientation changes for responsive behavior
    final orientation = MediaQuery.orientationOf(context);
    final isLandscape = orientation == Orientation.landscape;

    // immersiveLandscape: detect orientation changes and schedule a
    // SystemChrome call via addPostFrameCallback (never during build).
    if (widget.controller.config.immersiveLandscape &&
        orientation != _lastOrientation) {
      _lastOrientation = orientation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed || !mounted) return;
        if (isLandscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
              .ignore();
          _appliedImmersive = true;
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).ignore();
          // Keep _appliedImmersive = true so dispose() still restores if needed
        }
      });
    }

    // In landscape mode, prioritize video display
    if (isLandscape && widget.expandToFill) {
      return Container(
        color: widget.backgroundColor,
        child: _buildPlayerContent(),
      );
    }

    return _buildPlayerContent();
  }

  Widget _buildPlayerContent() {
    Widget content;

    // Determine what content to show based on player state and native view availability
    final playerState = widget.controller.state.state;

    // If we have a native view and media loaded, show the video surface (even if buffering)
    if (_hasNativeView && widget.controller.currentItem != null) {
      content = _buildVideoSurface();
    } else {
      // Otherwise, determine content based on state
      switch (playerState) {
        case PlayerState.idle:
          content = _buildPlaceholder();
          break;
        case PlayerState.buffering:
          content = _buildBuffering();
          break;
        case PlayerState.error:
          content = _buildError();
          break;
        case PlayerState.ready:
        case PlayerState.playing:
        case PlayerState.paused:
        case PlayerState.completed:
          content = _buildVideoSurface();
          break;
      }
    }

    // Wrap content with gesture detection and controls
    content = _buildInteractiveContent(content);

    // Apply aspect ratio if specified or if we should expand to fill
    if (widget.aspectRatio != null) {
      content = AspectRatio(
        aspectRatio: widget.aspectRatio!,
        child: content,
      );
    } else if (!widget.expandToFill) {
      // Use video's natural aspect ratio (16:9 as fallback)
      final aspectRatio = _getVideoAspectRatio();
      content = AspectRatio(
        aspectRatio: aspectRatio,
        child: content,
      );
    }

    return Container(
      color: widget.backgroundColor,
      child: content,
    );
  }

  Widget _buildInteractiveContent(Widget content) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final showTapDetector = !widget.controller.controlsVisible;
        final showControlsOverlay =
            widget.showControls && widget.controller.controlsVisible;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Video content - ensure it fills the available space
            Positioned.fill(child: content),

            // Subtitle overlay - show when subtitles are enabled
            if (widget.controller.config.enableSubtitles == true)
              _buildSubtitleOverlay(),

            // Controls overlay - only show when needed
            if (showControlsOverlay)
              Positioned.fill(child: _buildControlsOverlay()),

            // Transparent tap detector overlay - positioned ABOVE native view
            // This ensures taps are captured even when native platform view
            // (UiKitView/AndroidView) would otherwise consume them
            if (showTapDetector)
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onTap ?? _handleTap,
                  onDoubleTap: widget.onDoubleTap ?? _handleDoubleTap,
                  onLongPress: widget.onLongPress,
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Build subtitle overlay
  Widget _buildSubtitleOverlay() {
    if (widget.controller.currentItem == null) {
      return const SizedBox.shrink();
    }

    return SubtitleView(
      subtitleService: _subtitleService,
      position: widget.controller.state.position,
      config: widget.controller.config.subtitleConfig ?? const SubtitleConfig(),
      enabled: widget.controller.config.enableSubtitles,
      onTrackChanged: (_) {
        // Subtitle track change is handled internally by SubtitleView
      },
    );
  }

  Widget _buildVideoSurface() {
    // Check if we have media loaded
    if (widget.controller.currentItem == null) {
      return _buildPlaceholder();
    }

    final playerState = widget.controller.state.state;

    // Show error state if there's an error
    if (playerState == PlayerState.error) {
      return _buildError();
    }

    // Only show buffering if we truly don't have a native view yet
    if (!_hasNativeView || _nativeView == null) {
      return _buildBuffering();
    }

    // We have a native view - show it regardless of buffering state
    // The native player will handle its own buffering overlay if needed
    final nativeContent = Container(
      color: Colors.black, // Ensure background is black for video
      child: SizedBox.expand(
        child: _nativeView!,
      ),
    );

    // respectSafeArea: wrap the native view subtree in a SafeArea so the
    // video insets below the status bar / notch in fullscreen/landscape.
    // When false (default), the video is edge-to-edge.
    if (widget.controller.config.respectSafeArea) {
      return SafeArea(child: nativeContent);
    }
    return nativeContent;
  }

  Future<void> _createNativeView() async {
    if (_isDisposed || _isCreatingNativeView) return;

    _isCreatingNativeView = true;

    try {
      // Ensure player is initialized before creating native view
      if (!widget.controller.player.isInitialized) {
        await widget.controller.initialize();
        if (_isDisposed) return;
      }

      // Check if we have a current media item
      final currentItem = widget.controller.currentItem;
      if (currentItem == null) {
        if (mounted && !_isDisposed) {
          setState(() {
            _hasNativeView = false;
            _nativeView = null;
          });
        }
        return;
      }

      // Add a small delay to ensure media is properly loaded
      await Future.delayed(const Duration(milliseconds: 100));

      // Create platform-specific video surface
      const viewType = 'zmedia_player_view';
      final creationParams = {
        'playerId': widget.controller.player.playerId,
        'boxFit':
            _boxFitToString(widget.boxFit ?? widget.controller.config.boxFit),
      };

      Widget nativeView;
      final platform = Theme.of(context).platform;

      if (platform == TargetPlatform.android) {
        nativeView = AndroidView(
          viewType: viewType,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      } else if (platform == TargetPlatform.iOS) {
        nativeView = UiKitView(
          viewType: viewType,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      } else {
        return;
      }

      // Set the native view with proper sizing and ensure it's visible
      if (mounted && !_isDisposed) {
        setState(() {
          _hasNativeView = true;
          _nativeView = Container(
            color: Colors.black, // Ensure black background
            child: SizedBox.expand(
              child: nativeView,
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('Error creating native view: $e');
      // Set error state if platform view creation fails
      if (mounted && !_isDisposed) {
        setState(() {
          _hasNativeView = false;
          _nativeView = null;
        });
      }
    } finally {
      _isCreatingNativeView = false;
    }
  }

  void _cleanupNativeView() {
    if (mounted && !_isDisposed) {
      setState(() {
        _hasNativeView = false;
        _nativeView = null;
      });
    } else {
      _hasNativeView = false;
      _nativeView = null;
    }
  }

  void _onPlatformViewCreated(int viewId) {
    if (_isDisposed) return;

    // Tell the native side that this new host is now the active surface so
    // it re-attaches the ExoPlayer / AVPlayer to the freshly created view.
    // On Android this is essential: getPlayerView() already detached the old
    // PlayerView's player, and reclaimVideoSurface() wires the exoPlayer back
    // onto the new PlayerView.  On iOS this is a no-op (AVPlayer supports
    // multiple AVPlayerLayers) but is harmless.
    widget.controller.player.reclaimVideoSurface().ignore();

    // Apply the effective boxFit immediately after the native view is created.
    // creationParams are one-shot and ignored by the native factory, so we must
    // push the value via the method channel on every new view creation.
    if (mounted && !_isDisposed) {
      final effectiveBoxFit = widget.boxFit ?? widget.controller.config.boxFit;
      widget.controller.player.setBoxFit(effectiveBoxFit).ignore();
    }

    // Platform view is ready - trigger a rebuild to ensure it's displayed
    if (mounted && !_isDisposed) {
      // Add a small delay to ensure the platform view is fully initialized
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_isDisposed) {
          setState(() {
            // Force a rebuild to ensure the native view is displayed
          });

          // Additional delay and rebuild to ensure visibility
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && !_isDisposed) {
              setState(() {
                // Final rebuild to ensure video is visible
              });
            }
          });
        }
      });
    }

    // The MediaController will handle platform communication through method channels
  }

  Widget _buildControlsOverlay() {
    if (widget.customControls != null) {
      return widget.customControls!;
    }

    return AnimatedOpacity(
      opacity: widget.controller.controlsVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !widget.controller.controlsVisible,
        child: MediaControls(
          controller: widget.controller,
          allowFullscreen: widget.allowFullscreen,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    if (widget.placeholder != null) {
      return widget.placeholder!;
    }

    return Container(
      color: widget.backgroundColor,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 64,
              color: Colors.white70,
            ),
            SizedBox(height: 16),
            Text(
              'No media loaded',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuffering() {
    if (widget.bufferingWidget != null) {
      return widget.bufferingWidget!;
    }

    return Container(
      color: widget.backgroundColor,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    if (widget.errorWidget != null) {
      return widget.errorWidget!;
    }

    // Use comprehensive ErrorOverlay by default
    // Note: We pass the error message as a string since the full exception
    // object is not currently stored in PlaybackState
    return ErrorOverlay(
      error: widget.controller.state.errorMessage,
      controller: widget.controller,
      onRetry: _handleRetry,
      showErrorCode: true,
      animated: true,
    );
  }

  void _handleTap() {
    if (!_isDisposed) {
      widget.controller.toggleControls();
    }
  }

  void _handleDoubleTap() {
    if (!_isDisposed) {
      widget.controller.togglePlayPause();
    }
  }

  void _handleRetry() {
    final currentItem = widget.controller.currentItem;
    if (currentItem != null && !_isDisposed) {
      // Clean up current view before retry
      _cleanupNativeView();
      // Reload the media
      widget.controller.load(currentItem);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposed) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Hide controls when app goes to background
        widget.controller.forceHideControls();
        break;
      case AppLifecycleState.resumed:
        // Refresh video surface when app comes back to foreground
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed) {
            _refreshVideoSurface();
          }
        });
        break;
      case AppLifecycleState.detached:
        // Clean up when app is detached
        _cleanupNativeView();
        break;
      default:
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Called when the widget's dependencies change — most relevantly when the
    // navigator route changes (e.g. fullscreen route is pushed/popped).
    // Re-assert native surface ownership so this (inline) host renders video
    // once it is back on screen, and trigger a layout rebuild.
    if (!_isDisposed && mounted) {
      // Small delay to let the route transition complete so the platform view
      // is fully attached to the window before we nudge the native layer.
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && !_isDisposed) {
          // reclaimVideoSurface is a no-op if no platform view exists yet; it
          // only matters when returning from fullscreen where the inline host
          // was de-prioritised.
          widget.controller.player.reclaimVideoSurface().ignore();
          refreshVideoSurface();
        }
      });
    }
  }

  double _getVideoAspectRatio() {
    // Try to get actual video aspect ratio from controller state
    try {
      // Check if we have video dimensions in the state
      // Note: This would need to be added to PlaybackState if video dimensions are needed
      // For now, we'll use a reasonable default based on the media type or duration

      // If we have a current media item, we could potentially get aspect ratio from metadata
      final currentItem = widget.controller.currentItem;
      if (currentItem != null) {
        // Check if the media item has aspect ratio metadata
        // This would depend on how MediaItem is structured
        // For now, assume standard video aspect ratios based on common formats

        // You could potentially add aspectRatio as a property to MediaItem
        // and return currentItem.aspectRatio ?? (16 / 9);
      }
    } catch (_) {
      // Ignore aspect ratio retrieval errors; fall back to 16:9 below
    }

    // Return 16:9 as default (most common video aspect ratio)
    return 16 / 9;
  }

  String _boxFitToString(BoxFit boxFit) {
    switch (boxFit) {
      case BoxFit.contain:
        return 'contain';
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitWidth:
        return 'fitWidth';
      case BoxFit.fitHeight:
        return 'fitHeight';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
        return 'scaleDown';
    }
  }

  /// Force recreate the native view (useful for debugging video display issues)
  void forceRecreateNativeView() {
    if (!_isDisposed) {
      _cleanupNativeView();
      _createNativeView();
    }
  }

  /// Refresh video surface (useful after returning from fullscreen)
  void refreshVideoSurface() {
    if (!_isDisposed && mounted) {
      setState(() {
        // Force rebuild of video surface
      });

      // Additional refresh after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isDisposed) {
          setState(() {
            // Final refresh to ensure video is visible
          });
        }
      });
    }
  }

  /// Update box fit for the current video
  Future<void> updateBoxFit(BoxFit newBoxFit) async {
    if (_isDisposed || !_hasNativeView) return;

    try {
      // Update the box fit through the method channel
      await widget.controller.player.setBoxFit(newBoxFit);

      // Force a refresh of the video surface to apply the new box fit
      await _forceRefreshVideoSurface();
    } catch (e) {
      debugPrint('Error updating box fit: $e');
    }
  }

  /// Force refresh video surface to fix black screen issues
  Future<void> _forceRefreshVideoSurface() async {
    if (_isDisposed) return;

    // Clean up existing view
    _cleanupNativeView();

    // Wait a bit before recreating
    await Future.delayed(const Duration(milliseconds: 300));

    // Recreate if we still have media
    if (widget.controller.currentItem != null && !_isDisposed) {
      await _createNativeView();
    }
  }
}

/// A fullscreen scaffold that wraps [MediaPlayerWidget], locks the device to
/// landscape orientation, hides the system UI, and shows an always-visible
/// close button.
///
/// ### Single-native-view contract
///
/// Every [MediaPlayerWidget] (and therefore every [FullscreenMediaPlayer])
/// creates exactly ONE native platform-view host (`UiKitView` on iOS,
/// `AndroidView` on Android) per mount.  Because the underlying native player
/// (AVPlayer + AVPlayerLayer on iOS, ExoPlayer + PlayerView on Android) is a
/// singleton per `playerId`, two concurrently-mounted hosts contend for the
/// same surface and the inactive one shows a black frame.
///
/// **Symptoms**: pushing [FullscreenMediaPlayer] while an inline
/// [MediaPlayerWidget] for the same controller is still mounted results in a
/// black fullscreen (audio continues).
///
/// **Root-cause fix**: On iOS, [MediaPlayerInstance.getPlayerView()] now
/// creates a separate `AVPlayerLayer` per host so both can render
/// simultaneously via `AVPlayer`'s native multi-layer support.  On Android,
/// [MediaPlayerInstance.getPlayerView()] detaches the ExoPlayer from the
/// previous [PlayerView] before returning a fresh one for the new host, and
/// the Dart `_onPlatformViewCreated` callback calls
/// [MediaPlayer.reclaimVideoSurface] to re-attach the player.
///
/// **Recommended usage pattern** (belt-and-suspenders, required on Android):
/// Before pushing [FullscreenMediaPlayer], hide the inline [MediaPlayerWidget]
/// (replace it with a [ColoredBox(color: Colors.black)] placeholder so the
/// Flutter platform-view host is unmounted).  Restore the inline player after
/// the route pops.  This guarantees only one host is alive at a time and
/// avoids any residual surface-contention on devices where the native fix
/// cannot fully compensate.
///
/// ```dart
/// Future<void> _enterFullscreen() async {
///   if (mounted) setState(() => _isFullscreen = true); // swap to placeholder
///   try {
///     await Navigator.of(context).push(MaterialPageRoute(
///       builder: (_) => FullscreenMediaPlayer(controller: _controller),
///       fullscreenDialog: true,
///     ));
///   } finally {
///     if (mounted) setState(() => _isFullscreen = false); // restore player
///   }
/// }
/// ```
///
/// See also: `docs/fullscreen_pip_guide.md` for the full explanation and
/// example code.
class FullscreenMediaPlayer extends StatefulWidget {
  /// Media controller for the fullscreen player
  final MediaController controller;

  /// Custom controls widget
  final Widget? customControls;

  /// Background color
  final Color backgroundColor;

  const FullscreenMediaPlayer({
    super.key,
    required this.controller,
    this.customControls,
    this.backgroundColor = Colors.black,
  });

  @override
  State<FullscreenMediaPlayer> createState() => _FullscreenMediaPlayerState();
}

class _FullscreenMediaPlayerState extends State<FullscreenMediaPlayer>
    with WidgetsBindingObserver {
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set fullscreen orientation and hide system UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _enterFullscreen();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // Restore system UI and orientation
    _exitFullscreen();
    super.dispose();
  }

  Future<void> _enterFullscreen() async {
    if (_isDisposed) return;

    try {
      // Set fullscreen mode
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // Set landscape orientation
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {
      // Ignore system UI / orientation errors on platforms that do not support them
    }
  }

  Future<void> _exitFullscreen() async {
    if (_isDisposed) return;

    try {
      // Restore system UI
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // Restore all orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {
      // Ignore system UI / orientation errors on platforms that do not support them
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && !_isDisposed) {
      // Re-enter fullscreen mode when app resumes
      _enterFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_isDisposed) {
          _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        // Do NOT wrap with SafeArea here — the inner controls (MediaControls,
        // CupertinoMediaControls, MaterialMediaControls) already apply their own
        // SafeArea per-zone (top bar / bottom bar).  A SafeArea at this level
        // would double-count insets and cause RenderFlex overflow in landscape.
        body: Stack(
          children: [
            // Video player fills the entire scaffold body.
            Positioned.fill(
              child: MediaPlayerWidget(
                controller: widget.controller,
                showControls: true,
                customControls: widget.customControls,
                expandToFill: true,
                backgroundColor: widget.backgroundColor,
                onTap: () => widget.controller.toggleControls(),
                onDoubleTap: () => widget.controller.togglePlayPause(),
              ),
            ),

            // Guaranteed exit affordance: always-visible close button in the
            // top-left corner, outside the auto-hiding controls overlay.
            // Wired directly to Navigator.maybePop so the user can always exit
            // even if the inner controls are hidden or overflowing.
            Positioned(
              top: 8,
              left: 8,
              child: SafeArea(
                child: Semantics(
                  button: true,
                  label: 'Exit fullscreen',
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 22,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(40, 40),
                    ),
                    tooltip: 'Exit fullscreen',
                    onPressed: () {
                      if (!_isDisposed) {
                        Navigator.maybePop(context);
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

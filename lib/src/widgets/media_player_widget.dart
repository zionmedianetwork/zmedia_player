import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
///
/// ## Gesture callbacks
///
/// Every gesture the widget forwards comes in two flavours: a bare
/// [VoidCallback] ([onTap], [onDoubleTap], [onLongPress]) and a
/// position-carrying counterpart ([onTapDown], [onDoubleTapDown],
/// [onLongPressStart]).  Four rules apply uniformly to all three gestures:
///
/// 1. **Both may be supplied, and both fire.**  The order is
///    `GestureDetector`'s own: the position-carrying variant fires first (on
///    pointer-down / press recognition), the bare variant second (on gesture
///    recognition).
/// 2. **Supplying *either* variant means the host has taken over that
///    gesture**, so the widget's own built-in default for it does not run.
///    The built-in defaults are: single tap toggles the controls overlay,
///    double tap toggles play/pause.  Long press has no built-in default.
/// 3. **`localPosition` is relative to the player's own box** — the box this
///    widget occupies after any [aspectRatio] sizing, which is also the box
///    the video surface, subtitle overlay and controls overlay fill.  So the
///    width you divide by is the widget's own width (`context.size?.width`,
///    or a wrapping [LayoutBuilder]'s `constraints.maxWidth`), not the
///    screen width.  This is the coordinate space to use for
///    left-half/right-half zones; `globalPosition` is screen-relative and is
///    what you want for positioning an overlay in an [Overlay]/[Stack] above
///    the whole route.
/// 4. **A callback runs only if no overlay widget claimed the gesture
///    first** — the controls overlay is always mounted and stacked *above*
///    the package's own tap detector, so the overlay gets first refusal on
///    every pointer.  Overlay *visibility* is not what decides this: the
///    built-in [MediaControls] are made non-hit-testable while hidden, and
///    while visible they forward background taps and double taps (with
///    position) straight back to these callbacks, so tap and double tap
///    behave identically in both states.  Long press is the one exception —
///    it is not forwarded by the built-in overlay, so it only fires while the
///    overlay is hidden.  With [customControls] the host's own recognizers
///    decide; anything they do not claim falls through to these callbacks
///    (set [enableBuiltInGestures] to `false` to remove the detector
///    entirely).
///
/// Direction-aware double-tap seek — the near-universal video-player
/// convention — is therefore expressed as:
///
/// ```dart
/// LayoutBuilder(
///   builder: (context, constraints) => MediaPlayerWidget(
///     controller: controller,
///     onDoubleTapDown: (details) {
///       final isLeftHalf =
///           details.localPosition.dx < constraints.maxWidth / 2;
///       final target = isLeftHalf
///           ? controller.position - const Duration(seconds: 10)
///           : controller.position + const Duration(seconds: 10);
///       controller.seekTo(target < Duration.zero ? Duration.zero : target);
///     },
///   ),
/// )
/// ```
///
/// Because only `onDoubleTapDown` is supplied above, the built-in
/// double-tap-to-play/pause default is suppressed; single tap still toggles
/// the controls overlay because no tap callback was supplied.
class MediaPlayerWidget extends StatefulWidget {
  /// Media controller for this player widget
  final MediaController controller;

  /// Whether to show media controls overlay
  final bool showControls;

  /// Custom controls widget (if null, default controls will be used).
  ///
  /// ## Gesture ownership
  ///
  /// The controls overlay is **always mounted and always hit-testable**,
  /// including while [MediaController.controlsVisible] is `false`. The
  /// package's own full-surface tap detector (see [enableBuiltInGestures]) is
  /// stacked *underneath* the overlay, so any gesture recognizer declared
  /// inside [customControls] gets first refusal on every pointer — the
  /// built-in detector only sees pointers that no widget in the overlay
  /// claimed.
  ///
  /// This means a host-defined gesture zone (e.g. left/right double-tap seek
  /// zones) keeps working when the overlay auto-hides, instead of silently
  /// being taken over by the package.
  ///
  /// Two consequences worth designing for:
  ///
  /// * The package does **not** fade or unmount [customControls] for you.
  ///   Drive your own visibility from [MediaController.controlsVisible] (or
  ///   extend `CustomControlsBase` / use `CustomControlsBuilder`, which expose
  ///   `ControlsState.isVisible` and a ready-made fade animation).
  /// * Anything your overlay renders at zero opacity is still hit-testable.
  ///   Wrap chrome you do not want tappable while hidden in an
  ///   `IgnorePointer(ignoring: !state.isVisible)` and leave only the gesture
  ///   zones live. Likewise, if your overlay paints a full-bleed scrim
  ///   (a `Container` with a `color` is opaque to hit testing), it will
  ///   absorb the tap that would otherwise reveal the controls — gate that
  ///   scrim on visibility too, or return `const SizedBox.shrink()` while
  ///   hidden to restore the pre-0.3.1 behavior entirely.
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

  /// Callback when the player widget is tapped.
  ///
  /// Fires for a tap that no widget inside the controls overlay claimed —
  /// identically whether the overlay is visible or hidden (see the
  /// "Gesture callbacks" section of the class docs for how that is achieved).
  /// Carries no position; use [onTapDown] when the tap location matters.
  ///
  /// When supplied — on its own or alongside [onTapDown] — it replaces the
  /// built-in "toggle controls" behavior. Never invoked when
  /// [enableBuiltInGestures] is `false`.
  final VoidCallback? onTap;

  /// Position-carrying counterpart of [onTap].
  ///
  /// Invoked on pointer-down with a [TapDownDetails] whose `localPosition` is
  /// measured from the top-left of the player's own box (the same box the
  /// video surface and controls overlay fill), so
  /// `details.localPosition.dx < box.width / 2` reliably means "left half".
  ///
  /// Fires *before* [onTap] when both are supplied, and — like [onTap] —
  /// fires identically whether the controls overlay is visible or hidden.
  /// Never invoked when [enableBuiltInGestures] is `false`.
  final GestureTapDownCallback? onTapDown;

  /// Callback when the player widget is double-tapped.
  ///
  /// Fires for a double tap that no widget inside the controls overlay
  /// claimed — identically whether the overlay is visible or hidden. When
  /// supplied — on its own or alongside [onDoubleTapDown] — it replaces the
  /// built-in "toggle play/pause" behavior. Never invoked when
  /// [enableBuiltInGestures] is `false`.
  ///
  /// Carries no position; use [onDoubleTapDown] to build the conventional
  /// direction-aware double-tap seek (left half = rewind, right half =
  /// forward).
  final VoidCallback? onDoubleTap;

  /// Position-carrying counterpart of [onDoubleTap].
  ///
  /// Invoked on the pointer-down of the *second* tap of a double-tap, with a
  /// [TapDownDetails] whose `localPosition` is measured from the top-left of
  /// the player's own box.  Fires *before* [onDoubleTap] when both are
  /// supplied, and fires identically whether the controls overlay is visible
  /// or hidden (with the default controls the visible overlay forwards it via
  /// [MediaControls.onBackgroundDoubleTapDown], which spans the same box, so
  /// `localPosition` is unchanged across the two paths). Never invoked when
  /// [enableBuiltInGestures] is `false`.
  ///
  /// The canonical use — direction-aware double-tap seek:
  ///
  /// ```dart
  /// LayoutBuilder(
  ///   builder: (context, constraints) => MediaPlayerWidget(
  ///     controller: controller,
  ///     onDoubleTapDown: (details) {
  ///       // constraints.maxWidth is the player's own width — the correct
  ///       // denominator for localPosition, unlike the screen width.
  ///       final isLeftHalf =
  ///           details.localPosition.dx < constraints.maxWidth / 2;
  ///       final target = isLeftHalf
  ///           ? controller.position - const Duration(seconds: 10)
  ///           : controller.position + const Duration(seconds: 10);
  ///       controller.seekTo(target < Duration.zero ? Duration.zero : target);
  ///     },
  ///   ),
  /// )
  /// ```
  final GestureTapDownCallback? onDoubleTapDown;

  /// Callback when the player widget is long-pressed.
  ///
  /// Carries no position.  Use [onLongPressStart] when the press location
  /// matters (e.g. press-and-hold-on-the-right-edge to fast-forward).
  ///
  /// Fires for a long press that no widget inside the controls overlay
  /// claimed. Never invoked when [enableBuiltInGestures] is `false`.
  ///
  /// Unlike tap and double tap, long press is **not** forwarded to the
  /// built-in controls' background: while the default [MediaControls] overlay
  /// is visible it covers the whole surface, so a long press over it is
  /// absorbed by the overlay and this callback does not fire. It fires
  /// whenever the overlay is hidden, and — with [customControls] — whenever
  /// the host's overlay does not claim the press.
  final VoidCallback? onLongPress;

  /// Position-carrying counterpart of [onLongPress].
  ///
  /// Invoked when a long press is recognized, with a
  /// [LongPressStartDetails] whose `localPosition` is measured from the
  /// top-left of the player's own box.  Fires *before* [onLongPress] when
  /// both are supplied, and shares [onLongPress]'s overlay caveat above.
  final GestureLongPressStartCallback? onLongPressStart;

  /// Whether the package installs its own tap / double-tap / long-press
  /// handling over the video surface.
  ///
  /// Defaults to `true`, which is the historical behavior: a transparent,
  /// full-surface [GestureDetector] is stacked above the native platform view
  /// (`AndroidView` / `UiKitView`) — which would otherwise swallow pointers —
  /// and **below** the controls overlay, so it only receives gestures that no
  /// widget in the overlay claimed. It maps tap → [MediaController.toggleControls]
  /// (or [onTap]/[onTapDown]) and double tap → [MediaController.togglePlayPause]
  /// (or [onDoubleTap]/[onDoubleTapDown]).
  ///
  /// Set to `false` when you supply [customControls] and want to own every
  /// gesture yourself. The detector is then not mounted at all and [onTap],
  /// [onTapDown], [onDoubleTap], [onDoubleTapDown], [onLongPress] and
  /// [onLongPressStart] are never invoked by the package; the built-in
  /// controls' background tap handling is disabled too. Note that
  /// with no detector in the way, any pointer your overlay does not claim
  /// reaches the native platform view directly, so your overlay is
  /// responsible for covering the surface it cares about.
  final bool enableBuiltInGestures;

  /// Whether to allow fullscreen mode
  final bool allowFullscreen;

  /// Aspect ratio for the video (if null, uses video's natural aspect ratio)
  final double? aspectRatio;

  /// Whether to expand to fill all the space the parent offers, instead of
  /// sizing the player to an aspect ratio.
  ///
  /// When `true`, the widget does **not** wrap its content in an
  /// [AspectRatio] (unless [aspectRatio] is explicitly provided, which always
  /// wins): it is expected to be laid out by an ancestor that hands it a
  /// definite size — for example a [Positioned.fill] inside a [Stack], a
  /// [SizedBox.expand], or any tightly-constrained parent.
  ///
  /// **Constraint requirement.** `expandToFill: true` needs constraints that
  /// are bounded *and* have a non-zero minimum in both axes. If the incoming
  /// constraints are loose (a non-positioned [Stack] child gets
  /// `BoxConstraints.loose`), zero-minimum, or unbounded in an axis (an
  /// unbounded [Column]/[ListView] child), a fill-everything layout has no
  /// intrinsic size and would silently collapse to zero — a black screen with
  /// no exception, taking the controls overlay down with it.
  ///
  /// **Fallback.** Rather than collapse, the widget falls back to a definite
  /// size derived from the video's natural aspect ratio (16:9 when unknown):
  /// the bounded axis is filled and the other axis is computed from that
  /// ratio; when both axes are unbounded, the screen width is used. In debug
  /// builds this fallback also reports a [FlutterError] describing the
  /// offending constraints and the remedy ([Positioned.fill],
  /// [SizedBox.expand], or `expandToFill: false`). The report is emitted at
  /// most once per state, and never throws in release builds.
  ///
  /// Defaults to `false`, which always applies the natural aspect ratio and is
  /// therefore immune to loose constraints.
  final bool expandToFill;

  /// Whether this widget's State should be kept alive by
  /// [AutomaticKeepAliveClientMixin] when it would otherwise be removed
  /// from the tree (e.g. scrolled out of a scrollable's cache extent).
  ///
  /// Defaults to `true`, matching a standalone player embedded in a
  /// scrollable page (e.g. a video at the top of an article), where keeping
  /// the native decoder/platform view alive across small scroll
  /// adjustments is desirable.
  ///
  /// [MediaListPlayer] explicitly passes `false` here: in a feed of many
  /// players, unconditionally keeping every item's State (and therefore its
  /// native decoder/platform view) alive forever once mounted — regardless
  /// of how far it has scrolled out of view — is what causes the live
  /// decoder count to track every item ever scrolled past instead of only
  /// the currently-visible ones. A `false` value lets Flutter actually
  /// dispose the State once the item leaves the scrollable's cache extent.
  final bool wantKeepAlive;

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
    this.onTapDown,
    this.onDoubleTap,
    this.onDoubleTapDown,
    this.onLongPress,
    this.onLongPressStart,
    this.enableBuiltInGestures = true,
    this.allowFullscreen = true,
    this.aspectRatio,
    this.expandToFill = false,
    this.wantKeepAlive = true,
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

  /// Keep alive, configurable via [MediaPlayerWidget.wantKeepAlive] — see
  /// its doc comment for why list usage (MediaListPlayer) needs `false`.
  @override
  bool get wantKeepAlive => widget.wantKeepAlive;

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
    } else {
      // expandToFill: fill the parent when it hands us a definite size, but
      // never collapse to zero when it does not (see _buildExpandToFill).
      content = _buildExpandToFill(content);
    }

    return Container(
      color: widget.backgroundColor,
      child: content,
    );
  }

  // ---------------------------------------------------------------------------
  // expandToFill layout
  // ---------------------------------------------------------------------------

  /// Width used as a last resort when the incoming constraints are unbounded
  /// in *both* axes and no [MediaQuery] size is available. Chosen as a common
  /// phone-ish logical width so the player is visible rather than absent.
  static const double _kUnboundedFallbackWidth = 640.0;

  /// Whether the loose/unbounded-constraints diagnostic has already been
  /// reported for the current constraint condition. Reset as soon as the
  /// widget is laid out with definite constraints again, so the report is
  /// emitted on condition changes rather than once per frame.
  bool _reportedCollapsibleConstraints = false;

  /// Builds the `expandToFill: true` subtree.
  ///
  /// When the parent supplies a definite size (bounded with a non-zero
  /// minimum in both axes — which includes every tight constraint, e.g.
  /// `Positioned.fill`, `SizedBox.expand`, a `Scaffold` body) the content is
  /// returned untouched and fills exactly as before.
  ///
  /// When the parent supplies constraints that would let the widget collapse
  /// — loose / zero-minimum (a non-positioned `Stack` child) or unbounded in
  /// an axis (an unbounded `Column`/`ListView` child) — a definite size is
  /// derived from the video's natural aspect ratio so the player (and its
  /// controls overlay) can never silently paint nothing.
  Widget _buildExpandToFill(Widget content) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_constraintsAreDefinite(constraints)) {
          // Intended usage: fill exactly, unchanged.
          _reportedCollapsibleConstraints = false;
          return content;
        }

        final aspectRatio = _getVideoAspectRatio();
        final size = _fallbackSize(context, constraints, aspectRatio);
        _reportCollapsibleConstraints(constraints, size);

        return SizedBox(
          width: size.width,
          height: size.height,
          child: content,
        );
      },
    );
  }

  /// Whether [constraints] give the widget a definite size on their own.
  ///
  /// True for tight constraints, and for any constraints that are bounded
  /// with a non-zero minimum in both axes. False for loose/zero-minimum or
  /// unbounded constraints, which is exactly when a fill-everything layout
  /// has no intrinsic size.
  static bool _constraintsAreDefinite(BoxConstraints constraints) {
    // A tight constraint is always definite — including a deliberate tight
    // zero (e.g. SizedBox.shrink), which is the parent's explicit choice and
    // must not be second-guessed or warned about.
    if (constraints.isTight) return true;

    final widthIsDefinite =
        constraints.hasBoundedWidth && constraints.minWidth > 0;
    final heightIsDefinite =
        constraints.hasBoundedHeight && constraints.minHeight > 0;
    return widthIsDefinite && heightIsDefinite;
  }

  /// Computes the size floor used when [constraints] would let the widget
  /// collapse: fill the bounded axis and derive the other from [aspectRatio].
  Size _fallbackSize(
    BuildContext context,
    BoxConstraints constraints,
    double aspectRatio,
  ) {
    double width;
    double height;

    if (constraints.hasBoundedWidth && constraints.maxWidth > 0) {
      width = constraints.maxWidth;
      height = width / aspectRatio;
      // Never overflow a bounded height: re-derive from the height instead.
      if (constraints.hasBoundedHeight && height > constraints.maxHeight) {
        height = constraints.maxHeight;
        width = height * aspectRatio;
      }
    } else if (constraints.hasBoundedHeight && constraints.maxHeight > 0) {
      // Unbounded width (e.g. an unbounded Row child): derive from height.
      height = constraints.maxHeight;
      width = height * aspectRatio;
    } else {
      // Unbounded in both axes: nothing in the constraints to derive from,
      // so fall back to the screen width.
      final screenWidth = MediaQuery.maybeSizeOf(context)?.width;
      width = (screenWidth != null && screenWidth.isFinite && screenWidth > 0)
          ? screenWidth
          : _kUnboundedFallbackWidth;
      height = width / aspectRatio;
    }

    // Respect any non-zero minimums / bounded maximums the parent did set.
    return constraints.constrain(Size(width, height));
  }

  /// Debug-only diagnostic emitted when the size floor engages.
  ///
  /// Compiled out of release builds (the whole body runs inside an `assert`),
  /// never throws, and reports at most once per constraint condition so it
  /// cannot spam once per frame.
  void _reportCollapsibleConstraints(BoxConstraints constraints, Size size) {
    assert(() {
      if (_reportedCollapsibleConstraints) return true;
      _reportedCollapsibleConstraints = true;

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary(
              'MediaPlayerWidget(expandToFill: true) was given constraints '
              'that do not define a size.',
            ),
            ErrorDescription(
              'expandToFill: true intentionally skips the AspectRatio wrapper, '
              'so the widget has no intrinsic size and relies on an ancestor '
              'to give it one. The incoming constraints were $constraints, '
              'which are loose, zero-minimum or unbounded in at least one '
              'axis, so the player would have collapsed to zero size — a '
              'black screen (taking the controls overlay with it) with no '
              'exception at all.',
            ),
            ErrorDescription(
              'The usual causes are a non-positioned Stack child (Stack passes '
              'BoxConstraints.loose to those) and an unbounded Column / '
              'ListView / SingleChildScrollView child.',
            ),
            ErrorHint(
              'Wrap the MediaPlayerWidget in Positioned.fill (inside a Stack), '
              'SizedBox.expand, or an Expanded/SizedBox with a definite size — '
              'or use expandToFill: false to size the player from the video '
              'aspect ratio.',
            ),
            ErrorDescription(
              'As a fallback the player has been laid out at $size, derived '
              'from the video aspect ratio, instead of collapsing.',
            ),
          ]),
          library: 'zmedia_player',
          context: ErrorDescription('while laying out MediaPlayerWidget'),
        ),
      );
      return true;
    }());
  }

  /// Builds the interactive stack: video content, subtitles, the built-in tap
  /// detector, and the controls overlay.
  ///
  /// ## Gesture ownership rule
  ///
  /// A gesture is handled by the topmost widget in the controls overlay that
  /// claims it, and only reaches the package's built-in tap detector when no
  /// widget in the overlay claimed it — regardless of whether the overlay is
  /// currently visible.
  ///
  /// Two structural decisions make that rule hold:
  ///
  /// 1. **The controls overlay is always mounted** (previously it was not
  ///    built at all while [MediaController.controlsVisible] was `false`).
  ///    Host-supplied [MediaPlayerWidget.customControls] therefore keep their
  ///    own gesture recognizers alive across an auto-hide, instead of being
  ///    torn out of the tree and silently replaced by the package's detector
  ///    (issue #84). The *built-in* controls are additionally wrapped in
  ///    `ExcludeSemantics` + `IgnorePointer` + a zero opacity while hidden, so
  ///    they remain exactly as untappable and as invisible to screen readers
  ///    as when they were unmounted — see [_buildControlsOverlay].
  ///
  /// 2. **The built-in tap detector is stacked below the overlay.** `Stack`
  ///    hit-tests its children topmost-first and stops at the first child that
  ///    claims the pointer, so putting the detector *under* the overlay gives
  ///    overlay recognizers deterministic priority — no gesture-arena race.
  ///    (Making the detector `translucent` and leaving it on top would *not*
  ///    work: arena members are added in hit-test order and ties are resolved
  ///    in favour of the first member, so a topmost detector would beat both
  ///    host zones and the built-in controls' own buttons.)
  ///
  /// The detector keeps [HitTestBehavior.opaque] because that is what stops
  /// the native platform view (`AndroidView` / `UiKitView`) beneath it from
  /// consuming the pointer — its original and still-valid purpose. Opacity
  /// only affects what is *below* the detector, never what is above it.
  Widget _buildInteractiveContent(Widget content) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Video content - ensure it fills the available space
            Positioned.fill(child: content),

            // Subtitle overlay - show when subtitles are enabled
            if (widget.controller.config.enableSubtitles == true)
              _buildSubtitleOverlay(),

            // Transparent tap detector - sits ABOVE the native view (so taps
            // are captured even when the platform view would otherwise consume
            // them) but BELOW the controls overlay (so overlay-owned gestures,
            // including host-defined zones inside customControls, always win).
            if (widget.enableBuiltInGestures)
              Positioned.fill(
                child: GestureDetector(
                  // Position-carrying variants are forwarded verbatim; they
                  // fire before their bare counterparts (GestureDetector's
                  // own ordering).  Supplying EITHER variant for a gesture
                  // means the host owns it, so the package default
                  // (_handleTap / _handleDoubleTap) is suppressed — see the
                  // "Gesture callbacks" section of the MediaPlayerWidget
                  // class docs.
                  onTapDown: widget.onTapDown,
                  onTap: widget.onTap ??
                      (widget.onTapDown == null ? _handleTap : null),
                  onDoubleTapDown: widget.onDoubleTapDown,
                  onDoubleTap: widget.onDoubleTap ??
                      (widget.onDoubleTapDown == null
                          ? _handleDoubleTap
                          : null),
                  onLongPressStart: widget.onLongPressStart,
                  onLongPress: widget.onLongPress,
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),

            // Controls overlay - always mounted so host gestures survive the
            // overlay auto-hiding; visibility/pointer/semantics gating for the
            // built-in controls happens inside _buildControlsOverlay().
            if (widget.showControls)
              Positioned.fill(child: _buildControlsOverlay()),
          ],
        );
      },
    );
  }

  /// Build subtitle overlay
  ///
  /// This is built inside `_buildInteractiveContent`'s outer
  /// `ListenableBuilder(listenable: widget.controller)`, which intentionally
  /// does NOT rebuild on position-only changes (MediaController routes
  /// those through the dedicated `positionListenable` instead of
  /// `notifyListeners()` -- see `MediaController.positionListenable`).
  /// Subtitle cues still need to track playback position every tick, so
  /// this widget listens to `positionListenable` directly rather than
  /// relying on the outer rebuild, keeping subtitle timing accurate without
  /// re-triggering a rebuild of the whole video surface/controls
  /// overlay/tap-detector stack on every ~500ms tick.
  Widget _buildSubtitleOverlay() {
    if (widget.controller.currentItem == null) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.controller.positionListenable,
      builder: (context, position, _) {
        return SubtitleView(
          subtitleService: _subtitleService,
          position: position,
          config:
              widget.controller.config.subtitleConfig ?? const SubtitleConfig(),
          enabled: widget.controller.config.enableSubtitles,
          onTrackChanged: (_) {
            // Subtitle track change is handled internally by SubtitleView
          },
        );
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
        // True Hybrid Composition via PlatformViewLink + initExpensiveAndroidView.
        // This avoids VirtualDisplayController entirely, eliminating the
        // getRenderTargetWidth → getWidth()-on-null NPE that occurs when a resize
        // is posted to the platform Handler after the SurfaceProducer is released
        // on fullscreen exit.  TLHC (initSurfaceAndroidView) is intentionally NOT
        // used here — it renders via texture and cannot capture the ExoPlayer
        // SurfaceView, producing black video.
        nativeView = PlatformViewLink(
          viewType: viewType,
          surfaceFactory: (context, controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<
                  OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            );
          },
          onCreatePlatformView: (params) {
            final controller = PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params.onFocusChanged(true),
            );
            controller
                .addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
            // Preserve the re-attach hook: reclaimVideoSurface + setBoxFit.
            controller.addOnPlatformViewCreatedListener(_onPlatformViewCreated);
            controller.create();
            return controller;
          },
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
    // Host-supplied controls: the package neither hides nor gates them.  They
    // stay mounted and hit-testable at all times so their own recognizers keep
    // working while the overlay is hidden; the host drives visibility from
    // MediaController.controlsVisible.  See MediaPlayerWidget.customControls.
    if (widget.customControls != null) {
      return widget.customControls!;
    }

    final visible = widget.controller.controlsVisible;

    // Built-in controls: mounted at all times (so the fade-out can actually
    // run, and so the stack order above stays stable), but while hidden they
    // are removed from the semantics tree, made non-hit-testable, and faded to
    // zero — i.e. observationally identical to not being built at all.
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: MediaControls(
            controller: widget.controller,
            allowFullscreen: widget.allowFullscreen,
            // Keep the host callbacks firing consistently: while the built-in
            // overlay is visible it covers the whole surface, so the tap
            // detector below never sees the pointer.  Forwarding the same
            // callbacks to the overlay's background means a tap/double-tap on
            // empty overlay space behaves exactly as it does while hidden --
            // including the position-carrying variants, because the overlay's
            // background detector fills the same box as the tap detector
            // below it, so `localPosition` is identical on both paths.
            //
            // The suppression rule is mirrored verbatim: supplying EITHER
            // variant means the host owns the gesture, so the package default
            // (showControlsTemporarily / _handleDoubleTap) does not also run.
            onBackgroundTapDown:
                widget.enableBuiltInGestures ? widget.onTapDown : null,
            onBackgroundTap: widget.enableBuiltInGestures ? widget.onTap : null,
            onBackgroundDoubleTapDown:
                widget.enableBuiltInGestures ? widget.onDoubleTapDown : null,
            onBackgroundDoubleTap: widget.enableBuiltInGestures
                ? (widget.onDoubleTap ??
                    (widget.onDoubleTapDown == null ? _handleDoubleTap : null))
                : null,
          ),
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

  /// Forwarded to [MediaPlayerWidget.enableBuiltInGestures].
  ///
  /// Set to `false` alongside [customControls] to let the host own every
  /// gesture on the video surface.
  final bool enableBuiltInGestures;

  /// Background color
  final Color backgroundColor;

  /// Preferred device orientations while fullscreen is active.
  ///
  /// When null the widget preserves the original behavior: it locks to
  /// `[landscapeLeft, landscapeRight]`.  Pass a custom list to allow portrait
  /// fullscreen, free rotation, or any other set.
  ///
  /// Ignored while [rotationLocked] is non-null and its value is `true`.
  final List<DeviceOrientation>? preferredOrientations;

  /// Live rotation-lock signal.
  ///
  /// When non-null and its current value is `true`, the device is pinned to
  /// `[DeviceOrientation.portraitUp]` regardless of [preferredOrientations].
  /// When the value flips to `false`, [preferredOrientations] (or the default
  /// landscape pair) is re-applied immediately.  The widget subscribes in
  /// `initState` and unsubscribes in `dispose`.
  final ValueListenable<bool>? rotationLocked;

  /// Orientations to restore when the fullscreen player exits.
  ///
  /// Defaults to all four — matching the original hard-coded behavior.  A
  /// portrait-locked app can pass `[DeviceOrientation.portraitUp]` to avoid
  /// briefly unlocking landscape on exit.
  final List<DeviceOrientation> exitOrientations;

  const FullscreenMediaPlayer({
    super.key,
    required this.controller,
    this.customControls,
    this.enableBuiltInGestures = true,
    this.backgroundColor = Colors.black,
    this.preferredOrientations,
    this.rotationLocked,
    this.exitOrientations = const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
  });

  @override
  State<FullscreenMediaPlayer> createState() => _FullscreenMediaPlayerState();
}

class _FullscreenMediaPlayerState extends State<FullscreenMediaPlayer>
    with WidgetsBindingObserver {
  bool _isDisposed = false;

  // ---------------------------------------------------------------------------
  // Orientation helpers
  // ---------------------------------------------------------------------------

  /// Returns the orientation list that should be active right now.
  ///
  /// Priority order:
  ///   1. If [FullscreenMediaPlayer.rotationLocked] is non-null and `true`
  ///      → pin to portrait.
  ///   2. [FullscreenMediaPlayer.preferredOrientations] when non-null.
  ///   3. Original default: landscape pair.
  List<DeviceOrientation> _computeOrientations() {
    if (widget.rotationLocked?.value ?? false) {
      return const [DeviceOrientation.portraitUp];
    }
    return widget.preferredOrientations ??
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
  }

  /// Called whenever [FullscreenMediaPlayer.rotationLocked] changes value.
  void _onRotationLockChanged() {
    if (!_isDisposed) {
      _enterFullscreen();
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Subscribe to the live rotation-lock signal if one was provided.
    widget.rotationLocked?.addListener(_onRotationLockChanged);

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

    // Unsubscribe from the rotation-lock listenable before tearing down.
    widget.rotationLocked?.removeListener(_onRotationLockChanged);

    WidgetsBinding.instance.removeObserver(this);

    // Restore system UI and orientation.
    // NOTE: _exitFullscreen guards on _isDisposed, so it returns early here.
    // The actual restore on normal navigation happens via the PopScope callback
    // below (where _isDisposed is still false at call time).
    _exitFullscreen();
    super.dispose();
  }

  Future<void> _enterFullscreen() async {
    if (_isDisposed) return;

    try {
      // Set fullscreen mode
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // Apply the computed orientation set (respects preferredOrientations and
      // the live rotationLocked signal).
      await SystemChrome.setPreferredOrientations(_computeOrientations());
    } catch (_) {
      // Ignore system UI / orientation errors on platforms that do not support them
    }
  }

  Future<void> _exitFullscreen() async {
    if (_isDisposed) return;

    try {
      // Restore system UI
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // Restore the caller-supplied orientations (defaults to all four, matching
      // the original hard-coded behavior).
      await SystemChrome.setPreferredOrientations(widget.exitOrientations);
    } catch (_) {
      // Ignore system UI / orientation errors on platforms that do not support them
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && !_isDisposed) {
      // Re-enter fullscreen mode when app resumes, re-applying computed
      // orientations (including any rotationLocked state).
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
                enableBuiltInGestures: widget.enableBuiltInGestures,
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

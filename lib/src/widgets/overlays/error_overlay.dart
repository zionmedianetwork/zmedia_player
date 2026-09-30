/// Comprehensive error overlay widget for media player
///
/// Displays user-friendly error messages with actionable recovery steps
/// based on the type of error encountered. Supports all exception types
/// from the MediaPlayerException hierarchy.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/exceptions.dart';
import '../../core/media_controller.dart';

/// Error category for UI presentation
enum ErrorCategory {
  network,
  drm,
  playback,
  configuration,
  state,
  platform,
  unknown,
}

/// Error overlay widget with type-specific messaging and recovery actions
///
/// Provides a comprehensive error UI with:
/// - Error type-specific messages and icons
/// - User-friendly explanations
/// - Actionable recovery buttons (retry, check network, report)
/// - Optional error codes for debugging/support ([showErrorCode], off by
///   default — it is a developer diagnostic, not viewer copy)
/// - Animated error states
///
/// Example usage:
/// ```dart
/// if (controller.hasError) {
///   ErrorOverlay(
///     error: controller.error, // the typed MediaPlayerException
///     onRetry: () {
///       final item = controller.currentItem;
///       if (item != null) controller.load(item);
///     },
///     onDismiss: () => Navigator.of(context).pop(),
///   )
/// }
/// ```
///
/// **Raw platform or exception text is never shown.** An error that maps to
/// no known category (an unmatched `String`, or an unrecognized exception)
/// renders [genericMessage]; the raw text is written to the debug log only
/// (`debugPrint`, debug builds). Pass the typed exception
/// (`MediaController.error`) rather than `PlaybackState.errorMessage` to get
/// category-specific wording.
class ErrorOverlay extends StatefulWidget {
  /// Message shown when the error cannot be mapped to a specific category.
  static const String genericMessage =
      'Something went wrong playing this video. Please try again.';

  /// Message for an HTTP 403 / "unauthorized" failure. On signed CDN URLs a
  /// 403 is nearly always an expired credential that a retry fixes, so it is
  /// worded as retryable rather than as a permanent permission problem.
  static const String retryableAccessMessage =
      'We couldn\'t load this video right now. Please try again.';

  /// The error to display: a [MediaPlayerException] (preferred — category
  /// mapping runs) or a `String`. Never rendered verbatim.
  final Object? error;

  /// Media controller for retry operations
  final MediaController? controller;

  /// Callback when user taps retry button
  final VoidCallback? onRetry;

  /// Callback when user dismisses the error
  final VoidCallback? onDismiss;

  /// Callback when user requests to check network
  final VoidCallback? onCheckNetwork;

  /// Callback when user wants to report the issue
  final VoidCallback? onReportIssue;

  /// Support contact information
  final String? supportEmail;

  /// Support website URL
  final String? supportUrl;

  /// Whether to show a developer-facing "Error Code:" chip (DRM/playback
  /// error code or `HTTP <status>`). Defaults to `false`: the chip is a
  /// diagnostic, not viewer copy. Hosts may opt in (e.g. in debug builds).
  final bool showErrorCode;

  /// Whether to show support contact info
  final bool showSupportInfo;

  /// Custom background color
  final Color? backgroundColor;

  /// Whether to show animated error icon
  final bool animated;

  const ErrorOverlay({
    super.key,
    required this.error,
    this.controller,
    this.onRetry,
    this.onDismiss,
    this.onCheckNetwork,
    this.onReportIssue,
    this.supportEmail,
    this.supportUrl,
    this.showErrorCode = false,
    this.showSupportInfo = false,
    this.backgroundColor,
    this.animated = true,
  });

  @override
  State<ErrorOverlay> createState() => _ErrorOverlayState();
}

class _ErrorOverlayState extends State<ErrorOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _iconAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _logRawError();
  }

  @override
  void didUpdateWidget(ErrorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error != widget.error) _logRawError();
  }

  /// Raw platform/exception text is diagnostics: debug log only, never UI.
  void _logRawError() {
    final error = widget.error;
    if (kDebugMode && error != null) {
      debugPrint('ErrorOverlay: $error');
    }
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
      ),
    );

    _iconAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 1.0, curve: Curves.elasticOut),
      ),
    );

    if (widget.animated) {
      _animationController.forward();
    } else {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  ErrorCategory _getErrorCategory() {
    final error = widget.error;
    if (error is NetworkException) return ErrorCategory.network;
    if (error is DrmException) return ErrorCategory.drm;
    if (error is PlaybackException) return ErrorCategory.playback;
    if (error is ConfigurationException) return ErrorCategory.configuration;
    if (error is InvalidStateException || error is PlayerDisposedException) {
      return ErrorCategory.state;
    }
    if (error is PlatformOperationException || error is MediaLoadException) {
      return ErrorCategory.platform;
    }
    return ErrorCategory.unknown;
  }

  IconData _getErrorIcon() {
    switch (_getErrorCategory()) {
      case ErrorCategory.network:
        return Icons.wifi_off;
      case ErrorCategory.drm:
        return Icons.lock_outline;
      case ErrorCategory.playback:
        return Icons.play_disabled;
      case ErrorCategory.configuration:
        return Icons.settings_suggest;
      case ErrorCategory.state:
        return Icons.warning_amber;
      case ErrorCategory.platform:
        return Icons.error_outline;
      case ErrorCategory.unknown:
        return Icons.help_outline;
    }
  }

  Color _getErrorColor() {
    switch (_getErrorCategory()) {
      case ErrorCategory.network:
        return Colors.orange;
      case ErrorCategory.drm:
        return Colors.red;
      case ErrorCategory.playback:
        return Colors.deepOrange;
      case ErrorCategory.configuration:
        return Colors.amber;
      case ErrorCategory.state:
        return Colors.yellow.shade700;
      case ErrorCategory.platform:
        return Colors.red.shade700;
      case ErrorCategory.unknown:
        return Colors.grey;
    }
  }

  String _getUserFriendlyTitle() {
    final error = widget.error;

    // Handle plain string errors
    if (error is String) {
      if (error.toLowerCase().contains('network') ||
          error.toLowerCase().contains('connection') ||
          error.toLowerCase().contains('offline')) {
        return 'Network Error';
      }
      if (error.toLowerCase().contains('drm') ||
          error.toLowerCase().contains('license')) {
        return 'Protected Content Error';
      }
      if (error.toLowerCase().contains('not found')) {
        return 'Media Not Found';
      }
      if (error.toLowerCase().contains('unauthorized') ||
          error.toLowerCase().contains('403')) {
        return 'Failed to Load Media';
      }
      return 'Playback Error';
    }

    if (error is NetworkException) {
      if (error.isOffline) return 'No Internet Connection';
      if (error.isTimeout) return 'Connection Timeout';
      return 'Network Error';
    }
    if (error is DrmException) {
      if (error.isLicenseError) return 'Content License Error';
      if (error.isCertificateError) return 'DRM Certificate Error';
      return 'Protected Content Error';
    }
    if (error is PlaybackException) return 'Playback Failed';
    if (error is MediaLoadException) return 'Failed to Load Media';
    if (error is ConfigurationException) return 'Configuration Error';
    if (error is InvalidStateException) return 'Invalid Operation';
    if (error is PlayerDisposedException) return 'Player Not Available';
    if (error is PlatformOperationException) return 'Platform Error';
    return 'An Error Occurred';
  }

  String _getUserFriendlyMessage() {
    final error = widget.error;

    // Handle plain string errors (fallback when exception object not available)
    if (error is String) {
      if (error.toLowerCase().contains('network') ||
          error.toLowerCase().contains('connection') ||
          error.toLowerCase().contains('offline')) {
        return 'A network error occurred. Please check your internet connection and try again.';
      }
      if (error.toLowerCase().contains('drm') ||
          error.toLowerCase().contains('license')) {
        return 'This content is protected and cannot be played at this time.';
      }
      if (error.toLowerCase().contains('not found') ||
          error.toLowerCase().contains('404')) {
        return 'The requested media could not be found.';
      }
      if (error.toLowerCase().contains('unauthorized') ||
          error.toLowerCase().contains('403')) {
        return ErrorOverlay.retryableAccessMessage;
      }
      // Unmatched: never echo raw platform text (issue #135).
      return ErrorOverlay.genericMessage;
    }

    if (error is NetworkException) {
      if (error.isOffline) {
        return 'Please check your internet connection and try again.';
      }
      if (error.isTimeout) {
        return 'The connection took too long to respond. Please check your network and try again.';
      }
      return 'A network error occurred while trying to play the video. Please check your connection.';
    }

    if (error is DrmException) {
      if (error.isLicenseError) {
        return 'Unable to acquire a license to play this protected content. This may be due to regional restrictions or subscription requirements.';
      }
      if (error.isCertificateError) {
        return 'There was a problem verifying your device for protected content playback. Please try updating your app.';
      }
      return 'This content is protected and cannot be played on your device at this time.';
    }

    if (error is PlaybackException) {
      return 'The video cannot be played due to a playback error. This may be caused by an unsupported format or corrupted media.';
    }

    if (error is MediaLoadException) {
      if (error.statusCode == 404) {
        return 'The requested media could not be found. It may have been moved or deleted.';
      }
      if (error.statusCode == 403) {
        return ErrorOverlay.retryableAccessMessage;
      }
      if (error.statusCode == 500 || error.statusCode == 503) {
        return 'The server is experiencing issues. Please try again later.';
      }
      return 'Unable to load the media. Please check the URL and try again.';
    }

    if (error is ConfigurationException) {
      return 'There\'s a problem with the player configuration. Please contact support if this persists.';
    }

    if (error is InvalidStateException) {
      return 'This operation cannot be performed right now. Please try again.';
    }

    if (error is PlayerDisposedException) {
      return 'The media player is no longer available. Please refresh the page.';
    }

    if (error is PlatformOperationException) {
      return 'A platform-specific error occurred. This may be due to device limitations or system issues.';
    }

    // Unrecognized exception or arbitrary object: never echo raw text.
    return ErrorOverlay.genericMessage;
  }

  String? _getErrorCode() {
    if (!widget.showErrorCode) return null;

    final error = widget.error;
    if (error is DrmException) return error.errorCode;
    if (error is PlaybackException) return error.errorCode;
    if (error is MediaLoadException && error.statusCode != null) {
      return 'HTTP ${error.statusCode}';
    }
    if (error is PlatformOperationException) return error.code;
    return null;
  }

  List<Widget> _buildRecoveryActions() {
    final actions = <Widget>[];
    final category = _getErrorCategory();

    // Retry button - available for most errors
    if (widget.onRetry != null &&
        category != ErrorCategory.state &&
        category != ErrorCategory.configuration) {
      actions.add(
        _buildActionButton(
          icon: Icons.refresh,
          label: 'Retry',
          onPressed: widget.onRetry!,
          isPrimary: true,
        ),
      );
    }

    // Check network - for network errors
    if (widget.onCheckNetwork != null && category == ErrorCategory.network) {
      actions.add(
        _buildActionButton(
          icon: Icons.wifi_find,
          label: 'Check Network',
          onPressed: widget.onCheckNetwork!,
        ),
      );
    }

    // Report issue - always available
    if (widget.onReportIssue != null) {
      actions.add(
        _buildActionButton(
          icon: Icons.bug_report,
          label: 'Report Issue',
          onPressed: widget.onReportIssue!,
        ),
      );
    }

    // Dismiss button - always available
    if (widget.onDismiss != null) {
      actions.add(
        _buildActionButton(
          icon: Icons.close,
          label: 'Dismiss',
          onPressed: widget.onDismiss!,
        ),
      );
    }

    return actions;
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? _getErrorColor() : null,
        foregroundColor: isPrimary ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor =
        widget.backgroundColor ?? Colors.black.withValues(alpha: 0.9);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            color: backgroundColor,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, _slideAnimation.value),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated error icon
                      ScaleTransition(
                        scale: _iconAnimation,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getErrorColor().withValues(alpha: 0.2),
                          ),
                          child: Icon(
                            _getErrorIcon(),
                            size: 60,
                            color: _getErrorColor(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Error title
                      Text(
                        _getUserFriendlyTitle(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      // Error message
                      Text(
                        _getUserFriendlyMessage(),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // Error code (if available)
                      if (_getErrorCode() != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Error Code: ${_getErrorCode()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white60,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Recovery actions
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: _buildRecoveryActions(),
                      ),

                      // Support information
                      if (widget.showSupportInfo &&
                          (widget.supportEmail != null ||
                              widget.supportUrl != null)) ...[
                        const SizedBox(height: 32),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(
                          'Need Help?',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (widget.supportEmail != null)
                          Text(
                            'Email: ${widget.supportEmail}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white60,
                            ),
                          ),
                        if (widget.supportUrl != null)
                          Text(
                            'Support: ${widget.supportUrl}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white60,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact error badge for inline error display
///
/// Shows a minimal error indicator that can be expanded for details.
/// Useful for non-critical errors or when space is limited.
class CompactErrorBadge extends StatelessWidget {
  /// The error to display
  final Object? error;

  /// Callback when badge is tapped
  final VoidCallback? onTap;

  /// Size of the badge
  final double size;

  const CompactErrorBadge({
    super.key,
    required this.error,
    this.onTap,
    this.size = 32.0,
  });

  ErrorCategory _getErrorCategory() {
    if (error is NetworkException) return ErrorCategory.network;
    if (error is DrmException) return ErrorCategory.drm;
    if (error is PlaybackException) return ErrorCategory.playback;
    return ErrorCategory.unknown;
  }

  IconData _getErrorIcon() {
    switch (_getErrorCategory()) {
      case ErrorCategory.network:
        return Icons.wifi_off;
      case ErrorCategory.drm:
        return Icons.lock_outline;
      case ErrorCategory.playback:
        return Icons.play_disabled;
      default:
        return Icons.error_outline;
    }
  }

  Color _getErrorColor() {
    switch (_getErrorCategory()) {
      case ErrorCategory.network:
        return Colors.orange;
      case ErrorCategory.drm:
        return Colors.red;
      case ErrorCategory.playback:
        return Colors.deepOrange;
      default:
        return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _getErrorColor().withValues(alpha: 0.2),
          border: Border.all(
            color: _getErrorColor(),
            width: 2,
          ),
        ),
        child: Icon(
          _getErrorIcon(),
          size: size * 0.6,
          color: _getErrorColor(),
        ),
      ),
    );
  }
}

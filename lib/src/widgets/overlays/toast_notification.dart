import 'package:flutter/material.dart';
import 'feedback_overlay.dart';

/// Toast notification widget
///
/// Displays temporary toast-style notifications with:
/// - Customizable message
/// - Optional icon
/// - Auto-dismiss after duration
/// - Configurable position (top/center/bottom)
///
/// Example usage:
/// ```dart
/// ToastNotification(
///   message: 'Video saved to library',
///   icon: Icons.check_circle,
///   show: true,
/// )
/// ```
class ToastNotification extends StatelessWidget {
  /// Message to display
  final String message;

  /// Optional icon to show before message
  final IconData? icon;

  /// Whether to show the notification
  final bool show;

  /// How long to display the notification
  final Duration duration;

  /// Position of the toast
  final ToastPosition position;

  /// Toast severity level (affects styling)
  final ToastSeverity severity;

  /// Icon color (defaults based on severity)
  final Color? iconColor;

  /// Text color
  final Color? textColor;

  /// Background color of toast
  final Color? backgroundColor;

  /// Callback when toast is dismissed
  final VoidCallback? onDismiss;

  const ToastNotification({
    super.key,
    required this.message,
    this.icon,
    this.show = true,
    this.duration = const Duration(milliseconds: 2000),
    this.position = ToastPosition.bottom,
    this.severity = ToastSeverity.info,
    this.iconColor,
    this.textColor,
    this.backgroundColor,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _getColors(theme);

    return FeedbackOverlay(
      show: show,
      duration: duration,
      backgroundColor: backgroundColor ?? colors.background,
      alignment: _getAlignment(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      onDismiss: onDismiss,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon (if provided)
          if (icon != null) ...[
            Icon(
              icon,
              size: 24,
              color: iconColor ?? colors.icon,
            ),
            const SizedBox(width: 12),
          ],

          // Message
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor ?? colors.text,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Alignment _getAlignment() {
    switch (position) {
      case ToastPosition.top:
        return Alignment.topCenter;
      case ToastPosition.center:
        return Alignment.center;
      case ToastPosition.bottom:
        return Alignment.bottomCenter;
    }
  }

  _ToastColors _getColors(ThemeData theme) {
    switch (severity) {
      case ToastSeverity.success:
        return _ToastColors(
          background: const Color(0xFF4CAF50).withValues(alpha: 0.95),
          icon: Colors.white,
          text: Colors.white,
        );
      case ToastSeverity.error:
        return _ToastColors(
          background: const Color(0xFFF44336).withValues(alpha: 0.95),
          icon: Colors.white,
          text: Colors.white,
        );
      case ToastSeverity.warning:
        return _ToastColors(
          background: const Color(0xFFFF9800).withValues(alpha: 0.95),
          icon: Colors.white,
          text: Colors.white,
        );
      case ToastSeverity.info:
        return _ToastColors(
          background: theme.colorScheme.surface.withValues(alpha: 0.95),
          icon: theme.colorScheme.onSurface,
          text: theme.colorScheme.onSurface,
        );
    }
  }
}

/// Position of toast notification
enum ToastPosition {
  /// Top of screen
  top,

  /// Center of screen
  center,

  /// Bottom of screen
  bottom,
}

/// Severity level of toast notification
enum ToastSeverity {
  /// Success message (green)
  success,

  /// Error message (red)
  error,

  /// Warning message (orange)
  warning,

  /// Informational message (default theme colors)
  info,
}

/// Internal color scheme for toast
class _ToastColors {
  final Color background;
  final Color icon;
  final Color text;

  const _ToastColors({
    required this.background,
    required this.icon,
    required this.text,
  });
}

/// Action toast notification with button
///
/// Toast notification with an action button for user interaction.
///
/// Example usage:
/// ```dart
/// ActionToast(
///   message: 'Connection lost',
///   actionLabel: 'Retry',
///   onAction: () => retryConnection(),
///   show: true,
/// )
/// ```
class ActionToast extends StatelessWidget {
  /// Message to display
  final String message;

  /// Label for action button
  final String actionLabel;

  /// Callback when action button is pressed
  final VoidCallback onAction;

  /// Optional icon to show before message
  final IconData? icon;

  /// Whether to show the notification
  final bool show;

  /// How long to display before auto-dismiss (0 = no auto-dismiss)
  final Duration duration;

  /// Position of the toast
  final ToastPosition position;

  /// Icon color
  final Color? iconColor;

  /// Text color
  final Color? textColor;

  /// Action button color
  final Color? actionColor;

  /// Background color of toast
  final Color? backgroundColor;

  /// Callback when toast is dismissed
  final VoidCallback? onDismiss;

  const ActionToast({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.icon,
    this.show = true,
    this.duration = const Duration(seconds: 5),
    this.position = ToastPosition.bottom,
    this.iconColor,
    this.textColor,
    this.actionColor,
    this.backgroundColor,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = this.textColor ?? theme.colorScheme.onSurface;
    final actionColor = this.actionColor ?? theme.colorScheme.primary;

    return FeedbackOverlay(
      show: show,
      duration: duration,
      backgroundColor:
          backgroundColor ?? theme.colorScheme.surface.withValues(alpha: 0.95),
      alignment: _getAlignment(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onDismiss: onDismiss,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon (if provided)
          if (icon != null) ...[
            Icon(
              icon,
              size: 24,
              color: iconColor ?? textColor,
            ),
            const SizedBox(width: 12),
          ],

          // Message
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 16),

          // Action button
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: actionColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: actionColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Alignment _getAlignment() {
    switch (position) {
      case ToastPosition.top:
        return Alignment.topCenter;
      case ToastPosition.center:
        return Alignment.center;
      case ToastPosition.bottom:
        return Alignment.bottomCenter;
    }
  }
}

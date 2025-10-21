import 'package:flutter/foundation.dart';

/// Abstract crash reporter for integration with various crash reporting services
///
/// Implement this interface to connect ZMedia Player with your preferred
/// crash reporting service (Firebase Crashlytics, Sentry, etc.)
abstract class CrashReporter {
  /// Report an error with context
  ///
  /// [error] - The error object or message
  /// [stackTrace] - Optional stack trace
  /// [context] - Additional context information
  /// [fatal] - Whether this is a fatal error
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  });

  /// Log a message for debugging
  ///
  /// [message] - The log message
  /// [context] - Additional context information
  void log(String message, {Map<String, dynamic>? context});

  /// Set user identifier for crash reports
  ///
  /// [userId] - Unique identifier for the user
  void setUserIdentifier(String userId);

  /// Set custom key-value pairs
  ///
  /// [key] - The key name
  /// [value] - The value (will be converted to string)
  void setCustomKey(String key, dynamic value);
}

/// Built-in console-only crash reporter for development
///
/// This implementation only logs to console and doesn't persist crashes.
/// Use this during development or replace with a production crash reporter.
class ConsoleOnlyCrashReporter implements CrashReporter {
  @override
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  }) {
    debugPrint('🔴 ${fatal ? 'FATAL ' : ''}ERROR: $error');
    if (stackTrace != null) {
      debugPrint('Stack: $stackTrace');
    }
    if (context != null && context.isNotEmpty) {
      debugPrint('Context: $context');
    }
  }

  @override
  void log(String message, {Map<String, dynamic>? context}) {
    debugPrint('📝 LOG: $message');
    if (context != null && context.isNotEmpty) {
      debugPrint('Context: $context');
    }
  }

  @override
  void setUserIdentifier(String userId) {
    debugPrint('👤 User: $userId');
  }

  @override
  void setCustomKey(String key, dynamic value) {
    debugPrint('🔑 $key: $value');
  }
}

/// Example Firebase Crashlytics implementation
///
/// To use this:
/// 1. Add firebase_crashlytics to your pubspec.yaml
/// 2. Initialize Firebase in your app
/// 3. Create your own implementation based on this template
///
/// ```dart
/// // In main.dart
/// import 'package:firebase_crashlytics/firebase_crashlytics.dart';
///
/// class MyFirebaseCrashReporter implements CrashReporter {
///   @override
///   void reportError(error, stackTrace, {context, fatal = false}) {
///     FirebaseCrashlytics.instance.recordError(
///       error, stackTrace, fatal: fatal,
///       information: context?.entries.map((e) => '${e.key}: ${e.value}').toList(),
///     );
///   }
///
///   @override
///   void log(String message, {context}) {
///     FirebaseCrashlytics.instance.log(message);
///   }
///
///   @override
///   void setUserIdentifier(String userId) {
///     FirebaseCrashlytics.instance.setUserIdentifier(userId);
///   }
///
///   @override
///   void setCustomKey(String key, value) {
///     FirebaseCrashlytics.instance.setCustomKey(key, value);
///   }
/// }
///
/// // Then use it:
/// await Firebase.initializeApp();
/// MediaPlayer.enableCrashReporting(MyFirebaseCrashReporter());
/// ```

/// Example Sentry crash reporter implementation
///
/// To use this:
/// 1. Add sentry_flutter to your pubspec.yaml
/// 2. Initialize Sentry in your app
/// 3. Create your own implementation based on this template
///
/// ```dart
/// // In main.dart
/// import 'package:sentry_flutter/sentry_flutter.dart';
///
/// class MySentryCrashReporter implements CrashReporter {
///   @override
///   void reportError(error, stackTrace, {context, fatal = false}) {
///     Sentry.captureException(error, stackTrace: stackTrace);
///   }
///
///   @override
///   void log(String message, {context}) {
///     Sentry.addBreadcrumb(Breadcrumb(message: message, data: context));
///   }
///
///   @override
///   void setUserIdentifier(String userId) {
///     Sentry.configureScope((scope) {
///       scope.setUser(SentryUser(id: userId));
///     });
///   }
///
///   @override
///   void setCustomKey(String key, value) {
///     Sentry.configureScope((scope) {
///       scope.setTag(key, value.toString());
///     });
///   }
/// }
///
/// // Then use it:
/// await SentryFlutter.init((options) { options.dsn = 'your-dsn'; });
/// MediaPlayer.enableCrashReporting(MySentryCrashReporter());
/// ```

/// No-op crash reporter that does nothing
///
/// Use this when you want to disable crash reporting entirely
class NoOpCrashReporter implements CrashReporter {
  const NoOpCrashReporter();

  @override
  void reportError(
    dynamic error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? context,
    bool fatal = false,
  }) {
    // Do nothing
  }

  @override
  void log(String message, {Map<String, dynamic>? context}) {
    // Do nothing
  }

  @override
  void setUserIdentifier(String userId) {
    // Do nothing
  }

  @override
  void setCustomKey(String key, dynamic value) {
    // Do nothing
  }
}

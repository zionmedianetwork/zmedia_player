/// Network resilience and retry logic
///
/// Provides automatic retry with exponential backoff, network failure
/// handling, and auto-reconnect on network restoration. Ensures robust
/// playback under poor network conditions.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/network_status.dart';
import '../core/exceptions.dart';

/// Configuration for retry behavior
class RetryConfig {
  /// Maximum number of retry attempts
  final int maxRetries;

  /// Initial delay before first retry
  final Duration initialDelay;

  /// Multiplier for exponential backoff
  final double backoffMultiplier;

  /// Maximum delay between retries
  final Duration maxDelay;

  /// Whether to retry on network errors
  final bool retryOnNetworkError;

  /// Whether to retry on timeout errors
  final bool retryOnTimeout;

  /// Whether to retry on server errors (5xx)
  final bool retryOnServerError;

  const RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.retryOnNetworkError = true,
    this.retryOnTimeout = true,
    this.retryOnServerError = false,
  });

  /// Creates a configuration for aggressive retries
  factory RetryConfig.aggressive() {
    return const RetryConfig(
      maxRetries: 5,
      initialDelay: Duration(milliseconds: 500),
      backoffMultiplier: 1.5,
      maxDelay: Duration(seconds: 15),
    );
  }

  /// Creates a configuration for conservative retries
  factory RetryConfig.conservative() {
    return const RetryConfig(
      maxRetries: 2,
      initialDelay: Duration(seconds: 2),
      backoffMultiplier: 3.0,
      maxDelay: Duration(minutes: 1),
    );
  }

  /// Creates a configuration with no retries
  factory RetryConfig.noRetry() {
    return const RetryConfig(maxRetries: 0);
  }

  /// Calculates delay for a given attempt number
  Duration calculateDelay(int attemptNumber) {
    if (attemptNumber <= 0) return Duration.zero;

    final delayMs = initialDelay.inMilliseconds *
        (backoffMultiplier * (attemptNumber - 1));
    final delay = Duration(milliseconds: delayMs.toInt());

    return delay > maxDelay ? maxDelay : delay;
  }
}

/// Service for handling network failures and retry logic
class NetworkResilienceService {
  /// Current retry configuration
  RetryConfig _config;

  /// Current network status
  NetworkStatus _networkStatus = NetworkStatus.unknown();

  /// Network status stream controller
  final _networkStatusController = StreamController<NetworkStatus>.broadcast();

  /// Network change event stream controller
  final _networkChangeController =
      StreamController<NetworkChangeEvent>.broadcast();

  /// Whether service is monitoring network
  bool _isMonitoring = false;

  /// Active retry operations
  final Map<String, _RetryOperation> _activeRetries = {};

  /// Callback to fetch network status from platform
  final Future<Map<String, dynamic>> Function()? _platformNetworkStatusCallback;

  /// Timer for periodic network checks
  Timer? _monitoringTimer;

  NetworkResilienceService({
    RetryConfig? config,
    Future<Map<String, dynamic>> Function()? platformNetworkStatusCallback,
  })  : _config = config ?? const RetryConfig(),
        _platformNetworkStatusCallback = platformNetworkStatusCallback;

  /// Stream of network status updates
  Stream<NetworkStatus> get networkStatusStream =>
      _networkStatusController.stream;

  /// Stream of network change events
  Stream<NetworkChangeEvent> get networkChangeStream =>
      _networkChangeController.stream;

  /// Current network status
  NetworkStatus get networkStatus => _networkStatus;

  /// Current retry configuration
  RetryConfig get config => _config;

  /// Whether network is available
  bool get isNetworkAvailable => _networkStatus.isAvailable;

  /// Updates retry configuration
  void updateConfig(RetryConfig newConfig) {
    _config = newConfig;
    debugPrint('NetworkResilienceService: Config updated - $newConfig');
  }

  /// Updates current network status
  void updateNetworkStatus(NetworkStatus newStatus) {
    final previousStatus = _networkStatus;
    _networkStatus = newStatus;

    // Emit status update
    if (!_networkStatusController.isClosed) {
      _networkStatusController.add(newStatus);
    }

    // Emit change event
    final changeEvent = NetworkChangeEvent(
      previousStatus: previousStatus,
      currentStatus: newStatus,
    );

    if (!_networkChangeController.isClosed && changeEvent.isSignificant) {
      _networkChangeController.add(changeEvent);
      debugPrint('NetworkResilienceService: ${changeEvent.toString()}');
    }

    // Handle connection restoration
    if (changeEvent.connectionRestored) {
      _handleConnectionRestored();
    }
  }

  /// Starts monitoring network status
  void startMonitoring({Duration interval = const Duration(seconds: 5)}) {
    if (_isMonitoring) {
      debugPrint('NetworkResilienceService: Monitoring already active');
      return;
    }

    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(interval, (_) => _checkNetworkStatus());

    debugPrint(
      'NetworkResilienceService: Monitoring started (interval: $interval)',
    );

    // Initial check
    _checkNetworkStatus();
  }

  /// Stops monitoring network status
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;

    debugPrint('NetworkResilienceService: Monitoring stopped');
  }

  /// Executes an operation with automatic retry on failure
  Future<T> withRetry<T>(
    Future<T> Function() operation, {
    RetryConfig? config,
    String? operationId,
  }) async {
    final retryConfig = config ?? _config;
    final opId = operationId ?? DateTime.now().millisecondsSinceEpoch.toString();

    // Create retry operation tracker
    final retryOp = _RetryOperation(
      id: opId,
      config: retryConfig,
    );
    _activeRetries[opId] = retryOp;

    try {
      return await _executeWithRetry(operation, retryOp);
    } finally {
      _activeRetries.remove(opId);
    }
  }

  /// Handles a network failure
  Future<void> handleNetworkFailure(Exception error) async {
    debugPrint('NetworkResilienceService: Handling network failure - $error');

    // Update network status
    if (!_networkStatus.isAvailable) {
      return; // Already offline
    }

    // Check current network status
    await _checkNetworkStatus();

    // If still appears online, might be temporary glitch
    if (_networkStatus.isAvailable) {
      debugPrint('NetworkResilienceService: Network appears available, might be temporary issue');
    }
  }

  /// Checks if an error should trigger a retry
  bool shouldRetry(Exception error, int attemptCount) {
    if (attemptCount >= _config.maxRetries) {
      return false;
    }

    // Check if network is available
    if (!_networkStatus.isAvailable && _config.retryOnNetworkError) {
      return false; // Don't retry if offline
    }

    // Determine error type
    if (_isNetworkError(error) && _config.retryOnNetworkError) {
      return true;
    }

    if (_isTimeoutError(error) && _config.retryOnTimeout) {
      return true;
    }

    if (_isServerError(error) && _config.retryOnServerError) {
      return true;
    }

    return false;
  }

  /// Cancels all active retry operations
  void cancelAllRetries() {
    for (final retry in _activeRetries.values) {
      retry.cancel();
    }
    _activeRetries.clear();
    debugPrint('NetworkResilienceService: All retries cancelled');
  }

  /// Disposes the service
  void dispose() {
    stopMonitoring();
    cancelAllRetries();
    _networkStatusController.close();
    _networkChangeController.close();

    debugPrint('NetworkResilienceService: Disposed');
  }

  // Private methods

  Future<void> _checkNetworkStatus() async {
    if (_platformNetworkStatusCallback == null) {
      return;
    }

    try {
      final platformData = await _platformNetworkStatusCallback!();
      final status = NetworkStatus.fromPlatform(platformData);
      updateNetworkStatus(status);
    } catch (e) {
      debugPrint('NetworkResilienceService: Error checking network status - $e');
      updateNetworkStatus(NetworkStatus.unknown());
    }
  }

  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation,
    _RetryOperation retryOp,
  ) async {
    while (!retryOp.isCancelled) {
      try {
        final result = await operation();
        if (retryOp.attemptCount > 0) {
          debugPrint(
            'NetworkResilienceService: Operation succeeded after ${retryOp.attemptCount} retries',
          );
        }
        return result;
      } catch (e) {
        retryOp.attemptCount++;

        if (!shouldRetry(e as Exception, retryOp.attemptCount)) {
          debugPrint(
            'NetworkResilienceService: Not retrying after ${retryOp.attemptCount} attempts',
          );
          rethrow;
        }

        final delay = retryOp.config.calculateDelay(retryOp.attemptCount);
        debugPrint(
          'NetworkResilienceService: Retry ${retryOp.attemptCount}/${retryOp.config.maxRetries} '
          'after ${delay.inMilliseconds}ms',
        );

        await Future.delayed(delay);

        if (retryOp.isCancelled) {
          throw NetworkException(
            'Retry operation cancelled',
          );
        }
      }
    }

    throw NetworkException(
      'Retry operation cancelled',
    );
  }

  void _handleConnectionRestored() {
    debugPrint('NetworkResilienceService: Connection restored, checking pending operations');

    // Active retries will automatically continue
    // This is just for logging/tracking
    if (_activeRetries.isNotEmpty) {
      debugPrint(
        'NetworkResilienceService: ${_activeRetries.length} operations will retry',
      );
    }
  }

  bool _isNetworkError(Exception error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('unreachable');
  }

  bool _isTimeoutError(Exception error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('timeout') || errorString.contains('timed out');
  }

  bool _isServerError(Exception error) {
    final errorString = error.toString();
    // Check for 5xx HTTP status codes
    final match = RegExp(r'5\d{2}').firstMatch(errorString);
    return match != null;
  }
}

/// Internal tracker for retry operations
class _RetryOperation {
  final String id;
  final RetryConfig config;
  int attemptCount = 0;
  bool isCancelled = false;

  _RetryOperation({
    required this.id,
    required this.config,
  });

  void cancel() {
    isCancelled = true;
  }
}

/// Factory for creating NetworkResilienceService instances
class NetworkResilienceServiceFactory {
  /// Creates a service with default configuration
  static NetworkResilienceService createDefault() {
    return NetworkResilienceService(
      config: const RetryConfig(),
    );
  }

  /// Creates a service with aggressive retry
  static NetworkResilienceService createAggressive() {
    return NetworkResilienceService(
      config: RetryConfig.aggressive(),
    );
  }

  /// Creates a service with conservative retry
  static NetworkResilienceService createConservative() {
    return NetworkResilienceService(
      config: RetryConfig.conservative(),
    );
  }

  /// Creates a service with no retry
  static NetworkResilienceService createNoRetry() {
    return NetworkResilienceService(
      config: RetryConfig.noRetry(),
    );
  }

  /// Creates a service with custom configuration
  static NetworkResilienceService createCustom(RetryConfig config) {
    return NetworkResilienceService(config: config);
  }
}

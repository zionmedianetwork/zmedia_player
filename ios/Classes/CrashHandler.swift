import Foundation
import Flutter

/// Native crash handler for iOS
///
/// Catches and reports native-layer crashes to the Flutter layer,
/// which can then forward them to the configured crash reporter.
class CrashHandler {
    private let methodChannel: FlutterMethodChannel

    init(methodChannel: FlutterMethodChannel) {
        self.methodChannel = methodChannel
    }

    /// Wrap a potentially failing operation with crash reporting
    func wrapOperation<T>(
        operation: String,
        playerId: String,
        context: [String: Any] = [:],
        block: () throws -> T
    ) rethrows -> T {
        do {
            return try block()
        } catch {
            reportNativeError(
                operation: operation,
                playerId: playerId,
                error: error,
                context: context
            )
            throw error
        }
    }

    /// Wrap an async operation with crash reporting
    func wrapAsyncOperation<T>(
        operation: String,
        playerId: String,
        context: [String: Any] = [:],
        block: () async throws -> T
    ) async rethrows -> T {
        do {
            return try await block()
        } catch {
            reportNativeError(
                operation: operation,
                playerId: playerId,
                error: error,
                context: context
            )
            throw error
        }
    }

    /// Report a native error to Flutter layer
    private func reportNativeError(
        operation: String,
        playerId: String,
        error: Error,
        context: [String: Any]
    ) {
        print("CrashHandler: Native error in \(operation) for player \(playerId): \(error.localizedDescription)")

        var errorData: [String: Any] = [
            "operation": operation,
            "playerId": playerId,
            "error": error.localizedDescription,
            "errorType": String(describing: type(of: error)),
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]

        // Add context
        errorData.merge(context) { (_, new) in new }

        // Invoke method on Flutter side
        methodChannel.invokeMethod("onNativeError", arguments: errorData) { result in
            if let error = result as? FlutterError {
                print("CrashHandler: Failed to report error to Flutter: \(error.message ?? "Unknown")")
            }
        }
    }

    /// Report a non-fatal warning
    func reportWarning(
        operation: String,
        playerId: String,
        message: String,
        context: [String: Any] = [:]
    ) {
        print("CrashHandler: Warning in \(operation) for player \(playerId): \(message)")

        var warningData: [String: Any] = [
            "operation": operation,
            "playerId": playerId,
            "message": message,
            "level": "warning",
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]

        warningData.merge(context) { (_, new) in new }

        methodChannel.invokeMethod("onNativeWarning", arguments: warningData) { result in
            if let error = result as? FlutterError {
                print("CrashHandler: Failed to report warning: \(error.message ?? "Unknown")")
            }
        }
    }

    /// Log a debug message
    func logDebug(operation: String, playerId: String, message: String) {
        print("CrashHandler: [\(playerId)] \(operation): \(message)")
    }
}

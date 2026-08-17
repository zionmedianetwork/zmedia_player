import Foundation
import UIKit
import Flutter

/// B-12 (wave 2 security hardening): opt-in screen-capture *detection* for
/// iOS.
///
/// Unlike Android's `SecureSurfaceHandler` (`FLAG_SECURE`), iOS has no
/// public API to hard-block screen recording or AirPlay/screen mirroring of
/// arbitrary app content — Apple reserves that for a small set of
/// system-owned surfaces (e.g. password/payment text fields). The best this
/// handler can do is observe `UIScreen.isCaptured` (backed by
/// `UIScreen.capturedDidChangeNotification`) and report changes to Dart via
/// `onScreenCaptureChanged`, so the host app can react itself — e.g. blank
/// the video surface or show a warning overlay — for as long as the screen
/// is captured. This is **detection only**, not prevention.
///
/// A single plugin-lifetime instance (mirrors `NetworkMonitor`): `UIScreen`
/// capture state is a device-global signal, not a per-player one, so one
/// `NotificationCenter` observer is fanned out to every player id that has
/// opted in via [setMonitoring], rather than each player registering its own
/// redundant observer.
final class ScreenCaptureHandler: NSObject {
    private let channel: FlutterMethodChannel
    private var monitoredPlayerIds: Set<String> = []
    private var isObserving = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    /// Enable or disable screen-capture monitoring for `playerId`. When
    /// enabling, immediately reports the current `UIScreen.isCaptured` value
    /// to this player id (mirrors the "emit current status right away"
    /// pattern `ZMediaPlayerPlugin`'s `handleInitialize` already uses for
    /// `onNetworkStatusChanged`), so the host app does not have to wait for
    /// the next capture-state transition to learn the current one.
    func setMonitoring(playerId: String, enabled: Bool) {
        if enabled {
            monitoredPlayerIds.insert(playerId)
            startObservingIfNeeded()
            emit(to: [playerId], isCaptured: UIScreen.main.isCaptured)
        } else {
            monitoredPlayerIds.remove(playerId)
            stopObservingIfIdle()
        }
    }

    /// Stop monitoring for `playerId` entirely (called from `dispose`).
    func clear(playerId: String) {
        monitoredPlayerIds.remove(playerId)
        stopObservingIfIdle()
    }

    /// Stops observing and forgets every monitored player id. Called when
    /// the plugin itself detaches from the engine.
    func dispose() {
        if isObserving {
            NotificationCenter.default.removeObserver(
                self,
                name: UIScreen.capturedDidChangeNotification,
                object: nil
            )
            isObserving = false
        }
        monitoredPlayerIds.removeAll()
    }

    private func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureStateDidChange),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
    }

    private func stopObservingIfIdle() {
        guard isObserving, monitoredPlayerIds.isEmpty else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        isObserving = false
    }

    @objc private func captureStateDidChange() {
        emit(to: monitoredPlayerIds, isCaptured: UIScreen.main.isCaptured)
    }

    /// `UIScreen.capturedDidChangeNotification` is documented to be posted
    /// on the main thread, but `FlutterMethodChannel.invokeMethod` requires
    /// the main thread regardless — hop explicitly rather than relying on
    /// that (mirrors `DrmHandler.invokeOnMain` / the `NetworkMonitor`
    /// broadcast pattern in `ZMediaPlayerPlugin.swift`).
    private func emit(to playerIds: Set<String>, isCaptured: Bool) {
        guard !playerIds.isEmpty else { return }
        let ids = playerIds
        DispatchQueue.main.async { [channel] in
            for id in ids {
                channel.invokeMethod(
                    "onScreenCaptureChanged",
                    arguments: ["playerId": id, "isCaptured": isCaptured]
                )
            }
        }
    }
}

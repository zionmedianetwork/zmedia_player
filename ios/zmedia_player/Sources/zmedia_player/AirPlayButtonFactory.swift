import Foundation
import Flutter
import AVKit

/// Factory for creating AirPlay route picker button views
class AirPlayButtonFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return AirPlayButtonView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Platform view for displaying AVRoutePickerView
class AirPlayButtonView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private let routePickerView: AVRoutePickerView

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        _view = UIView(frame: frame)
        routePickerView = AVRoutePickerView()

        super.init()

        // Configure route picker from arguments
        if let arguments = args as? [String: Any] {
            configureRoutePicker(with: arguments)
        } else {
            // Default configuration
            routePickerView.tintColor = .white
            routePickerView.activeTintColor = .systemBlue
            routePickerView.prioritizesVideoDevices = true
        }

        // Setup layout
        routePickerView.translatesAutoresizingMaskIntoConstraints = false
        _view.addSubview(routePickerView)

        NSLayoutConstraint.activate([
            routePickerView.centerXAnchor.constraint(equalTo: _view.centerXAnchor),
            routePickerView.centerYAnchor.constraint(equalTo: _view.centerYAnchor),
            routePickerView.widthAnchor.constraint(equalToConstant: 32),
            routePickerView.heightAnchor.constraint(equalToConstant: 32)
        ])

        print("AirPlayButtonView: Created with frame: \(frame)")
    }

    func view() -> UIView {
        return _view
    }

    private func configureRoutePicker(with arguments: [String: Any]) {
        // Configure tint color
        if let tintColorHex = arguments["tintColor"] as? String {
            routePickerView.tintColor = hexStringToUIColor(hex: tintColorHex)
        } else {
            routePickerView.tintColor = .white
        }

        // Configure active tint color
        if let activeTintColorHex = arguments["activeTintColor"] as? String {
            routePickerView.activeTintColor = hexStringToUIColor(hex: activeTintColorHex)
        } else {
            routePickerView.activeTintColor = .systemBlue
        }

        // Configure prioritizesVideoDevices
        if let prioritizesVideo = arguments["prioritizesVideoDevices"] as? Bool {
            routePickerView.prioritizesVideoDevices = prioritizesVideo
        } else {
            routePickerView.prioritizesVideoDevices = true
        }

        print("AirPlayButtonView: Configured with arguments: \(arguments)")
    }

    /// Convert hex string to UIColor
    private func hexStringToUIColor(hex: String) -> UIColor {
        var cString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }

        guard cString.count == 8 else {
            return .white
        }

        var rgbaValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbaValue)

        return UIColor(
            red: CGFloat((rgbaValue & 0xFF000000) >> 24) / 255.0,
            green: CGFloat((rgbaValue & 0x00FF0000) >> 16) / 255.0,
            blue: CGFloat((rgbaValue & 0x0000FF00) >> 8) / 255.0,
            alpha: CGFloat(rgbaValue & 0x000000FF) / 255.0
        )
    }
}

import Foundation
import Security
import Flutter

/**
 * Handles secure storage operations using iOS Keychain.
 *
 * Uses the iOS Keychain Services API to securely store sensitive data
 * like DRM tokens and credentials. Data is encrypted and protected by
 * the device's secure enclave.
 */
class SecureStorageHandler: NSObject, FlutterPlugin {

    private let serviceName = "com.zionmedianetwork.zmedia_player"

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Not used - registration is handled by ZMediaPlayerPlugin
    }

    /**
     * Handles method calls from Flutter
     */
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "write":
            handleWrite(call, result: result)
        case "read":
            handleRead(call, result: result)
        case "delete":
            handleDelete(call, result: result)
        case "deleteAll":
            handleDeleteAll(call, result: result)
        case "containsKey":
            handleContainsKey(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleWrite(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String,
              let value = args["value"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Key and value must not be null",
                details: nil
            ))
            return
        }

        guard let valueData = value.data(using: .utf8) else {
            result(FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode value",
                details: nil
            ))
            return
        }

        // Delete existing value if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new value
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: valueData,
            // H-11: ...ThisDeviceOnly ties the item to this device's Secure Enclave-backed
            // keybag, so it is excluded from encrypted iCloud/iTunes backups and cannot be
            // restored onto different hardware. DRM tokens and credentials stored here must
            // never migrate to another device via a backup restore.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecSuccess {
            result(nil)
        } else {
            result(FlutterError(
                code: "WRITE_ERROR",
                message: "Failed to write to secure storage: \(status)",
                details: nil
            ))
        }
    }

    private func handleRead(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Key must not be null",
                details: nil
            ))
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let data = item as? Data,
               let value = String(data: data, encoding: .utf8) {
                result(value)
            } else {
                result(FlutterError(
                    code: "DECODING_ERROR",
                    message: "Failed to decode stored value",
                    details: nil
                ))
            }
        } else if status == errSecItemNotFound {
            result(nil)
        } else {
            result(FlutterError(
                code: "READ_ERROR",
                message: "Failed to read from secure storage: \(status)",
                details: nil
            ))
        }
    }

    private func handleDelete(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Key must not be null",
                details: nil
            ))
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            result(nil)
        } else {
            result(FlutterError(
                code: "DELETE_ERROR",
                message: "Failed to delete from secure storage: \(status)",
                details: nil
            ))
        }
    }

    private func handleDeleteAll(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            result(nil)
        } else {
            result(FlutterError(
                code: "DELETE_ALL_ERROR",
                message: "Failed to clear secure storage: \(status)",
                details: nil
            ))
        }
    }

    private func handleContainsKey(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Key must not be null",
                details: nil
            ))
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        result(status == errSecSuccess)
    }
}

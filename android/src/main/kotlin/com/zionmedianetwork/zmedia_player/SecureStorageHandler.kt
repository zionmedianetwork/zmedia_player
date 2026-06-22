package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handles secure storage operations using EncryptedSharedPreferences.
 *
 * Uses Android Keystore system to encrypt keys and values before storing.
 * Provides a secure way to store sensitive data like DRM tokens and credentials.
 *
 * SECURITY POLICY: If EncryptedSharedPreferences cannot be initialised (e.g.
 * the device has no hardware-backed Keystore, or the KeyStore is locked), every
 * operation returns a MethodChannel error with code "ENCRYPTION_UNAVAILABLE".
 * We deliberately refuse to fall back to plaintext SharedPreferences, because
 * the data stored here (DRM tokens, auth credentials) must never be written in
 * cleartext.
 */
class SecureStorageHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SecureStorageHandler"
        private const val PREFS_NAME = "zmedia_player_secure_storage"
        private const val ERROR_ENCRYPTION_UNAVAILABLE = "ENCRYPTION_UNAVAILABLE"
        private const val MESSAGE_ENCRYPTION_UNAVAILABLE =
            "Secure storage is not available on this device; refusing to store sensitive data in plaintext"
    }

    /**
     * Nullable encrypted prefs.  null means initialisation failed and every
     * operation must return an error – never fall back to plaintext.
     */
    private val securePrefs: SharedPreferences? by lazy {
        try {
            val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
            EncryptedSharedPreferences.create(
                PREFS_NAME,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create EncryptedSharedPreferences; secure storage unavailable", e)
            null
        }
    }

    /**
     * Returns true if encrypted prefs are available; otherwise invokes
     * result.error and returns false.  Callers must return immediately when
     * this returns false.
     */
    private fun requireSecurePrefs(result: MethodChannel.Result): SharedPreferences? {
        val prefs = securePrefs
        if (prefs == null) {
            result.error(
                ERROR_ENCRYPTION_UNAVAILABLE,
                MESSAGE_ENCRYPTION_UNAVAILABLE,
                null
            )
        }
        return prefs
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "write" -> handleWrite(call, result)
            "read" -> handleRead(call, result)
            "delete" -> handleDelete(call, result)
            "deleteAll" -> handleDeleteAll(call, result)
            "containsKey" -> handleContainsKey(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleWrite(call: MethodCall, result: MethodChannel.Result) {
        val prefs = requireSecurePrefs(result) ?: return
        try {
            val key = call.argument<String>("key")
            val value = call.argument<String>("value")

            if (key == null || value == null) {
                result.error("INVALID_ARGUMENTS", "Key and value must not be null", null)
                return
            }

            prefs.edit().putString(key, value).apply()
            result.success(null)
        } catch (e: Exception) {
            result.error("WRITE_ERROR", "Failed to write to secure storage: ${e.message}", null)
        }
    }

    private fun handleRead(call: MethodCall, result: MethodChannel.Result) {
        val prefs = requireSecurePrefs(result) ?: return
        try {
            val key = call.argument<String>("key")

            if (key == null) {
                result.error("INVALID_ARGUMENTS", "Key must not be null", null)
                return
            }

            val value = prefs.getString(key, null)
            result.success(value)
        } catch (e: Exception) {
            result.error("READ_ERROR", "Failed to read from secure storage: ${e.message}", null)
        }
    }

    private fun handleDelete(call: MethodCall, result: MethodChannel.Result) {
        val prefs = requireSecurePrefs(result) ?: return
        try {
            val key = call.argument<String>("key")

            if (key == null) {
                result.error("INVALID_ARGUMENTS", "Key must not be null", null)
                return
            }

            prefs.edit().remove(key).apply()
            result.success(null)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", "Failed to delete from secure storage: ${e.message}", null)
        }
    }

    private fun handleDeleteAll(call: MethodCall, result: MethodChannel.Result) {
        val prefs = requireSecurePrefs(result) ?: return
        try {
            prefs.edit().clear().apply()
            result.success(null)
        } catch (e: Exception) {
            result.error("DELETE_ALL_ERROR", "Failed to clear secure storage: ${e.message}", null)
        }
    }

    private fun handleContainsKey(call: MethodCall, result: MethodChannel.Result) {
        val prefs = requireSecurePrefs(result) ?: return
        try {
            val key = call.argument<String>("key")

            if (key == null) {
                result.error("INVALID_ARGUMENTS", "Key must not be null", null)
                return
            }

            val contains = prefs.contains(key)
            result.success(contains)
        } catch (e: Exception) {
            result.error(
                "CONTAINS_KEY_ERROR",
                "Failed to check key existence: ${e.message}",
                null
            )
        }
    }
}

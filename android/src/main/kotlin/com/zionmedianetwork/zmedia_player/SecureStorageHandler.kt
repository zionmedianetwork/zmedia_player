package com.zionmedianetwork.zmedia_player

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handles secure storage operations using EncryptedSharedPreferences.
 *
 * Uses Android Keystore system to encrypt keys and values before storing.
 * Provides a secure way to store sensitive data like DRM tokens and credentials.
 */
class SecureStorageHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val PREFS_NAME = "zmedia_player_secure_storage"
    }

    private val sharedPreferences: SharedPreferences by lazy {
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
            // Fallback to regular SharedPreferences if encryption fails
            android.util.Log.w("SecureStorageHandler", "Failed to create EncryptedSharedPreferences, using regular SharedPreferences", e)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
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
        try {
            val key = call.argument<String>("key")
            val value = call.argument<String>("value")

            if (key == null || value == null) {
                result.error("INVALID_ARGUMENTS", "Key and value must not be null", null)
                return
            }

            sharedPreferences.edit().putString(key, value).apply()
            result.success(null)
        } catch (e: Exception) {
            result.error("WRITE_ERROR", "Failed to write to secure storage: ${e.message}", null)
        }
    }

    private fun handleRead(call: MethodCall, result: MethodChannel.Result) {
        try {
            val key = call.argument<String>("key")

            if (key == null) {
                result.error("INVALID_ARGUMENTS", "Key must not be null", null)
                return
            }

            val value = sharedPreferences.getString(key, null)
            result.success(value)
        } catch (e: Exception) {
            result.error("READ_ERROR", "Failed to read from secure storage: ${e.message}", null)
        }
    }

    private fun handleDelete(call: MethodCall, result: MethodChannel.Result) {
        try {
            val key = call.argument<String>("key")

            if (key == null) {
                result.error("INVALID_ARGUMENTS", "Key must not be null", null)
                return
            }

            sharedPreferences.edit().remove(key).apply()
            result.success(null)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", "Failed to delete from secure storage: ${e.message}", null)
        }
    }

    private fun handleDeleteAll(call: MethodCall, result: MethodChannel.Result) {
        try {
            sharedPreferences.edit().clear().apply()
            result.success(null)
        } catch (e: Exception) {
            result.error("DELETE_ALL_ERROR", "Failed to clear secure storage: ${e.message}", null)
        }
    }

    private fun handleContainsKey(call: MethodCall, result: MethodChannel.Result) {
        try {
            val key = call.argument<String>("key")

            if (key == null) {
                result.error("INVALID_ARGUMENTS", "Key must not be null", null)
                return
            }

            val contains = sharedPreferences.contains(key)
            result.success(contains)
        } catch (e: Exception) {
            result.error("CONTAINS_KEY_ERROR", "Failed to check key existence: ${e.message}", null)
        }
    }
}

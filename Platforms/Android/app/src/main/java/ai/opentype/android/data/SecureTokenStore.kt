package ai.opentype.android.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import ai.opentype.android.model.TextProvider
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Provider tokens are encrypted with a non-exportable Android Keystore key.
 * SharedPreferences contains ciphertext and an IV only; plaintext is never logged.
 */
class SecureTokenStore(context: Context) {
    private val preferences = context.applicationContext
        .getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    fun save(provider: TextProvider, token: String) {
        val normalized = token.trim()
        if (normalized.isEmpty()) {
            clear(provider)
            return
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(normalized.toByteArray(Charsets.UTF_8))
        val payload = listOf(
            VERSION,
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
            Base64.encodeToString(encrypted, Base64.NO_WRAP)
        ).joinToString(":")
        preferences.edit().putString(keyFor(provider), payload).apply()
    }

    fun token(provider: TextProvider): String? {
        val payload = preferences.getString(keyFor(provider), null) ?: return null
        return runCatching {
            val components = payload.split(':', limit = 3)
            require(components.size == 3 && components[0] == VERSION)
            val iv = Base64.decode(components[1], Base64.NO_WRAP)
            val encrypted = Base64.decode(components[2], Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, existingKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        }.getOrNull()?.takeIf { it.isNotBlank() }
    }

    fun hasToken(provider: TextProvider): Boolean = token(provider) != null

    fun clear(provider: TextProvider) {
        preferences.edit().remove(keyFor(provider)).apply()
    }

    private fun keyFor(provider: TextProvider) = "provider_token_${provider.id}"

    private fun existingKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: error("OpenType secure key is unavailable")
    }

    private fun getOrCreateKey(): SecretKey {
        runCatching { existingKey() }.getOrNull()?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build()
            )
            generateKey()
        }
    }

    companion object {
        private const val FILE_NAME = "opentype_secure_tokens"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "opentype_provider_tokens_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val VERSION = "v1"
    }
}

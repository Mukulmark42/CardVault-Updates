import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Enhanced encryption service with AES-GCM, random IVs, and proper key management
/// Supports end-to-end encryption for Firebase backup
class EnhancedEncryptionService {
  static final EnhancedEncryptionService instance =
      EnhancedEncryptionService._init();

  static const _storage = FlutterSecureStorage();
  static const _masterKeyName = 'vault_master_key_v6';
  static const _keyDerivationSaltName = 'vault_key_salt_v1';

  encrypt.Key? _masterKey;
  encrypt.Encrypter? _encrypter;

  // For user-specific encryption (E2EE)
  String? _userEncryptionKeyId;
  encrypt.Key? _userEncryptionKey;

  EnhancedEncryptionService._init();

  // --- Local Device Encryption (for local SQLite storage) ---

  Future<void> _initMasterKey() async {
    if (_masterKey != null) return;

    String? storedKey = await _storage.read(key: _masterKeyName);

    if (storedKey == null || storedKey.isEmpty) {
      // Generate new 256-bit key for AES-256
      final newKey = encrypt.Key.fromSecureRandom(32);
      await _storage.write(key: _masterKeyName, value: newKey.base64);
      _masterKey = newKey;
    } else {
      _masterKey = encrypt.Key.fromBase64(storedKey);
    }

    // Initialize encrypter with AES-GCM mode
    _encrypter = encrypt.Encrypter(
      encrypt.AES(_masterKey!, mode: encrypt.AESMode.gcm),
    );
  }

  /// Encrypt data with AES-GCM using random IV
  Future<String> encryptData(String plaintext) async {
    try {
      if (plaintext.isEmpty) return "";
      await _initMasterKey();

      // Generate random IV for GCM (12 bytes recommended for GCM)
      final iv = encrypt.IV.fromSecureRandom(12);

      // Encrypt with GCM
      final encrypted = _encrypter!.encrypt(plaintext, iv: iv);

      // Return format: iv.base64:encrypted.base64
      // The encrypt package's GCM implementation includes auth tag in the encrypted data
      return "${iv.base64}:${encrypted.base64}";
    } catch (e) {
      debugPrint("Encryption error: $e");
      // Never return plaintext on error - throw instead
      throw Exception("Encryption failed: $e");
    }
  }

  /// Decrypt data encrypted with AES-GCM
  Future<String> decryptData(String encryptedData) async {
    try {
      if (encryptedData.isEmpty) return "";
      await _initMasterKey();

      // Parse the components
      final parts = encryptedData.split(':');
      if (parts.length < 2) {
        // Legacy format (CBC with fixed IV) - try to decrypt with old method
        return _decryptLegacyData(encryptedData);
      }

      final iv = encrypt.IV.fromBase64(parts[0]);
      final ciphertext = encrypt.Encrypted.fromBase64(parts[1]);

      return _encrypter!.decrypt(ciphertext, iv: iv);
    } catch (e) {
      debugPrint("Decryption error: $e");
      return "[Decryption Error]";
    }
  }

  /// Legacy decryption for backward compatibility
  Future<String> _decryptLegacyData(String encryptedData) async {
    try {
      // Old format used CBC with fixed IV
      final legacyEncrypter = encrypt.Encrypter(
        encrypt.AES(_masterKey!, mode: encrypt.AESMode.cbc),
      );
      final fixedIv = encrypt.IV.fromUtf8('cvault_fixed_iv_');
      return legacyEncrypter.decrypt64(encryptedData, iv: fixedIv);
    } catch (e) {
      debugPrint("Legacy decryption failed: $e");
      return "[Legacy Decryption Error]";
    }
  }

  // --- User-Specific Encryption (for Firebase E2EE) ---

  /// Derive encryption key from user password for cross-device compatibility
  Future<void> setupUserEncryptionKey(String password, {String? salt}) async {
    // Generate or use provided salt
    String actualSalt;
    if (salt == null) {
      final existingSalt = await _storage.read(key: _keyDerivationSaltName);
      if (existingSalt == null) {
        // Generate new salt
        final random = encrypt.Key.fromSecureRandom(16);
        actualSalt = random.base64;
        await _storage.write(key: _keyDerivationSaltName, value: actualSalt);
      } else {
        actualSalt = existingSalt;
      }
    } else {
      actualSalt = salt;
      await _storage.write(key: _keyDerivationSaltName, value: actualSalt);
    }

    // Derive key using PBKDF2
    final key = _deriveKeyFromPassword(password, actualSalt);
    _userEncryptionKey = encrypt.Key(Uint8List.fromList(key));
    _userEncryptionKeyId =
        'v1_${sha256.convert(utf8.encode(password + actualSalt)).toString().substring(0, 8)}';
  }

  /// Derive 256-bit key from password using PBKDF2-like approach
  List<int> _deriveKeyFromPassword(String password, String saltBase64) {
    final salt = base64.decode(saltBase64);
    final passwordBytes = utf8.encode(password);

    // Use HMAC-SHA256 for key derivation (simplified PBKDF2)
    // In production, use a proper PBKDF2 implementation
    var hmac = Hmac(sha256, passwordBytes);
    var derivedKey = hmac.convert(salt);

    // Iterate for 10000 rounds (simplified)
    for (int i = 0; i < 10000; i++) {
      hmac = Hmac(sha256, derivedKey.bytes);
      derivedKey = hmac.convert(salt);
    }

    return derivedKey.bytes.sublist(0, 32); // 256 bits
  }

  /// Encrypt data with user-specific key for Firebase storage
  Future<Map<String, String>> encryptForFirebase(String plaintext) async {
    if (_userEncryptionKey == null) {
      throw Exception(
        "User encryption key not set up. Call setupUserEncryptionKey first.",
      );
    }

    final encrypter = encrypt.Encrypter(
      encrypt.AES(_userEncryptionKey!, mode: encrypt.AESMode.gcm),
    );
    final iv = encrypt.IV.fromSecureRandom(12);
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    return {
      'encrypted_data': encrypted.base64,
      'iv': iv.base64,
      'key_id': _userEncryptionKeyId!,
      'algorithm': 'AES-GCM-256',
      'version': '1',
    };
  }

  /// Decrypt data encrypted with user-specific key
  Future<String> decryptFromFirebase(Map<String, dynamic> encryptedData) async {
    if (_userEncryptionKey == null) {
      throw Exception("User encryption key not set up.");
    }

    final version = encryptedData['version'] ?? '1';
    final algorithm = encryptedData['algorithm'] ?? 'AES-GCM-256';

    if (algorithm != 'AES-GCM-256') {
      throw Exception("Unsupported encryption algorithm: $algorithm");
    }

    final iv = encrypt.IV.fromBase64(encryptedData['iv'] as String);
    final ciphertext = encrypt.Encrypted.fromBase64(
      encryptedData['encrypted_data'] as String,
    );

    final encrypter = encrypt.Encrypter(
      encrypt.AES(_userEncryptionKey!, mode: encrypt.AESMode.gcm),
    );

    return encrypter.decrypt(ciphertext, iv: iv);
  }

  /// Check if user encryption is set up
  bool isUserEncryptionReady() {
    return _userEncryptionKey != null;
  }

  /// Get the salt for key derivation (to store in Firebase for cross-device sync)
  Future<String?> getKeyDerivationSalt() async {
    return await _storage.read(key: _keyDerivationSaltName);
  }

  /// Clear user encryption key (on logout)
  void clearUserEncryptionKey() {
    _userEncryptionKey = null;
    _userEncryptionKeyId = null;
  }

  /// Migrate existing encrypted data to new format
  Future<String> migrateToNewFormat(String legacyEncryptedData) async {
    try {
      // Decrypt with legacy method
      final decrypted = await _decryptLegacyData(legacyEncryptedData);
      // Re-encrypt with new method
      return await encryptData(decrypted);
    } catch (e) {
      debugPrint("Migration failed: $e");
      return legacyEncryptedData; // Return original if migration fails
    }
  }
}

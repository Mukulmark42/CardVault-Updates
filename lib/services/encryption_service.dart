import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class EncryptionService {
  static final EncryptionService instance = EncryptionService._init();
  
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'vault_master_key_v5';

  encrypt.Key? _key;
  encrypt.Encrypter? _encrypter;
  final _iv = encrypt.IV.fromUtf8('cvault_fixed_iv_');

  Completer<void>? _initCompleter;

  EncryptionService._init();

  Future<void> _initKey() async {
    if (_key != null) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      String? storedKey = await _storage.read(key: _keyName);
      
      if (storedKey == null || storedKey.isEmpty) {
        final newKey = encrypt.Key.fromSecureRandom(32);
        await _storage.write(key: _keyName, value: newKey.base64);
        _key = newKey;
      } else {
        _key = encrypt.Key.fromBase64(storedKey);
      }
      
      // Initialize encrypter once
      _encrypter = encrypt.Encrypter(encrypt.AES(_key!, mode: encrypt.AESMode.cbc));
      
      _initCompleter!.complete();
    } catch (e) {
      debugPrint("Security Init Error: $e");
      _initCompleter!.completeError(e);
      _initCompleter = null;
    }
  }

  Future<String> encryptData(String data) async {
    try {
      if (data.isEmpty) return "";
      await _initKey();
      return _encrypter!.encrypt(data, iv: _iv).base64;
    } catch (e) {
      return data;
    }
  }

  Future<String> decryptData(String encryptedData) async {
    try {
      if (encryptedData.isEmpty) return "";
      await _initKey();
      return _encrypter!.decrypt64(encryptedData, iv: _iv);
    } catch (e) {
      debugPrint("Decryption Failed: $e");
      return "[Decryption Error]";
    }
  }
}

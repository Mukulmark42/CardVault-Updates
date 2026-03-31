import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityProvider extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  String? _pin;
  bool _isBiometricEnabled = true;

  String? get pin => _pin;
  bool get isBiometricEnabled => _isBiometricEnabled;
  bool get isPinSet => _pin != null && _pin!.length == 4;

  SecurityProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _pin = await _storage.read(key: 'user_pin');
    String? bio = await _storage.read(key: 'biometric_enabled');
    _isBiometricEnabled = bio != 'false';
    notifyListeners();
  }

  Future<void> setPin(String newPin) async {
    if (newPin.length == 4) {
      await _storage.write(key: 'user_pin', value: newPin);
      _pin = newPin;
      notifyListeners();
    }
  }

  Future<void> removePin() async {
    await _storage.delete(key: 'user_pin');
    _pin = null;
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: 'biometric_enabled', value: enabled.toString());
    _isBiometricEnabled = enabled;
    notifyListeners();
  }

  bool verifyPin(String enteredPin) {
    return _pin == enteredPin;
  }
}

/// 4-digit PIN storage. Only a salted SHA-256 hash is kept, in secure storage.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinStore {
  static const String pinKey = 'ft_pin_sha256';

  final FlutterSecureStorage _storage;

  const PinStore([this._storage = const FlutterSecureStorage()]);

  Future<bool> hasPin() async => await _storage.read(key: pinKey) != null;

  Future<void> setPin(String pin) async {
    await _storage.write(key: pinKey, value: hashPin(pin));
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: pinKey);
    if (stored == null) return false;
    return stored == hashPin(pin);
  }

  /// Deletes the stored PIN hash. Called by Reset-all so the next lock gate
  /// lands in PIN-SETUP mode. Secure-storage needs a device/plugin, so this
  /// half of reset is device-verified, not unit-tested.
  Future<void> clearPin() async {
    await _storage.delete(key: pinKey);
  }

  /// Salted SHA-256 of the PIN. Static so tests can assert the format.
  static String hashPin(String pin) =>
      sha256.convert(utf8.encode('ft-pin:$pin')).toString();
}

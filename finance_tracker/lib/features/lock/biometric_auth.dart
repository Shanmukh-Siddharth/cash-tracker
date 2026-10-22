/// Thin injectable wrapper around [LocalAuthentication] so the lock-screen
/// biometric trigger lifecycle is unit/widget testable without a platform
/// channel.
library;

import 'package:local_auth/local_auth.dart';

/// Minimal surface the lock screen needs from local_auth.
abstract class BiometricAuth {
  Future<bool> get canCheckBiometrics;
  Future<bool> isDeviceSupported();
  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
  });
}

/// Production implementation backed by `local_auth`.
class RealBiometricAuth implements BiometricAuth {
  final LocalAuthentication _auth;
  RealBiometricAuth([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> get canCheckBiometrics => _auth.canCheckBiometrics;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
  }) =>
      _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: true,
      );
}

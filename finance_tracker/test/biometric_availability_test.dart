/// Lock-screen biometric availability rules (pure, no platform channel).
///
/// Regression cover for the owner bug "biometric not working": the old code
/// gated on `canCheckBiometrics` alone, so a device with only a screen lock
/// (PIN/pattern) got "No biometrics enrolled — use PIN" and dead-ended, even
/// though the OS credential prompt would have worked.
library;

import 'package:finance_tracker/features/lock/biometric_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('biometricAvailability', () {
    test('biometrics enrolled -> biometrics (credential fallback behind it)',
        () {
      expect(
        biometricAvailability(
          canCheckBiometrics: true,
          canCheckDeviceCredentials: true,
        ),
        BiometricOffer.biometrics,
      );
      // Some platforms report biometric support without the broader flag.
      expect(
        biometricAvailability(
          canCheckBiometrics: true,
          canCheckDeviceCredentials: false,
        ),
        BiometricOffer.biometrics,
      );
    });

    test('no biometrics but a screen lock set -> deviceCredentialOnly', () {
      expect(
        biometricAvailability(
          canCheckBiometrics: false,
          canCheckDeviceCredentials: true,
        ),
        BiometricOffer.deviceCredentialOnly,
      );
    });

    test('neither enrolled -> none', () {
      expect(
        biometricAvailability(
          canCheckBiometrics: false,
          canCheckDeviceCredentials: false,
        ),
        BiometricOffer.none,
      );
    });
  });

  group('offerBiometricButton', () {
    test('the button stays visible for a credential-only device (no dead end)',
        () {
      expect(offerBiometricButton(BiometricOffer.biometrics), isTrue);
      expect(offerBiometricButton(BiometricOffer.deviceCredentialOnly), isTrue);
    });

    test('only fully-unset devices hide the button', () {
      expect(offerBiometricButton(BiometricOffer.none), isFalse);
    });
  });

  group('labels + inline status', () {
    test('biometrics label is the owner-facing fingerprint/pattern copy', () {
      expect(
        biometricButtonLabel(BiometricOffer.biometrics),
        'Use fingerprint / pattern',
      );
      expect(biometricStatusText(BiometricOffer.biometrics), isNull);
    });

    test('credential-only still offers the button and says why', () {
      expect(
        biometricButtonLabel(BiometricOffer.deviceCredentialOnly),
        'Use PIN / pattern',
      );
      expect(
        biometricStatusText(BiometricOffer.deviceCredentialOnly),
        contains('No fingerprint enrolled'),
      );
    });

    test('none explains the PIN-only situation inline', () {
      expect(
        biometricButtonLabel(BiometricOffer.none),
        'No fingerprint or screen lock set',
      );
      expect(
        biometricStatusText(BiometricOffer.none),
        contains('No fingerprint or screen lock set'),
      );
      expect(biometricUnavailableReason(BiometricOffer.none), isNotEmpty);
    });

    test('biometrics enrolled has no failure reason to show', () {
      expect(biometricUnavailableReason(BiometricOffer.biometrics), '');
    });
  });
}

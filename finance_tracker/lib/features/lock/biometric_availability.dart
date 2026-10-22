/// Pure decision helper for the lock screen's biometric/credential offer.
///
/// Why this exists: the OS exposes two independent booleans —
/// `LocalAuthentication.canCheckBiometrics` (a biometric is *enrolled*) and
/// `LocalAuthentication.isDeviceSupported()` (biometrics OR a device PIN /
/// pattern / passcode exists). The old lock screen only looked at the first
/// one and dead-ended ("No biometrics enrolled — use PIN") on devices where
/// only a screen lock was set, even though the OS credential prompt would
/// have worked. This maps the pair to what the UI should offer, so it can be
/// unit tested without a platform channel.
library;

/// What the lock screen can offer the owner right now.
enum BiometricOffer {
  /// Biometrics enrolled: offer the fingerprint/face button, and the OS
  /// credential fallback is available behind it.
  biometrics,

  /// No biometrics enrolled, but a device PIN/pattern/passcode IS set.
  /// The button must STILL be offered — tapping it opens the OS credential
  /// prompt. This is the case the old code dead-ended on.
  deviceCredentialOnly,

  /// Neither biometrics nor a device credential is set up. Nothing to offer,
  /// so the PIN pad is the only way in and we say so inline.
  none,
}

/// Pure: given the two OS capability probes, decide what to offer.
///
/// [canCheckBiometrics] maps to `LocalAuthentication.canCheckBiometrics`
/// (`deviceSupportsBiometrics`). [canCheckDeviceCredentials] maps to
/// `LocalAuthentication.isDeviceSupported()` — true when the device can run a
/// biometric OR device-credential prompt, so a true value with a false
/// [canCheckBiometrics] means "credential only".
BiometricOffer biometricAvailability({
  required bool canCheckBiometrics,
  required bool canCheckDeviceCredentials,
}) {
  if (canCheckBiometrics) return BiometricOffer.biometrics;
  if (canCheckDeviceCredentials) return BiometricOffer.deviceCredentialOnly;
  return BiometricOffer.none;
}

/// Whether the unlock button should be visible at all. Only [BiometricOffer.none]
/// hides it — a credential-only device still gets the button.
bool offerBiometricButton(BiometricOffer offer) => offer != BiometricOffer.none;

/// Short always-visible label under/inside the unlock button.
String biometricButtonLabel(BiometricOffer offer) => switch (offer) {
      BiometricOffer.biometrics => 'Use fingerprint / pattern',
      BiometricOffer.deviceCredentialOnly => 'Use PIN / pattern',
      BiometricOffer.none => 'No fingerprint or screen lock set',
    };

/// Inline status line, or null when there is nothing to warn about.
String? biometricStatusText(BiometricOffer offer) => switch (offer) {
      BiometricOffer.biometrics => null,
      BiometricOffer.deviceCredentialOnly =>
        'No fingerprint enrolled — device PIN / pattern will be used',
      BiometricOffer.none =>
        'No fingerprint or screen lock set on this device — using app PIN',
    };

/// Sentence the auto-attempt (first show) uses when the OS cannot prompt.
String biometricUnavailableReason(BiometricOffer offer) => switch (offer) {
      BiometricOffer.biometrics => '',
      BiometricOffer.deviceCredentialOnly =>
        'No biometrics enrolled — use device PIN or app PIN',
      BiometricOffer.none =>
        'No fingerprint or screen lock set on this device — use app PIN',
    };

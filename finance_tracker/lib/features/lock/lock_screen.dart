/// Lock screen: biometric-first unlock with 4-digit PIN fallback.
///
/// First run forces PIN setup (enter twice). 5 wrong PINs -> 30s cooldown.
/// Balances stay hidden until [LockService.unlock] is called.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_version.dart';
import '../../core/theme.dart';
import '../settings/settings_store.dart';
import '../splash/notes_mark.dart';
import 'biometric_auth.dart';
import 'biometric_availability.dart';
import 'lock_service.dart';
import 'pin_store.dart';

enum _LockMode { loading, setupEnter, setupConfirm, enter }

class LockScreen extends StatefulWidget {
  final LockService lockService;
  final PinStore pinStore;

  /// Injectable biometric backend (tests pass a fake; defaults to real).
  final BiometricAuth? biometricAuth;

  const LockScreen({
    super.key,
    required this.lockService,
    required this.pinStore,
    this.biometricAuth,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  late final BiometricAuth _auth;
  _LockMode _mode = _LockMode.loading;
  String _entry = '';
  String _firstPin = '';
  String? _status;
  int _wrong = 0;
  DateTime? _cooldownUntil;
  Timer? _cooldownTimer;
  bool _bioAttempted = false;

  /// Tracks the last seen lock value so a false→true transition starts a
  /// NEW lock session (guard reset + re-probe + one auto-attempt).
  bool _wasLocked = true;

  /// What the OS can actually offer (biometrics and/or device credential).
  /// Probed once in [_initMode]; drives the unlock button + inline status.
  BiometricOffer _offer = BiometricOffer.none;
  bool _bioRunning = false;

  /// False when the user disabled biometrics in Settings (PIN only).
  bool _bioEnabled = true;

  static const int _maxWrong = 5;
  static const int _cooldownSeconds = 30;

  @override
  void initState() {
    super.initState();
    _auth = widget.biometricAuth ?? RealBiometricAuth();
    _wasLocked = widget.lockService.locked.value;
    widget.lockService.locked.addListener(_onLockChanged);
    WidgetsBinding.instance.addObserver(this);
    _initMode();
  }

  @override
  void dispose() {
    widget.lockService.locked.removeListener(_onLockChanged);
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// A NEW lock session began (unlocked → locked) while this State is still
  /// mounted: reset the one-shot guard, re-probe the OS offer, auto-attempt
  /// once. This is what re-fires the prompt on the 2nd, 3rd, … lock.
  void _onLockChanged() {
    final locked = widget.lockService.locked.value;
    final isNewSession = locked && !_wasLocked;
    _wasLocked = locked;
    if (!isNewSession || !mounted) return;
    _bioAttempted = false;
    _startBioSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Late OS enrollment (fingerprint added while away) is picked up
    // without a restart: re-probe, and auto-attempt if still untouched.
    if (state == AppLifecycleState.resumed && mounted) {
      _reprobeOffer();
    }
  }

  /// Re-probe the OS offer; auto-attempt once if the session never tried.
  Future<void> _reprobeOffer() async {
    final offer = await _probeOffer();
    if (!mounted) return;
    setState(() => _offer = offer);
    if (_mode == _LockMode.enter &&
        !_bioAttempted &&
        _bioEnabled &&
        offerBiometricButton(offer)) {
      _bioAttempted = true;
      await _tryBiometric();
    }
  }

  /// Shared tail of [_initMode] and [_onLockChanged]: probe + one attempt.
  Future<void> _startBioSession() async {
    final offer = await _probeOffer();
    if (!mounted) return;
    setState(() => _offer = offer);
    if (_mode == _LockMode.enter &&
        _bioEnabled &&
        offerBiometricButton(offer) &&
        !_bioAttempted) {
      _bioAttempted = true;
      await _tryBiometric();
    }
  }

  Future<void> _initMode() async {
    final hasPin = await widget.pinStore.hasPin();
    var bio = true;
    try {
      bio = await SettingsStore.readBiometric();
    } catch (_) {
      bio = true;
    }
    final offer = await _probeOffer();
    if (!mounted) return;
    setState(() {
      _mode = hasPin ? _LockMode.enter : _LockMode.setupEnter;
      _bioEnabled = bio;
      _offer = offer;
    });
    // Auto-attempt once on first show, but only if the OS can prompt at all.
    if (hasPin && bio && offerBiometricButton(offer) && !_bioAttempted) {
      _bioAttempted = true;
      await _tryBiometric();
    }
  }

  /// Probes the two independent OS capabilities. Any throw degrades to
  /// "not offered" rather than crashing the lock gate.
  Future<BiometricOffer> _probeOffer() async {
    var canCheckBiometrics = false;
    var canCheckDeviceCredentials = false;
    try {
      canCheckBiometrics = await _auth.canCheckBiometrics;
    } catch (_) {
      canCheckBiometrics = false;
    }
    try {
      // True when the device can run biometrics OR a PIN/pattern/passcode
      // prompt — this is what unblocks the "no fingerprint but screen lock
      // set" case that used to dead-end.
      canCheckDeviceCredentials = await _auth.isDeviceSupported();
    } catch (_) {
      canCheckDeviceCredentials = false;
    }
    return biometricAvailability(
      canCheckBiometrics: canCheckBiometrics,
      canCheckDeviceCredentials: canCheckDeviceCredentials,
    );
  }

  bool get _inCooldown =>
      _cooldownUntil != null &&
      DateTime.now().isBefore(_cooldownUntil!);

  int get _cooldownLeft {
    if (!_inCooldown) return 0;
    return _cooldownUntil!.difference(DateTime.now()).inSeconds + 1;
  }

  void _unlock() {
    widget.lockService.unlock();
  }

  Future<void> _tryBiometric({bool manual = false}) async {
    if (_mode != _LockMode.enter || _inCooldown || !_bioEnabled) return;
    if (_bioRunning) return;
    if (!offerBiometricButton(_offer)) {
      if (manual && mounted) {
        setState(() => _status = biometricUnavailableReason(_offer));
      }
      return;
    }
    setState(() {
      _bioRunning = true;
      _status = null;
    });
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock NEB:Expense Tracker',
        // Owner choice: fingerprint/face OR the device PIN/pattern/passcode.
        // biometricOnly:true dead-ended on devices with only a screen lock.
        biometricOnly: false,
      );
      if (ok && mounted) _unlock();
    } catch (_) {
      // Biometric error -> fall back to PIN, never crash (Design.md §3.1).
      if (mounted) {
        setState(() => _status = 'Biometric failed — use PIN');
      }
    } finally {
      if (mounted) setState(() => _bioRunning = false);
    }
  }

  void _onDigit(String d) {
    if (_inCooldown || _entry.length >= 4) return;
    setState(() {
      _entry += d;
      _status = null;
    });
    if (_entry.length == 4) {
      // Let the 4th dot paint before processing.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _submitPin(_entry);
      });
    }
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submitPin(String pin) async {
    if (!mounted) return;
    switch (_mode) {
      case _LockMode.setupEnter:
        setState(() {
          _firstPin = pin;
          _entry = '';
          _mode = _LockMode.setupConfirm;
          _status = 'Enter the PIN again to confirm';
        });
      case _LockMode.setupConfirm:
        if (pin == _firstPin) {
          await widget.pinStore.setPin(pin);
          if (!mounted) return;
          // PIN setup done: flip to enter, then auto-fire biometrics when
          // the OS can prompt (first launch never attempted before this).
          // Devices with nothing enrolled keep the old straight-in path.
          final offer = await _probeOffer();
          if (!mounted) return;
          setState(() {
            _firstPin = '';
            _entry = '';
            _mode = _LockMode.enter;
            _offer = offer;
          });
          if (_bioEnabled && offerBiometricButton(offer)) {
            _bioAttempted = true;
            await _tryBiometric();
            // Success already unlocked inside [_tryBiometric]; otherwise the
            // owner stays on the enter pad with the PIN fallback intact.
            return;
          }
          _unlock();
        } else {
          setState(() {
            _entry = '';
            _firstPin = '';
            _mode = _LockMode.setupEnter;
            _status = 'PINs did not match — try again';
          });
          HapticFeedback.mediumImpact();
        }
      case _LockMode.enter:
        final ok = await widget.pinStore.verifyPin(pin);
        if (!mounted) return;
        if (ok) {
          _unlock();
        } else {
          final wrong = _wrong + 1;
          if (wrong >= _maxWrong) {
            setState(() {
              _wrong = 0;
              _entry = '';
              _cooldownUntil =
                  DateTime.now().add(const Duration(seconds: _cooldownSeconds));
              _status = null;
            });
            HapticFeedback.heavyImpact();
            _cooldownTimer?.cancel();
            _cooldownTimer =
                Timer.periodic(const Duration(seconds: 1), (timer) {
              if (!mounted || !_inCooldown) {
                timer.cancel();
                if (mounted) setState(() => _cooldownUntil = null);
              } else {
                setState(() {});
              }
            });
          } else {
            setState(() {
              _wrong = wrong;
              _entry = '';
              _status =
                  'Wrong PIN (${_maxWrong - wrong} tries left before cooldown)';
            });
            HapticFeedback.mediumImpact();
          }
        }
      case _LockMode.loading:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: the one-shot biometric auto-attempt lives in [_initMode] (after the
    // capability probe) — not here, so build stays side-effect free.
    final title = switch (_mode) {
      _LockMode.setupEnter => 'Set a 4-digit PIN',
      _LockMode.setupConfirm => 'Confirm your PIN',
      _ => 'Unlock NEB',
    };
    final subtitle = switch (_mode) {
      _LockMode.setupEnter => 'You will use this when biometrics fail',
      _LockMode.setupConfirm => 'One more time',
      _ => 'Biometric first, PIN fallback',
    };

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const SizedBox(
                width: 56,
                height: 56,
                child: NotesMark.full(),
              ),
              const SizedBox(height: 12),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 30,
                  color: AppColors.primary,
                  semanticLabel: 'Locked',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: AppColors.text2),
              ),
              const SizedBox(height: 24),
              _PinDots(filled: _entry.length),
              const SizedBox(height: 12),
              SizedBox(
                height: 20,
                child: _inCooldown
                    ? Text(
                        'Too many tries — wait ${_cooldownLeft}s',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                        ),
                      )
                    : _status != null
                        ? Text(
                            _status!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.danger,
                            ),
                          )
                        : _mode == _LockMode.enter
                            ? const Text(
                                '5 wrong = 30s cooldown',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.text3,
                                ),
                              )
                            : null,
              ),
              const SizedBox(height: 16),
              if (_mode == _LockMode.enter && _bioEnabled) ...[
                _BioButton(
                  enabled: !_inCooldown && offerBiometricButton(_offer),
                  busy: _bioRunning,
                  label: biometricButtonLabel(_offer),
                  onTap: () => _tryBiometric(manual: true),
                ),
                if (biometricStatusText(_offer) != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    biometricStatusText(_offer)!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              _PinPad(
                enabled: !_inCooldown && _mode != _LockMode.loading,
                onDigit: _onDigit,
                onBackspace: _onBackspace,
              ),
              const Spacer(),
              const Text(
                'NEB:Expense Tracker • $appVersion • Offline',
                style: TextStyle(fontSize: 10, color: AppColors.text3),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  final int filled;
  const _PinDots({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$filled of 4 digits entered',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final on = i < filled;
          return Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? AppColors.primary : Colors.transparent,
              border: Border.all(
                color: on ? AppColors.primary : AppColors.text3,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _BioButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final String label;
  final VoidCallback onTap;
  const _BioButton({
    required this.enabled,
    required this.busy,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Unlock with fingerprint, face or device PIN',
      child: SizedBox(
        // >=48px tall tap target.
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: enabled ? AppColors.primary : AppColors.text3,
            side: BorderSide(
              color: enabled
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.line,
            ),
            shape: const StadiumBorder(),
          ),
          onPressed: enabled ? onTap : null,
          icon: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: enabled ? AppColors.primary : AppColors.text3,
                  ),
                )
              : const Icon(Icons.fingerprint, size: 22),
          label: Text(
            busy ? 'Waiting…' : label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? AppColors.primary : AppColors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  const _PinPad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, bool isAction = false}) {
      return SizedBox(
        width: 76,
        height: 56,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Center(
            child: isAction
                ? Icon(
                    Icons.backspace_outlined,
                    color: enabled ? AppColors.text2 : AppColors.text3,
                    semanticLabel: 'Delete digit',
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: enabled ? AppColors.text : AppColors.text3,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in row) key(d, onTap: () => onDigit(d)),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 76, height: 56),
            key('0', onTap: () => onDigit('0')),
            key('', onTap: onBackspace, isAction: true),
          ],
        ),
      ],
    );
  }
}

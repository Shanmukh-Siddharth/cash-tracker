/// Lock-screen biometric trigger lifecycle (widget tests with fakes).
///
/// Regression cover for "BIOMETRIC NEVER PROMPTS": the auto-attempt used to
/// run only in `_initMode`, but first launch takes the PIN-setup path (no
/// attempt after setup) and the same State persisted across later locks, so
/// no fresh attempt ever fired.
///
/// Covered:
/// - completing PIN setup flips to enter and auto-fires one attempt;
/// - a NEW lock session (false→true) resets the one-shot guard and
///   re-attempts exactly once;
/// - a throwing backend degrades to the PIN fallback (status text, still
///   locked, never crashes).
library;

import 'package:finance_tracker/features/lock/biometric_auth.dart';
import 'package:finance_tracker/features/lock/lock_screen.dart';
import 'package:finance_tracker/features/lock/lock_service.dart';
import 'package:finance_tracker/features/lock/pin_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [BiometricAuth] fake: counts `authenticate` calls.
class FakeBiometricAuth implements BiometricAuth {
  bool canCheck = true;
  bool deviceSupported = true;
  bool nextResult = true;
  bool throwOnAuthenticate = false;
  int authenticateCalls = 0;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    bool biometricOnly = false,
  }) async {
    authenticateCalls++;
    if (throwOnAuthenticate) throw Exception('no biometric hardware');
    return nextResult;
  }
}

/// In-memory secure-storage backend behind the platform channel.
void _mockSecureStorage(Map<String, String> backing) {
  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    final args = (call.arguments as Map?)?.cast<Object?, Object?>() ?? {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return backing[key];
      case 'write':
        backing[args['key'] as String] = args['value'] as String;
        return null;
      case 'delete':
        backing.remove(key);
        return null;
      case 'deleteAll':
        backing.clear();
        return null;
      case 'readAll':
        return Map<String, String>.of(backing);
      case 'containsKey':
        return backing.containsKey(key);
      default:
        return null;
    }
  });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
}

Future<void> _pumpLock(
  WidgetTester tester,
  LockService lockService,
  FakeBiometricAuth fake,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LockScreen(
        lockService: lockService,
        pinStore: const PinStore(),
        biometricAuth: fake,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final ch in pin.split('')) {
    await tester.tap(find.text(ch));
    await tester.pump();
  }
  // The 4th digit is processed after a 120ms paint delay.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('biometric trigger lifecycle', () {
    testWidgets('completing PIN setup flips to enter + auto-fires one attempt',
        (tester) async {
      final backing = <String, String>{};
      _mockSecureStorage(backing);
      final lockService = LockService();
      addTearDown(lockService.disposeService);
      final fake = FakeBiometricAuth();

      await _pumpLock(tester, lockService, fake);
      expect(find.text('Set a 4-digit PIN'), findsOneWidget);
      expect(fake.authenticateCalls, 0); // setup path: no probe attempt yet

      await _enterPin(tester, '1234');
      expect(find.text('Confirm your PIN'), findsOneWidget);
      await _enterPin(tester, '1234');

      expect(fake.authenticateCalls, 1,
          reason: 'setup-complete must auto-fire _tryBiometric once');
      expect(lockService.locked.value, isFalse,
          reason: 'fake backend succeeds, so setup unlocks via biometrics');
    });

    testWidgets('a new lock session (false→true) re-attempts exactly once',
        (tester) async {
      final backing = <String, String>{
        PinStore.pinKey: PinStore.hashPin('1234'),
      };
      _mockSecureStorage(backing);
      final lockService = LockService();
      addTearDown(lockService.disposeService);
      final fake = FakeBiometricAuth();

      await _pumpLock(tester, lockService, fake);
      // First session (cold start with a PIN) auto-attempts once.
      expect(fake.authenticateCalls, 1);
      expect(lockService.locked.value, isFalse);

      // Same State, new lock session: guard resets, one fresh attempt.
      lockService.lock();
      await tester.pumpAndSettle();
      expect(fake.authenticateCalls, 2,
          reason: 'false→true must reset the guard and re-attempt once');
      expect(lockService.locked.value, isFalse);

      // Steady locked-state rebuilds must NOT pile on extra attempts.
      await tester.pumpAndSettle();
      expect(fake.authenticateCalls, 2);
    });

    testWidgets('throwing backend falls back to PIN, never crashes',
        (tester) async {
      final backing = <String, String>{
        PinStore.pinKey: PinStore.hashPin('1234'),
      };
      _mockSecureStorage(backing);
      final lockService = LockService();
      addTearDown(lockService.disposeService);
      final fake = FakeBiometricAuth()..throwOnAuthenticate = true;

      await _pumpLock(tester, lockService, fake);
      expect(fake.authenticateCalls, 1);
      expect(lockService.locked.value, isTrue,
          reason: 'failed biometric must not unlock');
      expect(find.text('Biometric failed — use PIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

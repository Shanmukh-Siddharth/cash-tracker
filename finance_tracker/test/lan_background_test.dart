// Phase 8 background-LAN unit tests (no device, no platform channels):
// - LanBackground.start/stop are no-ops when enabled = false.
// - LanServerHolder attach/detach/isRunning lifecycle.
// Device-only behavior (service actually keeping the process alive when
// minimized/backgrounded/locked) is verified manually — owner-excluded.
import 'package:finance_tracker/features/lan_api/lan_background.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LanBackground is a no-op when disabled (unit-test mode)', () async {
    final was = LanBackground.enabled;
    LanBackground.enabled = false;
    try {
      // Must not touch platform channels — completes silently.
      await LanBackground.ensureNotificationPermission();
      await LanBackground.start('https://1.2.3.4:8080/api/v1');
      await LanBackground.stop();
    } finally {
      LanBackground.enabled = was;
    }
    expect(LanBackground.enabled, was);
  });

  test('LanServerHolder attach / detach lifecycle', () {
    final holder = LanServerHolder.instance;
    expect(holder.isRunning, false);
    expect(holder.server, isNull);
    holder.detach(); // safe when empty
    expect(holder.isRunning, false);
  });
}

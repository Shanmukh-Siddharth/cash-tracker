/// Foreground-service wrapper for the LAN API (Phase 8).
///
/// When the LAN server starts, [LanBackground.start] launches a low-
/// importance `dataSync` foreground service (channel "NEB LAN API") so
/// Android keeps the process alive while minimized/backgrounded or UI
/// locked. The server then runs until the user taps Stop or the process is
/// killed (service is NOT sticky — `stopWithTask="true"` in the manifest).
///
/// Token-per-start, subnet guard, HTTPS and rate limiting are unchanged.
///
/// Test seam: unit tests set [enabled] = false so the platform service is
/// never started; device-only behavior is verified manually (owner-excluded
/// from automated tests).
library;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'lan_server.dart';

/// Entry-point the service isolate calls. No-op handler: the HTTP server
/// lives in the main isolate; the service exists only to raise the process
/// priority (no periodic work, hence `eventAction: nothing()`).
@pragma('vm:entry-point')
void lanBackgroundCallback() {
  FlutterForegroundTask.setTaskHandler(_LanTaskHandler());
}

class _LanTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class LanBackground {
  /// When false, [start]/[stop] are no-ops (unit tests). Default true.
  static bool enabled = true;

  static bool _initialized = false;

  /// Android 13+ notification runtime permission (best-effort).
  static Future<void> ensureNotificationPermission() async {
    if (!enabled) return;
    try {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {
      // Permission request is best-effort; the service still starts.
    }
  }

  /// One-time channel + task configuration. Safe to call repeatedly.
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'neb_lan_api',
        channelName: 'NEB LAN API',
        channelDescription:
            'Keeps the LAN API reachable while the app is in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: true,
      ),
    );
  }

  /// Launches (or re-targets) the foreground service for [url].
  static Future<void> start(String url) async {
    if (!enabled) return;
    ensureInitialized();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'NEB LAN API running',
        notificationText: url,
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 42,
      serviceTypes: <ForegroundServiceTypes>[
        ForegroundServiceTypes.dataSync,
      ],
      notificationTitle: 'NEB LAN API running',
      notificationText: url,
      callback: lanBackgroundCallback,
    );
  }

  static Future<void> stop() async {
    if (!enabled) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

/// Process-wide holder for the running LAN server. The screen no longer owns
/// the server's lifetime: leaving the screen (or backgrounding/locking) must
/// NOT stop it, and reopening the screen re-attaches to show URL + token.
class LanServerHolder {
  LanServerHolder._();
  static final LanServerHolder instance = LanServerHolder._();

  LanApiServer? _server;
  LanApiServer? get server => _server;

  bool get isRunning => _server?.isRunning ?? false;

  void attach(LanApiServer server) => _server = server;

  void detach() => _server = null;
}

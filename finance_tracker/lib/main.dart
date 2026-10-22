import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/lock/lock_service.dart';
import 'state/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Port for foreground-service ↔ UI communication (Phase 8 background LAN).
  FlutterForegroundTask.initCommunicationPort();
  final lockService = LockService()..init();
  runApp(
    ProviderScope(
      overrides: [lockServiceProvider.overrideWithValue(lockService)],
      child: FinanceApp(lockService: lockService),
    ),
  );
}

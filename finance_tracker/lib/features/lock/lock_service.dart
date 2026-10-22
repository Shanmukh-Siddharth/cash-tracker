/// App lock state. Always locked on cold start; locks immediately when the
/// app leaves the foreground (backgrounded > 0s per Design.md §3.1).
library;

import 'package:flutter/widgets.dart';

class LockService with WidgetsBindingObserver {
  /// True until the user unlocks. Starts true on every cold start.
  final ValueNotifier<bool> locked = ValueNotifier<bool>(true);

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void disposeService() {
    WidgetsBinding.instance.removeObserver(this);
    locked.dispose();
  }

  void unlock() => locked.value = false;

  void lock() => locked.value = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      lock();
    }
  }
}

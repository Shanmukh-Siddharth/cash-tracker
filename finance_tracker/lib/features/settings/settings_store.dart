/// Settings preference keys + tiny read/write helpers (Phase 5).
///
/// Single source of truth for `last_export_at` and `biometric_enabled` so
/// the settings screen and the lock screen never disagree on key names.
library;

import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  /// ISO-8601 string of the last successful export. Absent = never exported.
  static const lastExportKey = 'last_export_at';

  /// False = PIN only, biometrics skipped. Defaults to true.
  static const biometricKey = 'biometric_enabled';

  static Future<String?> readLastExport() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastExportKey);
  }

  static Future<void> writeLastExport(String iso) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastExportKey, iso);
  }

  static Future<bool> readBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(biometricKey) ?? true;
  }

  static Future<void> writeBiometric(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(biometricKey, enabled);
  }

  /// Removes the last-export stamp (used by Reset-all).
  static Future<void> clearLastExport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(lastExportKey);
  }
}

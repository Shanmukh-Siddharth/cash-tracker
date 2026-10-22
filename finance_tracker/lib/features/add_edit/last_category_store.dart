/// Last-used category persistence (per txn type), same pattern as
/// [LastWalletStore]: `last_category_income` / `last_category_expense` in
/// SharedPreferences, behind [LastWalletStore]'s [IntStore]-style seam.
///
/// Uses a tiny [StringStore] so selection logic stays unit-testable.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal string key-value surface.
abstract class StringStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
}

/// SharedPreferences-backed store for production.
class PrefsStringStore implements StringStore {
  final SharedPreferences _prefs;
  const PrefsStringStore(this._prefs);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
}

/// In-memory fake for unit tests.
class FakeStringStore implements StringStore {
  final Map<String, String> _map = <String, String>{};

  @override
  String? getString(String key) => _map[key];

  @override
  Future<void> setString(String key, String value) async {
    _map[key] = value;
  }
}

/// Reads/writes the last-used category per type.
class LastCategoryStore {
  static const incomeKey = 'last_category_income';
  static const expenseKey = 'last_category_expense';

  final StringStore _store;
  const LastCategoryStore(this._store);

  /// Production constructor.
  static Future<LastCategoryStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LastCategoryStore(PrefsStringStore(prefs));
  }

  static String keyFor(bool income) => income ? incomeKey : expenseKey;

  String? read(bool income) => _store.getString(keyFor(income));

  Future<void> write(bool income, String category) =>
      _store.setString(keyFor(income), category);
}

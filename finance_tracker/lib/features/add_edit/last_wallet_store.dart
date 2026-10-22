/// Last-used wallet persistence (`last_wallet_id` in SharedPreferences).
///
/// Kept behind the tiny [IntStore] interface so the selection logic is
/// unit-testable with a fake (no widget/plugin tests allowed).
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal int key-value surface. Real app uses [PrefsIntStore], tests use
/// [FakeIntStore].
abstract class IntStore {
  int? getInt(String key);
  Future<void> setInt(String key, int value);
}

/// SharedPreferences-backed store for production.
class PrefsIntStore implements IntStore {
  final SharedPreferences _prefs;
  const PrefsIntStore(this._prefs);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
}

/// In-memory fake for unit tests.
class FakeIntStore implements IntStore {
  final Map<String, int> _map = <String, int>{};

  @override
  int? getInt(String key) => _map[key];

  @override
  Future<void> setInt(String key, int value) async {
    _map[key] = value;
  }
}

/// Reads/writes the last-used wallet id and resolves the default selection.
class LastWalletStore {
  static const storageKey = 'last_wallet_id';

  final IntStore _store;
  const LastWalletStore(this._store);

  /// Production constructor.
  static Future<LastWalletStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LastWalletStore(PrefsIntStore(prefs));
  }

  int? read() => _store.getInt(storageKey);

  Future<void> write(int walletId) => _store.setInt(storageKey, walletId);
}

/// Picks the wallet id to preselect: last-used when it still exists,
/// otherwise the first wallet, otherwise null (no wallets at all).
int? resolveDefaultWallet(List<({int id})> wallets, int? lastId) {
  if (wallets.isEmpty) return null;
  if (lastId != null && wallets.any((w) => w.id == lastId)) return lastId;
  return wallets.first.id;
}

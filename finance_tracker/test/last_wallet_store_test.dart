// Unit tests for last-used wallet persistence (fake store, no plugins).
import 'package:finance_tracker/features/add_edit/last_wallet_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LastWalletStore', () {
    test('reads null before any write', () {
      final store = LastWalletStore(FakeIntStore());
      expect(store.read(), isNull);
    });

    test('write then read round-trips the wallet id', () async {
      final store = LastWalletStore(FakeIntStore());
      await store.write(2);
      expect(store.read(), 2);
      await store.write(3);
      expect(store.read(), 3);
    });

    test('storage key is last_wallet_id', () {
      expect(LastWalletStore.storageKey, 'last_wallet_id');
    });
  });

  group('resolveDefaultWallet', () {
    test('prefers last-used when it still exists', () {
      expect(
        resolveDefaultWallet(const [(id: 1), (id: 2)], 2),
        2,
      );
    });

    test('falls back to first wallet when last-used is gone', () {
      expect(
        resolveDefaultWallet(const [(id: 1), (id: 2)], 99),
        1,
      );
    });

    test('falls back to first wallet when nothing stored', () {
      expect(
        resolveDefaultWallet(const [(id: 1), (id: 2)], null),
        1,
      );
    });

    test('returns null when there are no wallets', () {
      expect(resolveDefaultWallet(const <({int id})>[], 1), isNull);
    });
  });
}

/// Wallet reads. All balance writes go through [TxnRepo] inside DB
/// transactions — never UPDATE wallets from UI.
library;

import 'package:sqflite/sqflite.dart';

import '../models/wallet.dart';

class WalletRepo {
  final DatabaseExecutor db;
  const WalletRepo(this.db);

  Future<List<Wallet>> listWallets() async {
    final rows = await db.query('wallets', orderBy: 'id ASC');
    return rows.map(Wallet.fromMap).toList();
  }

  Future<Wallet?> getWallet(int id) async {
    final rows = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Wallet.fromMap(rows.first);
  }

  /// Adjusts a wallet balance. Must only be called inside a DB transaction
  /// owned by [TxnRepo] so balance + txn row stay in sync.
  Future<void> adjustBalance(
    DatabaseExecutor txn,
    int walletId,
    int deltaPaise,
  ) async {
    await txn.rawUpdate(
      'UPDATE wallets SET balance = balance + ? WHERE id = ?',
      <Object?>[deltaPaise, walletId],
    );
  }
}

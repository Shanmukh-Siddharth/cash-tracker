/// Transaction writes with balance integrity.
///
/// Every write runs in a single DB transaction: INSERT/UPDATE/DELETE the txn
/// row plus adjust the wallet balance, so a crash can never half-apply.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/money.dart';
import '../categories.dart';
import '../models/transaction.dart';

/// Thrown when an expense exceeds the selected wallet balance.
class InsufficientBalance implements Exception {
  final int availablePaise;
  final String walletName;

  const InsufficientBalance({
    required this.availablePaise,
    required this.walletName,
  });

  @override
  String toString() =>
      'Not enough in $walletName. Available: ${formatPaise(availablePaise)}';
}

/// Today's summed income/expense, in paise.
class TodayTotals {
  final int incomePaise;
  final int expensePaise;

  const TodayTotals({required this.incomePaise, required this.expensePaise});
}

class TxnRepo {
  final Database db;
  const TxnRepo(this.db);

  void _checkInput({required int amountPaise, required String fromFor}) {
    if (amountPaise <= 0) {
      throw ArgumentError('Amount must be > 0 paise');
    }
    if (fromFor.trim().isEmpty) {
      throw ArgumentError('From/For must not be empty');
    }
  }

  /// Null/blank → list-tail default; unknown → [ArgumentError] (the LAN
  /// layer maps this to 422 `invalid_category`).
  String _resolveCategory(String? category, {required bool income}) {
    final trimmed = category?.trim() ?? '';
    if (trimmed.isEmpty) return defaultCategory(income);
    if (!isValidCategory(trimmed, income: income)) {
      throw ArgumentError('Unknown category: $trimmed');
    }
    return trimmed;
  }

  Future<Map<String, Object?>> _requireWallet(
    DatabaseExecutor txn,
    int walletId,
  ) async {
    final rows = await txn.query(
      'wallets',
      where: 'id = ?',
      whereArgs: <Object?>[walletId],
      limit: 1,
    );
    if (rows.isEmpty) throw ArgumentError('Unknown wallet id $walletId');
    return rows.first;
  }

  String _nowIso(DateTime? date) =>
      (date ?? DateTime.now()).toIso8601String();

  /// Adds income: INSERT txn + increase wallet balance.
  Future<int> addIncome({
    required int walletId,
    required int amountPaise,
    required String fromFor,
    String? note,
    String? category,
    DateTime? date,
  }) async {
    _checkInput(amountPaise: amountPaise, fromFor: fromFor);
    final iso = _nowIso(date);
    final cat = _resolveCategory(category, income: true);
    return db.transaction<int>((txn) async {
      await _requireWallet(txn, walletId);
      final id = await txn.insert('transactions', <String, Object?>{
        'wallet_id': walletId,
        'type': 'income',
        'amount': amountPaise,
        'from_for': fromFor.trim(),
        'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
        'category': cat,
        'date': iso,
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance + ? WHERE id = ?',
        <Object?>[amountPaise, walletId],
      );
      return id;
    });
  }

  /// Adds expense: blocks when amount exceeds wallet balance.
  Future<int> addExpense({
    required int walletId,
    required int amountPaise,
    required String fromFor,
    String? note,
    String? category,
    DateTime? date,
  }) async {
    _checkInput(amountPaise: amountPaise, fromFor: fromFor);
    final iso = _nowIso(date);
    final cat = _resolveCategory(category, income: false);
    return db.transaction<int>((txn) async {
      final wallet = await _requireWallet(txn, walletId);
      final balance = (wallet['balance'] as num).toInt();
      if (amountPaise > balance) {
        throw InsufficientBalance(
          availablePaise: balance,
          walletName: wallet['name'] as String,
        );
      }
      final id = await txn.insert('transactions', <String, Object?>{
        'wallet_id': walletId,
        'type': 'expense',
        'amount': amountPaise,
        'from_for': fromFor.trim(),
        'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
        'category': cat,
        'date': iso,
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance - ? WHERE id = ?',
        <Object?>[amountPaise, walletId],
      );
      return id;
    });
  }

  /// Edits a txn: reverts the old effect, then applies the new one.
  /// Handles wallet changes and income<->expense switches.
  Future<void> editTxn({
    required int id,
    required int walletId,
    required TxnType type,
    required int amountPaise,
    required String fromFor,
    String? note,
    String? category,
    DateTime? date,
  }) async {
    _checkInput(amountPaise: amountPaise, fromFor: fromFor);
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Unknown transaction id $id');
      final old = Txn.fromMap(rows.first);
      // Null category = keep the stored one (legacy callers); a value is
      // validated against the lists for the NEW type.
      final cat = category == null
          ? old.category
          : _resolveCategory(category, income: type == TxnType.income);

      // 1. Revert old effect on the old wallet.
      final revertDelta =
          old.type == TxnType.income ? -old.amountPaise : old.amountPaise;
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance + ? WHERE id = ?',
        <Object?>[revertDelta, old.walletId],
      );

      // 2. Check + apply new effect on the (possibly different) wallet.
      final wallet = await _requireWallet(txn, walletId);
      if (type == TxnType.expense) {
        final balance = (wallet['balance'] as num).toInt();
        if (amountPaise > balance) {
          throw InsufficientBalance(
            availablePaise: balance,
            walletName: wallet['name'] as String,
          );
        }
      }
      await txn.update(
        'transactions',
        <String, Object?>{
          'wallet_id': walletId,
          'type': txnTypeToString(type),
          'amount': amountPaise,
          'from_for': fromFor.trim(),
          'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
          'category': cat,
          if (date != null) 'date': date.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      final applyDelta =
          type == TxnType.income ? amountPaise : -amountPaise;
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance + ? WHERE id = ?',
        <Object?>[applyDelta, walletId],
      );
    });
  }

  /// Deletes a txn and reverts its balance effect.
  Future<void> deleteTxn(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final old = Txn.fromMap(rows.first);
      final revertDelta =
          old.type == TxnType.income ? -old.amountPaise : old.amountPaise;
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance + ? WHERE id = ?',
        <Object?>[revertDelta, old.walletId],
      );
      await txn.delete('transactions', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }

  /// Single txn by id (joined with wallet name), or null. Used by the LAN
  /// API to echo a just-created transaction back with `201 + Location`.
  Future<Txn?> getTxn(int id) async {
    final rows = await db.rawQuery(
      'SELECT t.*, w.name AS wallet_name FROM transactions t '
      'JOIN wallets w ON w.id = t.wallet_id '
      'WHERE t.id = ? LIMIT 1',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return Txn.fromMap(rows.first);
  }

  /// Newest-first txns joined with wallet names (for the recent list).
  /// Default 10 = the Home list length.
  Future<List<Txn>> recentTxns({int limit = 10}) async {
    final rows = await db.rawQuery(
      'SELECT t.*, w.name AS wallet_name FROM transactions t '
      'JOIN wallets w ON w.id = t.wallet_id '
      'ORDER BY t.date DESC, t.id DESC LIMIT ?',
      <Object?>[limit],
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// All txns newest-first (for the History tab). No limit.
  Future<List<Txn>> allTxns() async {
    final rows = await db.rawQuery(
      'SELECT t.*, w.name AS wallet_name FROM transactions t '
      'JOIN wallets w ON w.id = t.wallet_id '
      'ORDER BY t.date DESC, t.id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// Today's summed income/expense in paise (local device date).
  Future<TodayTotals> todayTotals() async {
    final rows = await db.rawQuery(
      "SELECT type, SUM(amount) AS total FROM transactions "
      "WHERE date(date) = date('now', 'localtime') GROUP BY type",
    );
    var income = 0;
    var expense = 0;
    for (final row in rows) {
      final total = (row['total'] as num?)?.toInt() ?? 0;
      if (row['type'] == 'income') {
        income = total;
      } else {
        expense = total;
      }
    }
    return TodayTotals(incomePaise: income, expensePaise: expense);
  }
}

/// Track-only debt memo repo (v3). Debts NEVER touch wallet balances and
/// create NO transactions — every method here reads/writes only the
/// `debts` / `debt_payments` tables.
library;

import 'package:sqflite/sqflite.dart';

import '../models/debt.dart';

export '../models/debt.dart';

/// Thrown by [DebtRepo.addPayment] when amount exceeds the remaining balance.
/// Carries [remaining] so callers (UI, LAN) can show "Remaining: ₹X".
class DebtOverpay implements Exception {
  final int remaining;
  const DebtOverpay(this.remaining);

  @override
  String toString() => 'Payment exceeds remaining balance';
}

bool isValidDebtDirection(String v) => v == 'owe' || v == 'lent';
bool isValidDebtStatus(String v) => v == 'open' || v == 'settled';

class DebtRepo {
  final Database db;
  const DebtRepo(this.db);

  Future<int> _paidFor(DatabaseExecutor ex, int debtId) async {
    final rows = await ex.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM debt_payments WHERE debt_id = ?',
      <Object?>[debtId],
    );
    return ((rows.first['s'] as num?) ?? 0).toInt();
  }

  Future<Debt> _withPaid(Map<String, Object?> row) async {
    final id = row['id'] as int;
    return Debt.fromMap(row, paidPaise: await _paidFor(db, id));
  }

  Future<int> addDebt({
    required String person,
    required int amountPaise,
    required String direction,
    String? note,
    String? date,
  }) async {
    if (person.trim().isEmpty) throw ArgumentError('Person is required');
    if (amountPaise <= 0) throw ArgumentError('Amount must be > 0 paise');
    if (!isValidDebtDirection(direction)) {
      throw ArgumentError('direction must be owe or lent');
    }
    final now = DateTime.now().toIso8601String();
    return db.insert('debts', <String, Object?>{
      'person': person.trim(),
      'amount': amountPaise,
      'direction': direction,
      'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
      'date': date ?? now,
      'status': 'open',
      'created_at': now,
    });
  }

  Future<Debt?> getDebt(int id) async {
    final rows = await db.query('debts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _withPaid(rows.first);
  }

  /// All debts, newest first. Optional [direction] ('owe'|'lent') and
  /// [status] ('open'|'settled') filters.
  Future<List<Debt>> listDebts({String? direction, String? status}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (direction != null) {
      if (!isValidDebtDirection(direction)) {
        throw ArgumentError('direction must be owe or lent');
      }
      where.add('direction = ?');
      args.add(direction);
    }
    if (status != null) {
      if (!isValidDebtStatus(status)) throw ArgumentError('bad status');
      where.add('status = ?');
      args.add(status);
    }
    final rows = await db.query(
      'debts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'id DESC',
    );
    final out = <Debt>[];
    for (final r in rows) {
      out.add(await _withPaid(r));
    }
    return out;
  }

  /// Open debts for one direction, newest first.
  Future<List<Debt>> openDebts(String direction) =>
      listDebts(direction: direction, status: 'open');

  Future<List<DebtPayment>> paymentsFor(int debtId) async {
    final rows = await db.query(
      'debt_payments',
      where: 'debt_id = ?',
      whereArgs: <Object?>[debtId],
      orderBy: 'id ASC',
    );
    return rows.map(DebtPayment.fromMap).toList();
  }

  /// Records a payment. Throws [DebtOverpay] (with remaining) when
  /// [amountPaise] > remaining, [ArgumentError] for bad debt/amount.
  Future<int> addPayment({
    required int debtId,
    required int amountPaise,
    String? note,
    String? date,
  }) async {
    if (amountPaise <= 0) throw ArgumentError('Amount must be > 0 paise');
    final debt = await getDebt(debtId);
    if (debt == null) throw ArgumentError('Unknown debt id $debtId');
    final remaining = debt.remainingPaise;
    if (amountPaise > remaining) throw DebtOverpay(remaining);
    final now = DateTime.now().toIso8601String();
    return db.insert('debt_payments', <String, Object?>{
      'debt_id': debtId,
      'amount': amountPaise,
      'date': date ?? now,
      'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
    });
  }

  Future<void> settle(int id) async {
    final count = await db.update(
      'debts',
      <String, Object?>{'status': 'settled'},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (count == 0) throw ArgumentError('Unknown debt id $id');
  }

  /// Deletes the debt; payments cascade via FK.
  Future<void> deleteDebt(int id) async {
    await db.delete('debts', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Remaining (open-debt) totals per direction, in paise.
  Future<DebtTotals> totals() async {
    final debts = await listDebts(status: 'open');
    var owe = 0;
    var lent = 0;
    for (final d in debts) {
      if (d.isOwe) {
        owe += d.remainingPaise;
      } else {
        lent += d.remainingPaise;
      }
    }
    return DebtTotals(oweTotal: owe, lentTotal: lent);
  }

  Future<int> openCount() async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM debts WHERE status = 'open'",
    );
    return ((rows.first['n'] as num?) ?? 0).toInt();
  }
}

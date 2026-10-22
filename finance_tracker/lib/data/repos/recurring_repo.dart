/// CRUD for monthly templates (Phase 8).
///
/// Templates are inert rows: money moves only when the UI materializes one
/// into a real txn via [TxnRepo] (same validation incl. overspend), then
/// stamps [markAdded]. Table is created in v2 onCreate AND onUpgrade.
library;

import 'package:sqflite/sqflite.dart';

import '../models/recurring_template.dart';
import '../models/transaction.dart';

/// Note auto-written onto the txn a template materializes into. Owner choice
/// 2026-10-08: 'Monthly: <template name>' — no extra prompt, the note just
/// explains where the row came from (and satisfies the mandatory-note rule).
String recurringTxnNote(String templateName) =>
    'Monthly: ${templateName.trim()}';

class RecurringRepo {
  final DatabaseExecutor db;
  const RecurringRepo(this.db);

  Future<int> addTemplate({
    required String name,
    required int amountPaise,
    required int walletId,
    required TxnType type,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Name must not be empty');
    if (amountPaise <= 0) throw ArgumentError('Amount must be > 0 paise');
    final wallets = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: <Object?>[walletId],
      limit: 1,
    );
    if (wallets.isEmpty) throw ArgumentError('Unknown wallet id $walletId');
    return db.insert('recurring_templates', <String, Object?>{
      'name': name.trim(),
      'amount': amountPaise,
      'wallet_id': walletId,
      'type': txnTypeToString(type),
      'created_at': DateTime.now().toIso8601String(),
      'last_added_at': null,
    });
  }

  Future<void> updateTemplate({
    required int id,
    required String name,
    required int amountPaise,
    required int walletId,
    required TxnType type,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Name must not be empty');
    if (amountPaise <= 0) throw ArgumentError('Amount must be > 0 paise');
    final wallets = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: <Object?>[walletId],
      limit: 1,
    );
    if (wallets.isEmpty) throw ArgumentError('Unknown wallet id $walletId');
    final count = await db.update(
      'recurring_templates',
      <String, Object?>{
        'name': name.trim(),
        'amount': amountPaise,
        'wallet_id': walletId,
        'type': txnTypeToString(type),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (count == 0) throw ArgumentError('Unknown template id $id');
  }

  Future<void> deleteTemplate(int id) async {
    await db.delete(
      'recurring_templates',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// All templates oldest-first, joined with wallet names.
  Future<List<RecurringTemplate>> listTemplates() async {
    final rows = await db.rawQuery(
      'SELECT t.*, w.name AS wallet_name FROM recurring_templates t '
      'JOIN wallets w ON w.id = t.wallet_id '
      'ORDER BY t.id ASC',
    );
    return rows.map(RecurringTemplate.fromMap).toList();
  }

  Future<RecurringTemplate?> getTemplate(int id) async {
    final rows = await db.rawQuery(
      'SELECT t.*, w.name AS wallet_name FROM recurring_templates t '
      'JOIN wallets w ON w.id = t.wallet_id '
      'WHERE t.id = ? LIMIT 1',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return RecurringTemplate.fromMap(rows.first);
  }

  /// Stamps `last_added_at = now` after a successful materialization.
  Future<void> markAdded(int id) async {
    await db.update(
      'recurring_templates',
      <String, Object?>{'last_added_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}

/// Export (CSV/JSON) + JSON backup restore (Phase 5).
///
/// Money stays **int paise** in JSON; CSV renders rupees with 2 decimals.
/// [parseBackup] validates before anything is wiped; [restoreFromJson] runs
/// the wipe + reinsert + [recalculateBalances] in ONE DB transaction.
library;

import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database.dart';

/// Thrown when a backup file fails validation. Message is user-showable.
class InvalidBackup implements Exception {
  final String message;
  const InvalidBackup(this.message);

  @override
  String toString() => 'InvalidBackup: $message';
}

class ExportRepo {
  final Database db;
  const ExportRepo(this.db);

  /// SharedPreferences keys wiped by [resetAll]. `biometric_enabled` is
  /// deliberately NOT here — the biometric toggle survives a reset.
  /// Pure/testable: [clearResetPrefs] takes an optional in-memory map so
  /// unit tests never touch plugins.
  static const resetPrefKeys = <String>[
    'last_wallet_id',
    'last_category_income',
    'last_category_expense',
    'last_export_at',
  ];

  /// CSV of all txns joined with wallet names, oldest first.
  ///
  /// Header: `id,date,type,amount,from_for,wallet,note,created_at,category`
  /// (`category` appended at END, Phase 8). Amount is rupees with 2 decimals
  /// (e.g. `123.45`); quoting is handled by the `csv` package
  /// (commas/quotes in notes are escaped).
  Future<String> buildCsv() async {
    final rows = await db.rawQuery(
      'SELECT t.id AS id, t.date AS date, t.type AS type, t.amount AS amount, '
      't.from_for AS from_for, w.name AS wallet, t.note AS note, '
      't.created_at AS created_at, t.category AS category '
      'FROM transactions t '
      'JOIN wallets w ON w.id = t.wallet_id '
      'ORDER BY t.date ASC, t.id ASC',
    );
    final data = <List<dynamic>>[
      const <String>[
        'id',
        'date',
        'type',
        'amount',
        'from_for',
        'wallet',
        'note',
        'created_at',
        'category',
      ],
      for (final r in rows)
        <dynamic>[
          r['id'],
          r['date'],
          r['type'],
          _paiseToRupees((r['amount'] as num).toInt()),
          r['from_for'],
          r['wallet'],
          r['note'] ?? '',
          r['created_at'],
          r['category'] ?? 'Miscellaneous',
        ],
    ];
    return Csv(lineDelimiter: '\n').encode(data);
  }

  /// Full backup map: wallets + transactions + cart + debts/debt_payments
  /// (paise ints) plus `schema_version: 3` and `exported_at`. Caller
  /// `jsonEncode`s it to share. Transactions include `category` (v2 rows);
  /// v1 backups without it still restore (backfilled to the default).
  /// v1/v2 backups without debt keys restore with empty debts.
  Future<Map<String, dynamic>> buildJson() async {
    final wallets = await db.query('wallets', orderBy: 'id ASC');
    final txns = await db.query('transactions', orderBy: 'date ASC, id ASC');
    final cart = await db.query('cart_items', orderBy: 'id ASC');
    final debts = await db.query('debts', orderBy: 'id ASC');
    final payments = await db.query('debt_payments', orderBy: 'id ASC');
    return <String, dynamic>{
      'schema_version': 3,
      'exported_at': DateTime.now().toIso8601String(),
      'wallets': wallets.map((e) => Map<String, dynamic>.from(e)).toList(),
      'transactions': txns.map((e) => Map<String, dynamic>.from(e)).toList(),
      'cart': cart.map((e) => Map<String, dynamic>.from(e)).toList(),
      'debts': debts.map((e) => Map<String, dynamic>.from(e)).toList(),
      'debt_payments':
          payments.map((e) => Map<String, dynamic>.from(e)).toList(),
    };
  }

  /// Parses + validates a backup file. Throws [InvalidBackup] on garbage,
  /// missing keys, or wrong types — call BEFORE wiping anything.
  Map<String, dynamic> parseBackup(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const InvalidBackup('Not valid JSON');
    }
    return validateBackup(decoded);
  }

  /// Validates an already-decoded backup map. Shared by [parseBackup] and
  /// [restoreFromJson] so restores are safe even if the caller skips parsing.
  static Map<String, dynamic> validateBackup(dynamic decoded) {
    if (decoded is! Map) {
      throw const InvalidBackup('Backup must be a JSON object');
    }
    final map = Map<String, dynamic>.from(decoded);
    for (final key in const ['wallets', 'transactions', 'cart']) {
      if (map[key] is! List) {
        throw InvalidBackup('Missing or invalid "$key"');
      }
    }
    if (map.containsKey('schema_version') &&
        map['schema_version'] != 1 &&
        map['schema_version'] != 2 &&
        map['schema_version'] != 3) {
      throw const InvalidBackup('Unsupported schema_version');
    }
    for (final w in map['wallets'] as List) {
      _checkWallet(w);
    }
    for (final t in map['transactions'] as List) {
      _checkTxn(t);
    }
    for (final c in map['cart'] as List) {
      _checkCart(c);
    }
    // Debt keys are optional (v1/v2 backups predate them → backfill empty).
    if (map.containsKey('debts') || map.containsKey('debt_payments')) {
      if (map['debts'] is! List || map['debt_payments'] is! List) {
        throw const InvalidBackup('Missing or invalid "debts"');
      }
      for (final d in map['debts'] as List) {
        _checkDebt(d);
      }
      for (final p in map['debt_payments'] as List) {
        _checkDebtPayment(p);
      }
    }
    return map;
  }

  /// Restores a validated backup in ONE DB txn: wipe all tables (incl.
  /// debts), reinsert rows (ids preserved so wallet links hold), then
  /// [recalculateBalances]. Fixes a dangling `last_wallet_id` after.
  Future<void> restoreFromJson(Map<String, dynamic> backup) async {
    final data = validateBackup(backup);
    final wallets = (data['wallets'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final txns = (data['transactions'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cart = (data['cart'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final debts = ((data['debts'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final debtPayments = ((data['debt_payments'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final walletIds = wallets.map((w) => w['id']).toSet();
    for (final t in txns) {
      if (!walletIds.contains(t['wallet_id'])) {
        throw InvalidBackup(
          'Transaction references unknown wallet ${t['wallet_id']}',
        );
      }
    }
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('cart_items');
      await txn.delete('debt_payments');
      await txn.delete('debts');
      await txn.delete('wallets');
      for (final w in wallets) {
        await txn.insert('wallets', <String, Object?>{
          'id': w['id'],
          'name': w['name'],
          'balance': 0, // rebuilt by recalculateBalances below
          'created_at': w['created_at'],
        });
      }
      for (final t in txns) {
        await txn.insert('transactions', <String, Object?>{
          if (t['id'] is int) 'id': t['id'],
          'wallet_id': t['wallet_id'],
          'type': t['type'],
          'amount': t['amount'],
          'from_for': t['from_for'],
          'note': t['note'],
          'category': (t['category'] as String?) ?? 'Miscellaneous',
          'date': t['date'],
          'created_at': t['created_at'],
        });
      }
      for (final c in cart) {
        await txn.insert('cart_items', <String, Object?>{
          if (c['id'] is int) 'id': c['id'],
          'name': c['name'],
          'price': c['price'],
          'qty': c['qty'],
          'added_at': c['added_at'],
        });
      }
      for (final d in debts) {
        await txn.insert('debts', <String, Object?>{
          if (d['id'] is int) 'id': d['id'],
          'person': d['person'],
          'amount': d['amount'],
          'direction': d['direction'],
          'note': d['note'],
          'date': d['date'],
          'status': (d['status'] as String?) ?? 'open',
          'created_at': d['created_at'],
        });
      }
      final debtIds =
          debts.where((d) => d['id'] is int).map((d) => d['id']).toSet();
      for (final p in debtPayments) {
        if (p['debt_id'] is! int || !debtIds.contains(p['debt_id'])) {
          throw InvalidBackup(
            'Debt payment references unknown debt ${p['debt_id']}',
          );
        }
        await txn.insert('debt_payments', <String, Object?>{
          if (p['id'] is int) 'id': p['id'],
          'debt_id': p['debt_id'],
          'amount': p['amount'],
          'date': p['date'],
          'note': p['note'],
        });
      }
      await recalculateBalances(txn);
    });
    await _fixLastWallet();
  }

  /// Wipes everything (incl. debts) and reseeds the default wallets. Also
  /// clears the resettable prefs ([resetPrefKeys]) — last wallet, last
  /// categories, last export — but keeps `biometric_enabled`. The app PIN
  /// lives in secure storage and is cleared by the caller via
  /// [PinStore.clearPin] (untestable in unit tests — device-verified).
  /// Caller refreshes UI and forces `lockService.lock()` so the lock gate
  /// re-probes into PIN-SETUP mode. Migration-safe: tables are deleted, not
  /// dropped, so re-seed works on any schema version.
  Future<void> resetAll() async {
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('cart_items');
      await txn.delete('debt_payments');
      await txn.delete('debts');
      await txn.delete('wallets');
      await seedDefaultWallets(txn);
    });
    await clearResetPrefs();
  }

  /// Removes every key in [resetPrefKeys] from SharedPreferences.
  /// Best-effort: prefs may be unavailable in some test setups — skips then.
  Future<void> clearResetPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in resetPrefKeys) {
        await prefs.remove(key);
      }
    } catch (_) {
      // SharedPreferences unavailable (e.g. unit tests) — skip.
    }
  }

  /// Clears `last_wallet_id` when it dangles, rewriting it to the first
  /// wallet when one exists. Best-effort: prefs may be unavailable in tests.
  Future<void> _fixLastWallet() async {
    try {
      const key = 'last_wallet_id'; // LastWalletStore.storageKey
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(key);
      if (last == null) return;
      final rows = await db.query(
        'wallets',
        where: 'id = ?',
        whereArgs: <Object?>[last],
        limit: 1,
      );
      if (rows.isNotEmpty) return;
      await prefs.remove(key);
      final first = await db.query('wallets', orderBy: 'id ASC', limit: 1);
      if (first.isNotEmpty) {
        await prefs.setInt(key, (first.first['id'] as num).toInt());
      }
    } catch (_) {
      // SharedPreferences unavailable (e.g. unit tests) — skip fixup.
    }
  }

  static void _checkWallet(dynamic entry) {
    if (entry is! Map) {
      throw const InvalidBackup('Wallet entry must be an object');
    }
    final w = entry;
    if (w['id'] is! int) {
      throw const InvalidBackup('Wallet is missing a valid id');
    }
    if (w['name'] is! String ||
        (w['name'] as String).trim().isEmpty) {
      throw const InvalidBackup('Wallet has a bad name');
    }
    if (w['balance'] is! int) {
      throw const InvalidBackup('Wallet balance must be paise int');
    }
    if (w['created_at'] is! String) {
      throw const InvalidBackup('Wallet is missing created_at');
    }
  }

  static void _checkTxn(dynamic entry) {
    if (entry is! Map) {
      throw const InvalidBackup('Transaction entry must be an object');
    }
    final t = entry;
    if (t['wallet_id'] is! int) {
      throw const InvalidBackup('Transaction is missing wallet_id');
    }
    if (t['type'] != 'income' && t['type'] != 'expense') {
      throw const InvalidBackup('Transaction has a bad type');
    }
    if (t['amount'] is! int || (t['amount'] as int) <= 0) {
      throw const InvalidBackup('Transaction amount must be paise int > 0');
    }
    if (t['from_for'] is! String ||
        (t['from_for'] as String).trim().isEmpty) {
      throw const InvalidBackup('Transaction is missing from_for');
    }
    if (t['date'] is! String || DateTime.tryParse(t['date'] as String) == null) {
      throw const InvalidBackup('Transaction has a bad date');
    }
    if (t['created_at'] is! String) {
      throw const InvalidBackup('Transaction is missing created_at');
    }
    if (t['note'] != null && t['note'] is! String) {
      throw const InvalidBackup('Transaction has a bad note');
    }
    // v1 backups have no category — backfilled on restore. v2 rows carry a
    // plain string (validated against the lists only on live writes).
    if (t['category'] != null && t['category'] is! String) {
      throw const InvalidBackup('Transaction has a bad category');
    }
  }

  static void _checkCart(dynamic entry) {
    if (entry is! Map) {
      throw const InvalidBackup('Cart entry must be an object');
    }
    final c = entry;
    if (c['name'] is! String || (c['name'] as String).trim().isEmpty) {
      throw const InvalidBackup('Cart item has a bad name');
    }
    if (c['price'] is! int || (c['price'] as int) <= 0) {
      throw const InvalidBackup('Cart price must be paise int > 0');
    }
    if (c['qty'] is! int || (c['qty'] as int) <= 0) {
      throw const InvalidBackup('Cart qty must be int > 0');
    }
    if (c['added_at'] is! String) {
      throw const InvalidBackup('Cart item is missing added_at');
    }
  }

  static void _checkDebt(dynamic entry) {
    if (entry is! Map) {
      throw const InvalidBackup('Debt entry must be an object');
    }
    final d = entry;
    if (d['person'] is! String || (d['person'] as String).trim().isEmpty) {
      throw const InvalidBackup('Debt is missing person');
    }
    if (d['amount'] is! int || (d['amount'] as int) <= 0) {
      throw const InvalidBackup('Debt amount must be paise int > 0');
    }
    if (d['direction'] != 'owe' && d['direction'] != 'lent') {
      throw const InvalidBackup('Debt has a bad direction');
    }
    if (d['date'] is! String ||
        DateTime.tryParse(d['date'] as String) == null) {
      throw const InvalidBackup('Debt has a bad date');
    }
    if (d['created_at'] is! String) {
      throw const InvalidBackup('Debt is missing created_at');
    }
    if (d['note'] != null && d['note'] is! String) {
      throw const InvalidBackup('Debt has a bad note');
    }
    if (d['status'] != null &&
        d['status'] != 'open' &&
        d['status'] != 'settled') {
      throw const InvalidBackup('Debt has a bad status');
    }
  }

  static void _checkDebtPayment(dynamic entry) {
    if (entry is! Map) {
      throw const InvalidBackup('Debt payment entry must be an object');
    }
    final p = entry;
    if (p['debt_id'] is! int) {
      throw const InvalidBackup('Debt payment is missing debt_id');
    }
    if (p['amount'] is! int || (p['amount'] as int) <= 0) {
      throw const InvalidBackup('Debt payment amount must be paise int > 0');
    }
    if (p['date'] is! String ||
        DateTime.tryParse(p['date'] as String) == null) {
      throw const InvalidBackup('Debt payment has a bad date');
    }
    if (p['note'] != null && p['note'] is! String) {
      throw const InvalidBackup('Debt payment has a bad note');
    }
  }
}

/// Paise int -> rupees string with exactly 2 decimals (integer math, no
/// float). Amounts are always > 0 in our tables.
String _paiseToRupees(int paise) {
  final rupees = paise ~/ 100;
  final frac = (paise % 100).toString().padLeft(2, '0');
  return '$rupees.$frac';
}

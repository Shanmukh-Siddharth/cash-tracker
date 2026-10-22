/// SQLite setup: open `finance.db`, create schema v3, seed wallets.
///
/// Money is stored as **int paise**. Balance changes must go through the
/// repos (which use DB transactions) — never UPDATE wallets from UI.
///
/// v2 adds `transactions.category` (default 'Miscellaneous', backfilled for
/// v1 rows) and the `recurring_templates` table. [recalculateBalances] is
/// untouched.
///
/// v3 adds the track-only debt memo tables (`debts`, `debt_payments`).
/// Debts NEVER touch wallet balances and create NO transactions.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Default wallets seeded on first run. Balances stored as int paise.
const List<String> defaultWalletNames = <String>['Cash', 'UPI', 'Bank'];

/// App-wide singleton for the production database.
///
/// Tests bypass this and call [openAppDatabase] with an in-memory path.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await openAppDatabase();
    _db = opened;
    return opened;
  }
}

/// Opens (and creates on first run) the app database.
///
/// Pass [path] to override the file location (tests use an in-memory path).
Future<Database> openAppDatabase({String? path}) async {
  final dbPath = path ?? p.join(await getDatabasesPath(), 'finance.db');
  return openDatabase(
    dbPath,
    version: 3,
    onConfigure: (Database db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (Database db, int version) async {
      await createSchema(db);
      await seedDefaultWallets(db);
    },
    onUpgrade: (Database db, int oldVersion, int newVersion) async {
      if (oldVersion < 2) {
        // Existing v1 rows keep working; the default backfills the column.
        await db.execute(
          "ALTER TABLE transactions ADD COLUMN category TEXT NOT NULL DEFAULT 'Miscellaneous'",
        );
        await createRecurringTemplatesTable(db);
      }
      if (oldVersion < 3) {
        await createDebtTables(db);
      }
    },
  );
}

/// Creates wallets / transactions / cart_items / recurring_templates tables
/// (current schema, v3 — debts included).
Future<void> createSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE wallets(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      balance INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      wallet_id INTEGER NOT NULL REFERENCES wallets(id),
      type TEXT NOT NULL CHECK(type IN ('income','expense')),
      amount INTEGER NOT NULL CHECK(amount > 0),
      from_for TEXT NOT NULL,
      note TEXT,
      category TEXT NOT NULL DEFAULT 'Miscellaneous',
      date TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_txns_date ON transactions(date)');
  await db.execute('CREATE INDEX idx_txns_wallet ON transactions(wallet_id)');
  await db.execute('''
    CREATE TABLE cart_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      price INTEGER NOT NULL CHECK(price > 0),
      qty INTEGER NOT NULL DEFAULT 1 CHECK(qty > 0),
      added_at TEXT NOT NULL
    )
  ''');
  await createRecurringTemplatesTable(db);
  await createDebtTables(db);
}

/// User-triggered monthly templates. No scheduler reads this table — rows
/// are materialized into real txns only via explicit [+ Add] / Add-all-due.
Future<void> createRecurringTemplatesTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS recurring_templates(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount > 0),
      wallet_id INTEGER NOT NULL REFERENCES wallets(id),
      type TEXT NOT NULL CHECK(type IN ('income','expense')),
      created_at TEXT NOT NULL,
      last_added_at TEXT
    )
  ''');
}

/// Track-only debt memo tables (v3). NEVER touches wallets/transactions.
/// `direction`: 'owe' (I owe them) | 'lent'. `status`: 'open' | 'settled'.
/// `remaining = amount - SUM(payments)` is computed in the repo.
Future<void> createDebtTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS debts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      person TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount > 0),
      direction TEXT NOT NULL CHECK(direction IN ('owe','lent')),
      note TEXT,
      date TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','settled')),
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS debt_payments(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      debt_id INTEGER NOT NULL REFERENCES debts(id) ON DELETE CASCADE,
      amount INTEGER NOT NULL CHECK(amount > 0),
      date TEXT NOT NULL,
      note TEXT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_status ON debts(status)');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_debt_payments_debt ON debt_payments(debt_id)',
  );
}

/// Inserts Cash/UPI/Bank with balance 0 when the wallets table is empty.
Future<void> seedDefaultWallets(DatabaseExecutor db) async {
  final count =
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM wallets')) ??
          0;
  if (count > 0) return;
  final now = DateTime.now().toIso8601String();
  for (final name in defaultWalletNames) {
    await db.insert('wallets', <String, Object?>{
      'name': name,
      'balance': 0,
      'created_at': now,
    });
  }
}

/// Rebuilds every wallet balance from transactions. Used after import/reset.
Future<void> recalculateBalances(DatabaseExecutor db) async {
  await db.update('wallets', <String, Object?>{'balance': 0});
  final rows = await db.rawQuery(
    'SELECT wallet_id, type, SUM(amount) AS total '
    'FROM transactions GROUP BY wallet_id, type',
  );
  for (final row in rows) {
    final total = (row['total'] as num).toInt();
    final delta = row['type'] == 'income' ? total : -total;
    await db.rawUpdate(
      'UPDATE wallets SET balance = balance + ? WHERE id = ?',
      <Object?>[delta, row['wallet_id']],
    );
  }
}

// Phase 8 category tests (sqflite_common_ffi + pure logic):
// const lists (tails last), defaults, repo store/default/validate,
// editTxn change + preserve, v1-row backfill, expenseByCategory ordering,
// LastCategoryStore per-type persistence, query matches category.
import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/categories.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repos/stats_repo.dart';
import 'package:finance_tracker/data/repos/txn_repo.dart';
import 'package:finance_tracker/data/repos/wallet_repo.dart';
import 'package:finance_tracker/features/add_edit/last_category_store.dart';
import 'package:finance_tracker/features/history/grouping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openTestDb() =>
    openAppDatabase(path: inMemoryDatabasePath);

Future<int> _walletId(WalletRepo repo, String name) async {
  final wallets = await repo.listWallets();
  return wallets.firstWhere((w) => w.name == name).id!;
}

Txn _txn({required DateTime date, String category = 'Food'}) {
  final iso = date.toIso8601String();
  return Txn(
    walletId: 1,
    type: TxnType.expense,
    amountPaise: 1000,
    fromFor: 'Lunch',
    date: iso,
    createdAt: iso,
    category: category,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('category lists', () {
    test('expense tails Miscellaneous, income tails Other', () {
      expect(expenseCategories.last, 'Miscellaneous');
      expect(incomeCategories.last, 'Other');
      expect(expenseCategories, hasLength(12));
      expect(incomeCategories, hasLength(5));
    });

    test('defaults + validation follow the txn side', () {
      expect(defaultCategory(true), 'Other');
      expect(defaultCategory(false), 'Miscellaneous');
      expect(isValidCategory('Food', income: false), true);
      expect(isValidCategory('Salary', income: true), true);
      expect(isValidCategory('Salary', income: false), false);
      expect(isValidCategory('Food', income: true), false);
      expect(isValidCategory('Nope', income: false), false);
    });
  });

  group('txn_repo categories', () {
    late Database db;
    late WalletRepo wallets;
    late TxnRepo txns;

    setUp(() async {
      db = await _openTestDb();
      wallets = WalletRepo(db);
      txns = TxnRepo(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('stores the given category on add', () async {
      final cash = await _walletId(wallets, 'Cash');
      await txns.addIncome(
        walletId: cash,
        amountPaise: 50000,
        fromFor: 'Job',
        note: 'pay',
      );
      final id = await txns.addExpense(
        walletId: cash,
        amountPaise: 1000,
        fromFor: 'Lunch',
        note: 'team lunch',
        category: 'Food',
      );
      expect((await txns.getTxn(id))!.category, 'Food');
      final iid = await txns.addIncome(
        walletId: cash,
        amountPaise: 5000,
        fromFor: 'Job',
        note: 'pay',
        category: 'Salary',
      );
      expect((await txns.getTxn(iid))!.category, 'Salary');
    });

    test('missing category defaults to the list tail', () async {
      final cash = await _walletId(wallets, 'Cash');
      await txns.addIncome(
        walletId: cash,
        amountPaise: 50000,
        fromFor: 'Job',
        note: 'pay',
      );
      final eid = await txns.addExpense(
        walletId: cash,
        amountPaise: 1000,
        fromFor: 'x',
        note: 'x',
      );
      expect((await txns.getTxn(eid))!.category, 'Miscellaneous');
      final iid = await txns.addIncome(
        walletId: cash,
        amountPaise: 1000,
        fromFor: 'x',
        note: 'x',
      );
      // Income default is Other.
      expect((await txns.getTxn(iid))!.category, 'Other');
    });

    test('unknown category throws ArgumentError', () async {
      final cash = await _walletId(wallets, 'Cash');
      expect(
        () => txns.addExpense(
          walletId: cash,
          amountPaise: 1000,
          fromFor: 'x',
          note: 'x',
          category: 'Nope',
        ),
        throwsArgumentError,
      );
      // Cross-list is also rejected.
      expect(
        () => txns.addExpense(
          walletId: cash,
          amountPaise: 1000,
          fromFor: 'x',
          note: 'x',
          category: 'Salary',
        ),
        throwsArgumentError,
      );
    });

    test('editTxn changes the category, null keeps the stored one', () async {
      final cash = await _walletId(wallets, 'Cash');
      await txns.addIncome(
        walletId: cash,
        amountPaise: 50000,
        fromFor: 'Job',
        note: 'pay',
      );
      final id = await txns.addExpense(
        walletId: cash,
        amountPaise: 1000,
        fromFor: 'x',
        note: 'x',
        category: 'Food',
      );
      await txns.editTxn(
        id: id,
        walletId: cash,
        type: TxnType.expense,
        amountPaise: 1000,
        fromFor: 'x',
        note: 'y',
        category: 'Travel',
      );
      expect((await txns.getTxn(id))!.category, 'Travel');
      // Legacy call without category preserves the stored value.
      await txns.editTxn(
        id: id,
        walletId: cash,
        type: TxnType.expense,
        amountPaise: 1000,
        fromFor: 'x',
        note: 'z',
      );
      final kept = (await txns.getTxn(id))!;
      expect(kept.category, 'Travel');
      expect(kept.note, 'z');
    });

    test('v1 row without the column backfills to the default', () async {
      final cash = await _walletId(wallets, 'Cash');
      final now = DateTime.now().toIso8601String();
      // Simulate a v1 row: delete + recreate the table without category.
      await db.execute('DROP TABLE transactions');
      await db.execute('''
        CREATE TABLE transactions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          wallet_id INTEGER NOT NULL REFERENCES wallets(id),
          type TEXT NOT NULL CHECK(type IN ('income','expense')),
          amount INTEGER NOT NULL CHECK(amount > 0),
          from_for TEXT NOT NULL,
          note TEXT,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.insert('transactions', <String, Object?>{
        'wallet_id': cash,
        'type': 'expense',
        'amount': 500,
        'from_for': 'Old',
        'note': null,
        'date': now,
        'created_at': now,
      });
      final all = await txns.allTxns();
      expect(all.single.category, 'Miscellaneous');
    });

    test('expenseByCategory groups largest-first', () async {
      final cash = await _walletId(wallets, 'Cash');
      await txns.addIncome(
        walletId: cash,
        amountPaise: 100000,
        fromFor: 'Job',
        note: 'pay',
        category: 'Salary',
      );
      await txns.addExpense(
        walletId: cash,
        amountPaise: 3000,
        fromFor: 'a',
        note: 'a',
        category: 'Food',
      );
      await txns.addExpense(
        walletId: cash,
        amountPaise: 7000,
        fromFor: 'b',
        note: 'b',
        category: 'Travel',
      );
      await txns.addExpense(
        walletId: cash,
        amountPaise: 1000,
        fromFor: 'c',
        note: 'c',
        category: 'Food',
      );
      final shares = await StatsRepo(db).expenseByCategory();
      expect(shares.map((s) => s.category), ['Travel', 'Food']);
      expect(shares.map((s) => s.expensePaise), [7000, 4000]);
    });
  });

  group('last_category_store', () {
    test('per-type read/write with fake store', () async {
      final store = LastCategoryStore(FakeStringStore());
      expect(store.read(true), isNull);
      await store.write(false, 'Food');
      expect(store.read(false), 'Food');
      expect(store.read(true), isNull); // income untouched
      await store.write(true, 'Salary');
      expect(store.read(true), 'Salary');
    });
  });

  group('query matches category', () {
    test('txnMatchesQuery hits category case-insensitively', () {
      final txn = _txn(date: DateTime(2026, 10, 8), category: 'Food');
      expect(txnMatchesQuery(txn, 'food'), isTrue);
      expect(txnMatchesQuery(txn, 'FOO'), isTrue);
      expect(txnMatchesQuery(txn, 'rent'), isFalse);
    });
  });
}

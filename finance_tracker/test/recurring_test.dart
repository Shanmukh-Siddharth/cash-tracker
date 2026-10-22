// Phase 8 recurring-template tests (sqflite_common_ffi):
// CRUD + validation, markAdded stamping, isDue (never / old / recent),
// materialize-through-txn_repo (balance exact, last_added_at stamped),
// overspend materialization fails with nothing added and stamp untouched.
import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repos/recurring_repo.dart';
import 'package:finance_tracker/data/repos/txn_repo.dart';
import 'package:finance_tracker/data/repos/wallet_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openTestDb() =>
    openAppDatabase(path: inMemoryDatabasePath);

Future<int> _walletId(WalletRepo repo, String name) async {
  final wallets = await repo.listWallets();
  return wallets.firstWhere((w) => w.name == name).id!;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // v2 schema check: fresh DBs carry the table.
  test('fresh DB creates recurring_templates', () async {
    final db = await _openTestDb();
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'recurring_templates'",
      );
      expect(tables, hasLength(1));
      final cols = await db.rawQuery('PRAGMA table_info(recurring_templates)');
      expect(
        cols.map((c) => c['name']).toSet(),
        containsAll(
          <String>{
            'id',
            'name',
            'amount',
            'wallet_id',
            'type',
            'created_at',
            'last_added_at',
          },
        ),
      );
    } finally {
      await db.close();
    }
  });

  group('recurring_repo', () {
    late Database db;
    late WalletRepo wallets;
    late TxnRepo txns;
    late RecurringRepo recurring;

    setUp(() async {
      db = await _openTestDb();
      wallets = WalletRepo(db);
      txns = TxnRepo(db);
      recurring = RecurringRepo(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('add + list joins the wallet name, oldest first', () async {
      final cash = await _walletId(wallets, 'Cash');
      final upi = await _walletId(wallets, 'UPI');
      await recurring.addTemplate(
        name: 'Rent',
        amountPaise: 500000,
        walletId: cash,
        type: TxnType.expense,
      );
      await recurring.addTemplate(
        name: 'Salary',
        amountPaise: 1000000,
        walletId: upi,
        type: TxnType.income,
      );
      final list = await recurring.listTemplates();
      expect(list.map((t) => t.name), ['Rent', 'Salary']);
      expect(list.first.walletName, 'Cash');
      expect(list.first.lastAddedAt, isNull);
      expect(list.first.type, TxnType.expense);
    });

    test('validation rejects blank name, zero amount, unknown wallet',
        () async {
      final cash = await _walletId(wallets, 'Cash');
      expect(
        () => recurring.addTemplate(
          name: '  ',
          amountPaise: 100,
          walletId: cash,
          type: TxnType.expense,
        ),
        throwsArgumentError,
      );
      expect(
        () => recurring.addTemplate(
          name: 'x',
          amountPaise: 0,
          walletId: cash,
          type: TxnType.expense,
        ),
        throwsArgumentError,
      );
      expect(
        () => recurring.addTemplate(
          name: 'x',
          amountPaise: 100,
          walletId: 99999,
          type: TxnType.expense,
        ),
        throwsArgumentError,
      );
    });

    test('update + delete (delete keeps past txns by design)', () async {
      final cash = await _walletId(wallets, 'Cash');
      final upi = await _walletId(wallets, 'UPI');
      final id = await recurring.addTemplate(
        name: 'Rent',
        amountPaise: 500000,
        walletId: cash,
        type: TxnType.expense,
      );
      await recurring.updateTemplate(
        id: id,
        name: 'Rent hiked',
        amountPaise: 550000,
        walletId: upi,
        type: TxnType.expense,
      );
      final got = (await recurring.getTemplate(id))!;
      expect(got.name, 'Rent hiked');
      expect(got.amountPaise, 550000);
      expect(got.walletId, upi);
      await recurring.deleteTemplate(id);
      expect(await recurring.getTemplate(id), isNull);
      expect(
        () => recurring.updateTemplate(
          id: 99999,
          name: 'x',
          amountPaise: 100,
          walletId: cash,
          type: TxnType.expense,
        ),
        throwsArgumentError,
      );
    });

    test('markAdded stamps last_added_at', () async {
      final cash = await _walletId(wallets, 'Cash');
      final id = await recurring.addTemplate(
        name: 'Rent',
        amountPaise: 1000,
        walletId: cash,
        type: TxnType.expense,
      );
      expect((await recurring.getTemplate(id))!.lastAddedAt, isNull);
      await recurring.markAdded(id);
      expect(
        (await recurring.getTemplate(id))!.lastAddedAt,
        isNotNull,
      );
    });

    test('isDue: never → true, old → true, recent → false', () async {
      final cash = await _walletId(wallets, 'Cash');
      final id = await recurring.addTemplate(
        name: 'Rent',
        amountPaise: 1000,
        walletId: cash,
        type: TxnType.expense,
      );
      expect((await recurring.getTemplate(id))!.isDue, true);
      await db.update(
        'recurring_templates',
        <String, Object?>{
          'last_added_at': DateTime.now()
              .subtract(const Duration(days: 31))
              .toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      expect((await recurring.getTemplate(id))!.isDue, true);
      await recurring.markAdded(id);
      expect((await recurring.getTemplate(id))!.isDue, false);
    });

    test('materialize expense: exact balance + stamp', () async {
      final cash = await _walletId(wallets, 'Cash');
      await txns.addIncome(
        walletId: cash,
        amountPaise: 50000,
        fromFor: 'Job',
        note: 'pay',
      );
      final id = await recurring.addTemplate(
        name: 'Rent',
        amountPaise: 20000,
        walletId: cash,
        type: TxnType.expense,
      );
      final t = (await recurring.getTemplate(id))!;
      await txns.addExpense(
        walletId: t.walletId,
        amountPaise: t.amountPaise,
        fromFor: t.name,
        note: recurringTxnNote(t.name),
      );
      await recurring.markAdded(id);
      expect(
        (await wallets.getWallet(cash))!.balancePaise,
        50000 - 20000,
      );
      expect(
        (await recurring.getTemplate(id))!.lastAddedAt,
        isNotNull,
      );
      expect(
        (await txns.allTxns()).first.fromFor,
        'Rent',
      );
      // Owner choice: the note is auto-filled 'Monthly: <name>' so a
      // materialized row always satisfies the mandatory-note rule.
      expect((await txns.allTxns()).first.note, 'Monthly: Rent');
    });

    test('recurringTxnNote prefixes and trims the template name', () {
      expect(recurringTxnNote('Rent'), 'Monthly: Rent');
      expect(recurringTxnNote('  Netflix  '), 'Monthly: Netflix');
      // Never blank -> never trips the mandatory-note rule.
      expect(recurringTxnNote('   ').trim(), isNotEmpty);
    });

    test('overspend materialization fails, stamp untouched', () async {
      final cash = await _walletId(wallets, 'Cash');
      final id = await recurring.addTemplate(
        name: 'Rent',
        amountPaise: 999999,
        walletId: cash,
        type: TxnType.expense,
      );
      final t = (await recurring.getTemplate(id))!;
      expect(
        () => txns.addExpense(
          walletId: t.walletId,
          amountPaise: t.amountPaise,
          fromFor: t.name,
          note: recurringTxnNote(t.name),
        ),
        throwsA(isA<InsufficientBalance>()),
      );
      // Nothing added, stamp untouched.
      expect(await txns.allTxns(), isEmpty);
      expect(
        (await recurring.getTemplate(id))!.lastAddedAt,
        isNull,
      );
    });
  });
}

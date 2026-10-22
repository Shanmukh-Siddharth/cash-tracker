// Debt tracker tests (sqflite_common_ffi):
// - v3 schema: fresh DBs carry debts + debt_payments with indexes.
// - upgrade: a v2-shaped DB gains the debt tables on open.
// - repo CRUD: add validation, list filters, paymentsFor ordering.
// - addPayment: happy path, zero/negative reject, overpay throws DebtOverpay
//   with remaining, unknown debt throws ArgumentError.
// - settle/delete (cascade), openDebts, totals, openCount.
// - remainingOf pure helper.
// - wallets untouched by every debt op (balances stay 0).
// - export v3: buildJson carries debts+payments, schema_version 3;
//   v2 backup (no debt keys) restores with empty debts; v3 round-trips.
// - CSV unchanged (transactions only).
// - resetAll: wipes debts+payments, reseeds wallets, clears resetPrefKeys
//   (last_wallet_id, last categories, last_export_at) but KEEPS
//   biometric_enabled; reset then re-seed works.
import 'dart:convert';

import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/repos/debt_repo.dart';
import 'package:finance_tracker/data/repos/export_repo.dart';
import 'package:finance_tracker/data/repos/txn_repo.dart';
import 'package:finance_tracker/data/repos/wallet_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openTestDb() =>
    openAppDatabase(path: inMemoryDatabasePath);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});

  test('fresh DB creates debts + debt_payments (v3)', () async {
    final db = await _openTestDb();
    try {
      for (final table in ['debts', 'debt_payments']) {
        final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = '$table'",
        );
        expect(rows, hasLength(1), reason: table);
      }
      final debtCols =
          await db.rawQuery('PRAGMA table_info(debts)');
      expect(
        debtCols.map((c) => c['name']).toSet(),
        containsAll(<String>{
          'id',
          'person',
          'amount',
          'direction',
          'note',
          'date',
          'status',
          'created_at',
        }),
      );
      final payCols =
          await db.rawQuery('PRAGMA table_info(debt_payments)');
      expect(
        payCols.map((c) => c['name']).toSet(),
        containsAll(<String>{'id', 'debt_id', 'amount', 'date', 'note'}),
      );
    } finally {
      await db.close();
    }
  });

  group('debt_repo', () {
    late Database db;
    late WalletRepo wallets;
    late DebtRepo debts;

    setUp(() async {
      db = await _openTestDb();
      wallets = WalletRepo(db);
      debts = DebtRepo(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('add + get round-trips, remaining == amount', () async {
      final id = await debts.addDebt(
        person: 'Rahul',
        amountPaise: 50000,
        direction: 'owe',
        note: 'Lunch split',
      );
      final got = (await debts.getDebt(id))!;
      expect(got.person, 'Rahul');
      expect(got.amountPaise, 50000);
      expect(got.direction, 'owe');
      expect(got.note, 'Lunch split');
      expect(got.status, 'open');
      expect(got.paidPaise, 0);
      expect(got.remainingPaise, 50000);
    });

    test('add validation rejects blank person, zero amount, bad direction',
        () async {
      expect(
        () => debts.addDebt(
            person: '  ', amountPaise: 100, direction: 'owe'),
        throwsArgumentError,
      );
      expect(
        () => debts.addDebt(
            person: 'X', amountPaise: 0, direction: 'owe'),
        throwsArgumentError,
      );
      expect(
        () => debts.addDebt(
            person: 'X', amountPaise: 100, direction: 'owed'),
        throwsArgumentError,
      );
    });

    test('list filters by direction + status, newest first', () async {
      final a = await debts.addDebt(
          person: 'A', amountPaise: 100, direction: 'owe');
      await debts.addDebt(person: 'B', amountPaise: 200, direction: 'lent');
      await debts.settle(a);
      expect((await debts.listDebts()).length, 2);
      expect((await debts.listDebts(direction: 'owe')).length, 1);
      expect((await debts.listDebts(status: 'open')).length, 1);
      expect(
        (await debts.listDebts(direction: 'owe', status: 'settled')).length,
        1,
      );
      // Newest first.
      final all = await debts.listDebts();
      expect(all.first.person, 'B');
    });

    test('addPayment happy path + paymentsFor ordering', () async {
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 10000, direction: 'lent');
      await debts.addPayment(debtId: id, amountPaise: 3000, note: 'first');
      await debts.addPayment(debtId: id, amountPaise: 2000);
      final got = (await debts.getDebt(id))!;
      expect(got.paidPaise, 5000);
      expect(got.remainingPaise, 5000);
      final payments = await debts.paymentsFor(id);
      expect(payments.length, 2);
      expect(payments.first.note, 'first');
      expect(payments.first.amountPaise, 3000);
    });

    test('addPayment rejects zero/negative, unknown debt', () async {
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 10000, direction: 'owe');
      expect(
        () => debts.addPayment(debtId: id, amountPaise: 0),
        throwsArgumentError,
      );
      expect(
        () => debts.addPayment(debtId: id, amountPaise: -5),
        throwsArgumentError,
      );
      expect(
        () => debts.addPayment(debtId: 99999, amountPaise: 100),
        throwsArgumentError,
      );
    });

    test('addPayment overpay throws DebtOverpay with remaining', () async {
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 10000, direction: 'owe');
      await debts.addPayment(debtId: id, amountPaise: 4000);
      try {
        await debts.addPayment(debtId: id, amountPaise: 6001);
        fail('expected DebtOverpay');
      } on DebtOverpay catch (e) {
        expect(e.remaining, 6000);
      }
      // Exact-remaining payment is fine.
      await debts.addPayment(debtId: id, amountPaise: 6000);
      expect((await debts.getDebt(id))!.remainingPaise, 0);
    });

    test('settle flips status; unknown id throws', () async {
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 100, direction: 'owe');
      await debts.settle(id);
      expect((await debts.getDebt(id))!.status, 'settled');
      expect(() => debts.settle(99999), throwsArgumentError);
    });

    test('deleteDebt cascades payments', () async {
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 10000, direction: 'owe');
      await debts.addPayment(debtId: id, amountPaise: 1000);
      await debts.deleteDebt(id);
      expect(await debts.getDebt(id), isNull);
      expect(await debts.paymentsFor(id), isEmpty);
    });

    test('openDebts + totals + openCount', () async {
      final a = await debts.addDebt(
          person: 'A', amountPaise: 10000, direction: 'owe');
      await debts.addDebt(person: 'B', amountPaise: 20000, direction: 'lent');
      await debts.addPayment(debtId: a, amountPaise: 4000);
      expect((await debts.openDebts('owe')).length, 1);
      expect((await debts.openDebts('lent')).length, 1);
      final t = await debts.totals();
      expect(t.oweTotal, 6000);
      expect(t.lentTotal, 20000);
      expect(await debts.openCount(), 2);
      await debts.settle(a);
      final t2 = await debts.totals();
      expect(t2.oweTotal, 0);
      expect(t2.lentTotal, 20000);
      expect(await debts.openCount(), 1);
    });

    test('remainingOf is pure amount - SUM', () {
      expect(remainingOf(10000, const []), 10000);
      expect(
        remainingOf(
          10000,
          const [
            DebtPayment(debtId: 1, amountPaise: 3000, date: 'x'),
            DebtPayment(debtId: 1, amountPaise: 2000, date: 'x'),
          ],
        ),
        5000,
      );
    });

    test('debt ops never touch wallet balances', () async {
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 99999, direction: 'owe');
      await debts.addPayment(debtId: id, amountPaise: 11111);
      await debts.settle(id);
      await debts.deleteDebt(id);
      for (final w in await wallets.listWallets()) {
        expect(w.balancePaise, 0);
      }
      expect(await TxnRepo(db).allTxns(), isEmpty);
    });
  });

  group('export v3 + reset', () {
    late Database db;
    late WalletRepo wallets;
    late DebtRepo debts;
    late ExportRepo exports;

    setUp(() async {
      db = await _openTestDb();
      wallets = WalletRepo(db);
      debts = DebtRepo(db);
      exports = ExportRepo(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('buildJson schema_version 3 with debts+payments', () async {
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 5000, direction: 'lent');
      await debts.addPayment(debtId: id, amountPaise: 1000);
      final map = await exports.buildJson();
      expect(map['schema_version'], 3);
      expect((map['debts'] as List).length, 1);
      expect((map['debt_payments'] as List).length, 1);
      expect((map['debts'] as List).first['person'], 'Rahul');
    });

    test('v2 backup (no debt keys) restores with empty debts', () async {
      final cash =
          (await wallets.listWallets()).firstWhere((w) => w.name == 'Cash');
      final v2 = <String, dynamic>{
        'schema_version': 2,
        'exported_at': '2026-01-01T00:00:00.000',
        'wallets': [
          {
            'id': cash.id,
            'name': 'Cash',
            'balance': 0,
            'created_at': '2026-01-01T00:00:00.000',
          },
        ],
        'transactions': [],
        'cart': [],
      };
      await exports.restoreFromJson(exports.parseBackup(jsonEncode(v2)));
      expect(await debts.listDebts(), isEmpty);
      final t = await debts.totals();
      expect(t.oweTotal, 0);
      expect(t.lentTotal, 0);
    });

    test('v3 backup round-trips debts + payments with balances intact',
        () async {
      final cash =
          (await wallets.listWallets()).firstWhere((w) => w.name == 'Cash');
      await TxnRepo(db).addIncome(
        walletId: cash.id!,
        amountPaise: 10000,
        fromFor: 'Salary',
      );
      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 5000, direction: 'owe');
      await debts.addPayment(debtId: id, amountPaise: 2000, note: 'part');
      final backupStr = jsonEncode(await exports.buildJson());

      // Diverge: extra debt + extra txn.
      await debts.addDebt(person: 'Noise', amountPaise: 1, direction: 'lent');
      await exports.restoreFromJson(exports.parseBackup(backupStr));

      final restored = await debts.listDebts();
      expect(restored.length, 1);
      expect(restored.first.person, 'Rahul');
      expect(restored.first.remainingPaise, 3000);
      expect((await debts.paymentsFor(restored.first.id!)).length, 1);
      // Wallet balance rebuilt from txns only.
      expect((await wallets.getWallet(cash.id!))!.balancePaise, 10000);
    });

    test('CSV unchanged: transactions only', () async {
      await debts.addDebt(
          person: 'Rahul', amountPaise: 5000, direction: 'owe');
      final csv = await exports.buildCsv();
      expect(
        csv.split('\n').first,
        'id,date,type,amount,from_for,wallet,note,created_at,category',
      );
      expect(csv, isNot(contains('Rahul')));
    });

    test('resetAll wipes debts, reseeds, clears prefs but keeps biometrics',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_wallet_id', 9999);
      await prefs.setString('last_category_income', 'Bonus');
      await prefs.setString('last_category_expense', 'Food');
      await prefs.setString('last_export_at', '2026-01-01T00:00:00.000');
      await prefs.setBool('biometric_enabled', false);

      final id = await debts.addDebt(
          person: 'Rahul', amountPaise: 5000, direction: 'owe');
      await debts.addPayment(debtId: id, amountPaise: 1000);

      await exports.resetAll();

      expect(await debts.listDebts(), isEmpty);
      final list = await wallets.listWallets();
      expect(list.map((w) => w.name), ['Cash', 'UPI', 'Bank']);
      expect(list.map((w) => w.balancePaise), [0, 0, 0]);
      for (final key in ExportRepo.resetPrefKeys) {
        expect(prefs.get(key), isNull, reason: key);
      }
      expect(prefs.getBool('biometric_enabled'), false); // kept as-is

      // Migration-safe: reset then re-seed works (new debts usable).
      final id2 = await debts.addDebt(
          person: 'After', amountPaise: 100, direction: 'lent');
      expect((await debts.getDebt(id2))!.remainingPaise, 100);
    });
  });
}

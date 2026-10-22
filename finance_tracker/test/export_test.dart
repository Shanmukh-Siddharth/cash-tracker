// Phase 5 export/import tests on an in-memory DB (sqflite_common_ffi):
// CSV header (with trailing category column) + exact first row (comma/quote
// note quoting), JSON keys + paise ints round-trip, parseBackup rejections,
// restore wipe + rebuild with correct balances and dangling last_wallet
// repair, v1 backup (no category) backfill.
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/repos/cart_repo.dart';
import 'package:finance_tracker/data/repos/export_repo.dart';
import 'package:finance_tracker/data/repos/txn_repo.dart';
import 'package:finance_tracker/data/repos/wallet_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  SharedPreferences.setMockInitialValues({});

  late Database db;
  late WalletRepo wallets;
  late TxnRepo txns;
  late CartRepo cart;
  late ExportRepo exports;

  setUp(() async {
    db = await _openTestDb();
    wallets = WalletRepo(db);
    txns = TxnRepo(db);
    cart = CartRepo(db);
    exports = ExportRepo(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('CSV header + first-row exact content, comma/quote note quoted',
      () async {
    final cash = await _walletId(wallets, 'Cash');
    await db.insert('transactions', <String, Object?>{
      'wallet_id': cash,
      'type': 'income',
      'amount': 12345,
      'from_for': 'Salary',
      'note': 'Monthly, "bonus" pay',
      'date': '2026-01-02T10:00:00.000',
      'created_at': '2026-01-02T10:00:01.000',
    });
    await db.insert('transactions', <String, Object?>{
      'wallet_id': cash,
      'type': 'expense',
      'amount': 5000,
      'from_for': 'Chai',
      'note': null,
      'date': '2026-01-03T10:00:00.000',
      'created_at': '2026-01-03T10:00:01.000',
    });
    await recalculateBalances(db);

    final csv = await exports.buildCsv();
    expect(
      csv.split('\n').first,
      'id,date,type,amount,from_for,wallet,note,created_at,category',
    );
    // Raw quoting: field wrapped in quotes, inner quotes doubled.
    expect(csv, contains('"Monthly, ""bonus"" pay"'));

    final rows = Csv().decode(csv);
    expect(rows.first, <String>[
      'id',
      'date',
      'type',
      'amount',
      'from_for',
      'wallet',
      'note',
      'created_at',
      'category',
    ]);
    expect(rows[1], <String>[
      '1',
      '2026-01-02T10:00:00.000',
      'income',
      '123.45',
      'Salary',
      'Cash',
      'Monthly, "bonus" pay',
      '2026-01-02T10:00:01.000',
      'Miscellaneous', // v1-style row: default backfill
    ]);
    expect(rows[2][3], '50.00');
    expect(rows[2][6], '');
    expect(rows[2][8], 'Miscellaneous');
  });

  test('CSV appends the stored category as the last column', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 50000,
      fromFor: 'Salary',
      note: 'pay',
    );
    await txns.addExpense(
      walletId: cash,
      amountPaise: 8000,
      fromFor: 'Lunch',
      note: 'team lunch',
      category: 'Food',
    );
    final csv = await exports.buildCsv();
    final rows = Csv().decode(csv);
    expect(rows.first.last, 'category');
    expect(rows[1].last, 'Other'); // income default
    expect(rows[2].last, 'Food');
  });

  test('JSON has keys, paise ints, schema_version 3, round-trips', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    await txns.addExpense(
      walletId: cash,
      amountPaise: 2500,
      fromFor: 'Chai',
    );
    await cart.addItem(name: 'Book', pricePaise: 9999, qty: 2);

    final map = await exports.buildJson();
    expect(map['schema_version'], 3);
    expect(map['exported_at'] is String, true);
    expect((map['wallets'] as List).length, 3);
    expect((map['transactions'] as List).length, 2);
    expect((map['cart'] as List).length, 1);
    for (final t in map['transactions'] as List) {
      expect((t as Map)['amount'] is int, true);
      expect((t)['category'] is String, true);
    }
    expect((map['cart'] as List).first['price'] is int, true);

    // Through a real JSON string and back.
    final parsed = exports.parseBackup(jsonEncode(map));
    expect((parsed['transactions'] as List).length, 2);
    expect((parsed['cart'] as List).length, 1);
  });

  test('parseBackup rejects garbage, missing keys, wrong types', () {
    expect(
      () => exports.parseBackup('nope {{{'),
      throwsA(isA<InvalidBackup>()),
    );
    expect(
      () => exports.parseBackup(jsonEncode(<String, dynamic>{'wallets': []})),
      throwsA(isA<InvalidBackup>()),
    );
    expect(
      () => exports.parseBackup(
        jsonEncode(<String, dynamic>{
          'wallets': [],
          'transactions': [],
          'cart': 'not-a-list',
        }),
      ),
      throwsA(isA<InvalidBackup>()),
    );
    // Wrong type: amount as String instead of paise int.
    final badAmount = <String, dynamic>{
      'wallets': [
        {
          'id': 1,
          'name': 'Cash',
          'balance': 0,
          'created_at': '2026-01-01T00:00:00.000',
        },
      ],
      'transactions': [
        {
          'id': 1,
          'wallet_id': 1,
          'type': 'income',
          'amount': '100',
          'from_for': 'X',
          'note': null,
          'date': '2026-01-01T00:00:00.000',
          'created_at': '2026-01-01T00:00:00.000',
        },
      ],
      'cart': [],
    };
    expect(
      () => exports.parseBackup(jsonEncode(badAmount)),
      throwsA(isA<InvalidBackup>()),
    );
    // Wrong value: unknown txn type.
    final badType = <String, dynamic>{
      'wallets': (badAmount['wallets'] as List).toList(),
      'transactions': [
        {
          'id': 1,
          'wallet_id': 1,
          'type': 'gift',
          'amount': 100,
          'from_for': 'X',
          'note': null,
          'date': '2026-01-01T00:00:00.000',
          'created_at': '2026-01-01T00:00:00.000',
        },
      ],
      'cart': [],
    };
    expect(
      () => exports.parseBackup(jsonEncode(badType)),
      throwsA(isA<InvalidBackup>()),
    );
    expect(const InvalidBackup('x').message, 'x');
  });

  test('restore wipes divergent data and rebuilds balances + cart', () async {
    final cash = await _walletId(wallets, 'Cash');
    final upi = await _walletId(wallets, 'UPI');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    await txns.addExpense(
      walletId: cash,
      amountPaise: 3000,
      fromFor: 'Chai',
    );
    await cart.addItem(name: 'Pen', pricePaise: 1500);
    final backupStr = jsonEncode(await exports.buildJson());

    // Diverge after backup: noise income + cart cleared.
    await txns.addIncome(
      walletId: upi,
      amountPaise: 99999,
      fromFor: 'Noise',
    );
    await cart.clear();
    expect((await wallets.getWallet(upi))!.balancePaise, 99999);

    await exports.restoreFromJson(exports.parseBackup(backupStr));

    expect((await wallets.getWallet(cash))!.balancePaise, 7000);
    expect((await wallets.getWallet(upi))!.balancePaise, 0);
    expect((await txns.allTxns()).length, 2);
    expect((await cart.items()).length, 1);
    expect((await cart.items()).first.name, 'Pen');
  });

  test('v1 backup without category restores with the default', () async {
    final cash = await _walletId(wallets, 'Cash');
    final v1 = <String, dynamic>{
      'schema_version': 1,
      'exported_at': '2026-01-01T00:00:00.000',
      'wallets': [
        {
          'id': cash,
          'name': 'Cash',
          'balance': 0,
          'created_at': '2026-01-01T00:00:00.000',
        },
      ],
      'transactions': [
        {
          'id': 1,
          'wallet_id': cash,
          'type': 'expense',
          'amount': 1000,
          'from_for': 'Chai',
          'note': 'evening',
          'date': '2026-01-02T10:00:00.000',
          'created_at': '2026-01-02T10:00:01.000',
        },
      ],
      'cart': [],
    };
    await exports.restoreFromJson(exports.parseBackup(jsonEncode(v1)));
    final restored = await txns.allTxns();
    expect(restored, hasLength(1));
    expect(restored.first.category, 'Miscellaneous');
  });

  test('restore rewrites a dangling last_wallet_id', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_wallet_id', 9999);
    final backup = await exports.buildJson();

    await exports.restoreFromJson(
      exports.parseBackup(jsonEncode(backup)),
    );

    final firstId = (await wallets.listWallets()).first.id;
    expect(prefs.getInt('last_wallet_id'), firstId);
  });

  test('resetAll wipes and reseeds wallets at zero', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    await cart.addItem(name: 'Pen', pricePaise: 1500);

    await exports.resetAll();

    final list = await wallets.listWallets();
    expect(list.map((w) => w.name), ['Cash', 'UPI', 'Bank']);
    expect(list.map((w) => w.balancePaise), [0, 0, 0]);
    expect(await txns.allTxns(), isEmpty);
    expect(await cart.items(), isEmpty);
  });
}

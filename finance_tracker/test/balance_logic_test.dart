// Balance-integrity tests through the real repos on an in-memory DB
// (sqflite_common_ffi). Covers add/edit/delete/overspend/recalculate plus
// the grouped cart-buy math (one expense for the cart total).
import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/models/transaction.dart';
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

Future<int> _balance(WalletRepo repo, int id) async =>
    (await repo.getWallet(id))!.balancePaise;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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

  test('seeds Cash/UPI/Bank at zero', () async {
    final list = await wallets.listWallets();
    expect(list.map((w) => w.name), ['Cash', 'UPI', 'Bank']);
    expect(list.map((w) => w.balancePaise), [0, 0, 0]);
  });

  test('addIncome increases wallet balance', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    expect(await _balance(wallets, cash), 10000);
  });

  test('addExpense decreases balance; overspend throws InsufficientBalance',
      () async {
    final cash = await _walletId(wallets, 'Cash');
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
    expect(await _balance(wallets, cash), 7000);

    expect(
      () => txns.addExpense(
        walletId: cash,
        amountPaise: 999999,
        fromFor: 'Too much',
      ),
      throwsA(
        isA<InsufficientBalance>().having(
          (e) => e.availablePaise,
          'availablePaise',
          7000,
        ),
      ),
    );
    // Failed write leaves balance untouched.
    expect(await _balance(wallets, cash), 7000);
  });

  test('deleteTxn reverts the balance', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    final spendId = await txns.addExpense(
      walletId: cash,
      amountPaise: 3000,
      fromFor: 'Chai',
    );
    await txns.deleteTxn(spendId);
    expect(await _balance(wallets, cash), 10000);
  });

  test('editTxn reverts then applies, including wallet change', () async {
    final cash = await _walletId(wallets, 'Cash');
    final upi = await _walletId(wallets, 'UPI');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    await txns.addIncome(
      walletId: upi,
      amountPaise: 5000,
      fromFor: 'Refund',
    );
    final id = await txns.addExpense(
      walletId: cash,
      amountPaise: 3000,
      fromFor: 'Chai',
    );
    // Move the expense to UPI and change the amount.
    await txns.editTxn(
      id: id,
      walletId: upi,
      type: TxnType.expense,
      amountPaise: 2000,
      fromFor: 'Chai',
    );
    expect(await _balance(wallets, cash), 10000);
    expect(await _balance(wallets, upi), 3000);
  });

  test('editTxn overspend is blocked and rolls back', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 5000,
      fromFor: 'Salary',
    );
    final id = await txns.addExpense(
      walletId: cash,
      amountPaise: 1000,
      fromFor: 'Chai',
    );
    expect(
      () => txns.editTxn(
        id: id,
        walletId: cash,
        type: TxnType.expense,
        amountPaise: 999999,
        fromFor: 'Chai',
      ),
      throwsA(isA<InsufficientBalance>()),
    );
    expect(await _balance(wallets, cash), 4000);
  });

  test('grouped cart buy: one expense for the cart total', () async {
    // Cart math: 2 x Rs100 + 1 x Rs50 = Rs250 (25000 paise).
    const cartTotalPaise = 2 * 10000 + 1 * 5000;
    final upi = await _walletId(wallets, 'UPI');
    await txns.addIncome(
      walletId: upi,
      amountPaise: 50000,
      fromFor: 'Salary',
    );
    await txns.addExpense(
      walletId: upi,
      amountPaise: cartTotalPaise,
      fromFor: 'Cart purchase (3 items)',
      note: 'Headphones x1, Mouse pad x2',
    );
    expect(await _balance(wallets, upi), 50000 - cartTotalPaise);
    final recent = await txns.recentTxns();
    expect(recent.first.fromFor, 'Cart purchase (3 items)');
  });

  test('recentTxns defaults to the 10 newest, newest first', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(walletId: cash, amountPaise: 1000000, fromFor: 'Salary');
    for (var i = 0; i < 14; i++) {
      await txns.addExpense(
        walletId: cash,
        amountPaise: 100,
        fromFor: 'Spent $i',
      );
    }
    final recent = await txns.recentTxns();
    expect(recent.length, 10);
    expect(recent.first.fromFor, 'Spent 13'); // newest first
    expect(recent.last.fromFor, 'Spent 4'); // 10 rows: Spent 13..4
  });

  test('recalculateBalances repairs drift', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    // Simulate drift from an external write.
    await db.rawUpdate(
      'UPDATE wallets SET balance = ? WHERE id = ?',
      <Object?>[12345, cash],
    );
    await recalculateBalances(db);
    expect(await _balance(wallets, cash), 10000);
  });

  test('todayTotals sums only local-today rows', () async {    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 200000,
      fromFor: 'Salary',
    );
    await txns.addExpense(
      walletId: cash,
      amountPaise: 55000,
      fromFor: 'Petrol',
    );
    final totals = await txns.todayTotals();
    expect(totals.incomePaise, 200000);
    expect(totals.expensePaise, 55000);
  });

  test('edit-then-edit across wallets keeps balances correct', () async {
    final cash = await _walletId(wallets, 'Cash');
    final upi = await _walletId(wallets, 'UPI');
    await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    await txns.addIncome(walletId: upi, amountPaise: 5000, fromFor: 'Refund');
    final id = await txns.addExpense(
      walletId: cash,
      amountPaise: 3000,
      fromFor: 'Chai',
    );
    // traced scenario: spend 3000 Cash -> move to UPI 2000 -> back to Cash 1000
    await txns.editTxn(
      id: id,
      walletId: upi,
      type: TxnType.expense,
      amountPaise: 2000,
      fromFor: 'Chai',
    );
    expect(await _balance(wallets, cash), 10000);
    expect(await _balance(wallets, upi), 3000);
    await txns.editTxn(
      id: id,
      walletId: cash,
      type: TxnType.expense,
      amountPaise: 1000,
      fromFor: 'Chai',
    );
    expect(await _balance(wallets, cash), 9000);
    expect(await _balance(wallets, upi), 5000);
  });

  test('amount validation rejects zero and empty from/for', () async {
    final cash = await _walletId(wallets, 'Cash');
    expect(
      () => txns.addIncome(walletId: cash, amountPaise: 0, fromFor: 'Salary'),
      throwsArgumentError,
    );
    expect(
      () => txns.addExpense(
        walletId: cash,
        amountPaise: 100,
        fromFor: '   ',
      ),
      throwsArgumentError,
    );
    final id = await txns.addIncome(
      walletId: cash,
      amountPaise: 10000,
      fromFor: 'Salary',
    );
    expect(
      () => txns.editTxn(
        id: id,
        walletId: cash,
        type: TxnType.income,
        amountPaise: 0,
        fromFor: 'Salary',
      ),
      throwsArgumentError,
    );
    // Failed validations leave the balance untouched.
    expect(await _balance(wallets, cash), 10000);
  });
}

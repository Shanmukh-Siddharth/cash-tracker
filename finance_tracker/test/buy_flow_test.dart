// Cart buy-transaction tests through the real repos on an in-memory DB
// (sqflite_common_ffi): Buy deducts once, clears the cart, leaves one
// grouped txn; insufficient balance blocks and keeps the cart intact.
import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/repos/cart_repo.dart';
import 'package:finance_tracker/data/repos/stats_repo.dart';
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
  late CartRepo cart;

  setUp(() async {
    db = await _openTestDb();
    wallets = WalletRepo(db);
    txns = TxnRepo(db);
    cart = CartRepo(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('cart CRUD: add / setQty / remove / clear', () async {
    final id = await cart.addItem(name: 'Chai', pricePaise: 5000);
    await cart.addItem(name: 'Book', pricePaise: 10000, qty: 2);
    expect((await cart.items()).length, 2);
    expect(await cart.itemCount(), 3);

    await cart.setQty(id, 3);
    expect((await cart.items()).firstWhere((i) => i.id == id).qty, 3);

    await cart.removeItem(id);
    expect((await cart.items()).length, 1);

    await cart.clear();
    expect(await cart.items(), isEmpty);
  });

  test('cart validation rejects empty name, bad price, bad qty', () async {
    expect(() => cart.addItem(name: '  ', pricePaise: 100), throwsArgumentError);
    expect(() => cart.addItem(name: 'X', pricePaise: 0), throwsArgumentError);
    expect(() => cart.addItem(name: 'X', pricePaise: 100, qty: 0),
        throwsArgumentError);
    final id = await cart.addItem(name: 'X', pricePaise: 100);
    expect(() => cart.setQty(id, 0), throwsArgumentError);
  });

  test('buy deducts once, clears cart, leaves one grouped txn', () async {
    // Traced: Rs500 wallet, cart 2xRs100 + 1xRs50 = Rs250 -> Rs250 left.
    final upi = await _walletId(wallets, 'UPI');
    await txns.addIncome(walletId: upi, amountPaise: 50000, fromFor: 'Salary');
    await cart.addItem(name: 'Item A', pricePaise: 10000, qty: 2);
    await cart.addItem(name: 'Item B', pricePaise: 5000, qty: 1);

    await cart.buyAll(walletId: upi);

    expect(await _balance(wallets, upi), 25000);
    expect(await cart.items(), isEmpty);
    final recent = await txns.recentTxns();
    expect(recent.length, 2); // income + the single grouped expense
    expect(recent.first.fromFor, 'Cart purchase (3 items)');
    expect(recent.first.amountPaise, 25000);
    expect(recent.first.note, contains('Item A ×2'));
    expect(recent.first.note, contains('Item B ×1'));
  });

  test('buy with insufficient balance is blocked, cart kept', () async {
    final cash = await _walletId(wallets, 'Cash');
    await txns.addIncome(walletId: cash, amountPaise: 10000, fromFor: 'Salary');
    await cart.addItem(name: 'Big', pricePaise: 25000, qty: 1);

    expect(() => cart.buyAll(walletId: cash),
        throwsA(isA<InsufficientBalance>()));
    expect(await _balance(wallets, cash), 10000);
    expect((await cart.items()).length, 1);
  });

  test('buy on an empty cart throws', () async {
    final cash = await _walletId(wallets, 'Cash');
    expect(() => cart.buyAll(walletId: cash), throwsArgumentError);
  });

  test('stats repo: daily totals, monthly pairs, shares, totals', () async {
    final cash = await _walletId(wallets, 'Cash');
    final upi = await _walletId(wallets, 'UPI');
    await txns.addIncome(walletId: cash, amountPaise: 200000, fromFor: 'Salary');
    await txns.addIncome(walletId: upi, amountPaise: 50000, fromFor: 'Refund');
    await txns.addExpense(walletId: cash, amountPaise: 55000, fromFor: 'Petrol');
    await txns.addExpense(walletId: upi, amountPaise: 10000, fromFor: 'Chai');

    final stats = StatsRepo(db);
    final daily = await stats.dailyExpenseTotals();
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    expect(daily[todayMid], 65000);

    final pairs = await stats.monthlyPairs(3);
    expect(pairs.length, 3);
    expect(pairs.last.expensePaise, 65000);
    expect(pairs.last.incomePaise, 250000);

    final shares = await stats.expenseShareByWallet();
    expect(shares.length, 3);
    expect(shares.firstWhere((s) => s.walletName == 'Cash').expensePaise,
        55000);

    final ie = await stats.incomeVsExpense();
    expect(ie.incomePaise, 250000);
    expect(ie.expensePaise, 65000);
  });
}

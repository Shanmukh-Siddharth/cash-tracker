/// Cart persistence + grouped Buy.
///
/// Items live in `cart_items` and NEVER touch balances until [buyAll], which
/// runs a single DB transaction: one grouped expense
/// `from_for="Cart purchase (n items)"` with an item-breakdown note, wallet
/// balance update, then cart clear. Overspend throws [InsufficientBalance].
library;

import 'package:sqflite/sqflite.dart';

import '../../core/money.dart';
import '../models/cart_item.dart';
import 'txn_repo.dart';

class CartRepo {
  final Database db;
  const CartRepo(this.db);

  Future<List<CartItem>> items() async {
    final rows = await db.query('cart_items', orderBy: 'id ASC');
    return rows.map(CartItem.fromMap).toList();
  }

  Future<int> itemCount() async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(qty), 0) AS n FROM cart_items',
    );
    return ((result.first['n'] as num?) ?? 0).toInt();
  }

  Future<int> addItem({
    required String name,
    required int pricePaise,
    int qty = 1,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Item name must not be empty');
    }
    if (pricePaise <= 0) {
      throw ArgumentError('Price must be > 0 paise');
    }
    if (qty < 1) throw ArgumentError('Qty must be >= 1');
    return db.insert('cart_items', <String, Object?>{
      'name': name.trim(),
      'price': pricePaise,
      'qty': qty,
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> setQty(int id, int qty) async {
    if (qty < 1) throw ArgumentError('Qty must be >= 1');
    await db.update(
      'cart_items',
      <String, Object?>{'qty': qty},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> removeItem(int id) async {
    await db.delete('cart_items', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> clear() async {
    await db.delete('cart_items');
  }

  /// Buys everything in one DB transaction. Returns the new txn id.
  ///
  /// Throws [ArgumentError] when the cart is empty, [InsufficientBalance]
  /// when the wallet cannot cover the total (cart left untouched).
  Future<int> buyAll({required int walletId}) async {
    return db.transaction<int>((txn) async {
      final rows = await txn.query('cart_items', orderBy: 'id ASC');
      if (rows.isEmpty) throw ArgumentError('Cart is empty');
      final cart = rows.map(CartItem.fromMap).toList();
      final total = cart.fold<int>(0, (sum, i) => sum + i.totalPaise);

      final wallets = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: <Object?>[walletId],
        limit: 1,
      );
      if (wallets.isEmpty) throw ArgumentError('Unknown wallet id $walletId');
      final balance = (wallets.first['balance'] as num).toInt();
      final walletName = wallets.first['name'] as String;
      if (total > balance) {
        throw InsufficientBalance(
          availablePaise: balance,
          walletName: walletName,
        );
      }

      final qtyTotal = cart.fold<int>(0, (sum, i) => sum + i.qty);
      final note = cart
          .map((i) => '${i.name} ×${i.qty} — ${formatPaise(i.totalPaise)}')
          .join('\n');
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('transactions', <String, Object?>{
        'wallet_id': walletId,
        'type': 'expense',
        'amount': total,
        'from_for': 'Cart purchase ($qtyTotal items)',
        'note': note,
        'date': now,
        'created_at': now,
      });
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance - ? WHERE id = ?',
        <Object?>[total, walletId],
      );
      await txn.delete('cart_items');
      return id;
    });
  }
}

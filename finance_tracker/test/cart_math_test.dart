// Pure cart-math tests: totals and if-bought preview, incl. negatives.
import 'package:finance_tracker/data/models/cart_item.dart';
import 'package:finance_tracker/features/cart/cart_math.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem _item(String name, int pricePaise, int qty) => CartItem(
      name: name,
      pricePaise: pricePaise,
      qty: qty,
      addedAt: '2026-10-08T00:00:00.000',
    );

void main() {
  test('cartTotal sums price * qty', () {
    // Traced: 2 x Rs100 + 1 x Rs50 = Rs250.
    final items = [_item('A', 10000, 2), _item('B', 5000, 1)];
    expect(cartTotal(items), 25000);
  });

  test('cartTotal is zero for an empty cart', () {
    expect(cartTotal(const []), 0);
  });

  test('ifBought subtracts the total from the balance', () {
    expect(ifBought(50000, 25000), 25000);
  });

  test('ifBought goes negative when the wallet cannot cover the cart', () {
    expect(ifBought(10000, 25000), -15000);
  });

  test('ifBought is zero when the total exactly matches', () {
    expect(ifBought(25000, 25000), 0);
  });
}

// Unit tests for paise <-> INR helpers (pure functions, no DB).
import 'package:finance_tracker/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPaise', () {
    test('zero', () => expect(formatPaise(0), '₹0.00'));
    test('paise only', () => expect(formatPaise(5), '₹0.05'));
    test('simple rupees', () => expect(formatPaise(10000), '₹100.00'));
    test('demo value', () => expect(formatPaise(1245000), '₹12,450.00'));
    test('thousands group', () => expect(formatPaise(420000), '₹4,200.00'));
    test('lakh grouping (Indian)', () {
      expect(formatPaise(10000000), '₹1,00,000.00');
    });
    test('crore grouping (Indian)', () {
      expect(formatPaise(1234567890), '₹1,23,45,678.90');
    });
    test('negative', () => expect(formatPaise(-55000), '-₹550.00'));
  });

  group('parseToPaise', () {
    test('plain rupees', () => expect(parseToPaise('100'), 10000));
    test('symbol + commas + decimals', () {
      expect(parseToPaise('₹12,450.00'), 1245000);
    });
    test('spaces tolerated', () => expect(parseToPaise('  ₹ 2,000.5 '), 200050));
    test('single decimal digit', () => expect(parseToPaise('10.5'), 1050));
    test('smallest unit', () => expect(parseToPaise('0.01'), 1));
    test('zero rejected', () => expect(parseToPaise('0'), isNull));
    test('zero decimals rejected', () => expect(parseToPaise('0.00'), isNull));
    test('negative rejected', () => expect(parseToPaise('-5'), isNull));
    test('explicit plus rejected', () => expect(parseToPaise('+5'), isNull));
    test('three decimals rejected', () => expect(parseToPaise('10.123'), isNull));
    test('trailing dot rejected', () => expect(parseToPaise('12.'), isNull));
    test('leading dot rejected', () => expect(parseToPaise('.50'), isNull));
    test('empty rejected', () => expect(parseToPaise(''), isNull));
    test('blank rejected', () => expect(parseToPaise('   '), isNull));
    test('text rejected', () => expect(parseToPaise('abc'), isNull));
    test('mixed text rejected', () => expect(parseToPaise('12a'), isNull));
  });
}

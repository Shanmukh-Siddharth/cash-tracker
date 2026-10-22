/// Floating glass pill nav: 5 equal tabs (Home, History, Debts, Cart, Stats)
/// and the sliding triangle marker.
///
/// Home's +Add/−Subtract pills are the sole entry points for recording
/// money — there is no center button, no notch, and no chooser sheet.
///
/// All DB-backed providers are overridden, so this exercises real layout +
/// hit testing without a device.
library;

import 'package:finance_tracker/app.dart';
import 'package:finance_tracker/data/models/cart_item.dart';
import 'package:finance_tracker/data/models/debt.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/models/wallet.dart';
import 'package:finance_tracker/data/repos/stats_repo.dart';
import 'package:finance_tracker/data/repos/txn_repo.dart';
import 'package:finance_tracker/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [MainNav] with every data provider stubbed.
Future<void> _pumpNav(WidgetTester tester) async {
  final wallets = <Wallet>[
    const Wallet(
      id: 1,
      name: 'Cash',
      balancePaise: 500000,
      createdAt: '2026-01-01T00:00:00.000',
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        totalProvider.overrideWith((ref) async => 500000),
        walletsProvider.overrideWith((ref) async => wallets),
        recentProvider.overrideWith((ref) async => const <Txn>[]),
        todayProvider.overrideWith(
          (ref) async => const TodayTotals(incomePaise: 0, expensePaise: 0),
        ),
        historyProvider.overrideWith((ref) async => const <Txn>[]),
        cartItemsProvider.overrideWith((ref) async => const <CartItem>[]),
        cartCountProvider.overrideWith((ref) async => 2),
        debtsProvider.overrideWith((ref) async => const <Debt>[]),
        debtTotalsProvider.overrideWith(
          (ref) async => const DebtTotals(oweTotal: 0, lentTotal: 0),
        ),
        debtOpenCountProvider.overrideWith((ref) async => 3),
        dailyExpensesProvider.overrideWith((ref) async => const {}),
        monthlyPairsProvider.overrideWith(
          (ref, months) async => const <MonthlyPair>[],
        ),
        walletShareProvider.overrideWith((ref) async => const <WalletShare>[]),
        incomeExpenseProvider.overrideWith(
          (ref) async => const IncomeExpense(incomePaise: 0, expensePaise: 0),
        ),
        expenseCategoryProvider.overrideWith(
          (ref) async => const <CategoryShare>[],
        ),
      ],
      child: const MaterialApp(home: MainNav()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('renders 5 tabs in order: Home, History, Debt, Cart, Stats',
      (tester) async {
    await _pumpNav(tester);

    // Home starts active, so its icon is the filled variant; the rest are
    // outlined (mist).
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.handshake_outlined), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart_outlined), findsOneWidget);

    // No text labels under the icons (icon-inside only).
    expect(find.text('Home'), findsNothing);

    // Cart badge still renders its count, and the Debt tab shows its open
    // count badge.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('no center button, no notch, no chooser in the tree',
      (tester) async {
    await _pumpNav(tester);

    // No raised center + and no chooser sheet title anywhere.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.text('Record money'), findsNothing);
    expect(
      find.bySemanticsLabel('Add or subtract money'),
      findsNothing,
    );
  });

  testWidgets('tapping the Debt tab swaps it to the filled variant',
      (tester) async {
    await _pumpNav(tester);
    expect(find.byIcon(Icons.handshake_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.handshake_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.handshake), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('no RenderFlex overflow and no clipped layout errors',
      (tester) async {
    await _pumpNav(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a tab swaps it to the filled emerald variant',
      (tester) async {
    await _pumpNav(tester);
    expect(find.byIcon(Icons.bar_chart_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('reduced motion renders the solid fallback without errors',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpNav(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('nav_triangle')), findsOneWidget);
  });

  testWidgets('sliding triangle marks the active tab and survives tab swaps',
      (tester) async {
    await _pumpNav(tester);
    expect(find.byKey(const Key('nav_triangle')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The single marker glides (transform-only) — still exactly one, no
    // overflow from the strip above the pill.
    expect(find.byKey(const Key('nav_triangle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('triangle visits all 5 tabs', (tester) async {
    await _pumpNav(tester);
    expect(find.byKey(const Key('nav_triangle')), findsOneWidget);

    final tabs = <Finder>[
      find.byIcon(Icons.home),
      find.byIcon(Icons.receipt_long_outlined),
      find.byIcon(Icons.handshake_outlined),
      find.byIcon(Icons.shopping_cart_outlined),
      find.byIcon(Icons.bar_chart_outlined),
    ];
    // Walk every tab; the single triangle marker must survive each glide.
    for (final tab in tabs) {
      await tester.tap(tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('nav_triangle')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    // Landed on Stats: filled chart icon, Home back to outlined.
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('Home +Add pill opens the sheet with a working X close',
      (tester) async {
    await _pumpNav(tester);

    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add money'), findsOneWidget);

    // Visible X top-right of the sheet header.
    final closeButton = find.ancestor(
      of: find.byIcon(Icons.close),
      matching: find.byType(IconButton),
    );
    expect(closeButton, findsOneWidget);

    // The X pops the sheet with a false result: no save, no snackbar.
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(find.text('Add money'), findsNothing);
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('txn sheet dismisses on outside-tap', (tester) async {
    await _pumpNav(tester);

    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add money'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Add money'), findsNothing);
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('Home −Subtract pill opens the subtract sheet',
      (tester) async {
    await _pumpNav(tester);

    await tester.tap(find.text('− Subtract'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Subtract money'), findsOneWidget);
  });
}

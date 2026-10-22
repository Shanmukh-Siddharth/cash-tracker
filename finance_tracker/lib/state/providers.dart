/// Riverpod providers. UI reads these; after any write the caller must
/// `ref.invalidate(walletsProvider)` (plus recent/today) to refresh.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database.dart';
import '../data/models/cart_item.dart';
import '../data/models/recurring_template.dart';
import '../data/models/transaction.dart';
import '../data/models/wallet.dart';
import '../data/repos/cart_repo.dart';
import '../data/repos/debt_repo.dart';
import '../data/repos/recurring_repo.dart';
import '../data/repos/stats_repo.dart';
import '../data/repos/txn_repo.dart';
import '../data/repos/wallet_repo.dart';
import '../features/lock/lock_service.dart';

/// App-wide [LockService], overridden in main() with the real instance.
/// Lets background-agnostic screens (e.g. Settings reset) force a lock.
final lockServiceProvider = Provider<LockService>(
  (_) => throw UnimplementedError('override lockServiceProvider in main()'),
);

final databaseProvider = FutureProvider<Database>((ref) async {
  return AppDb.instance.database;
});

final walletRepoProvider = FutureProvider<WalletRepo>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return WalletRepo(db);
});

final txnRepoProvider = FutureProvider<TxnRepo>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return TxnRepo(db);
});

/// All wallets ordered by id.
final walletsProvider = FutureProvider<List<Wallet>>((ref) async {
  final repo = await ref.watch(walletRepoProvider.future);
  return repo.listWallets();
});

/// Total balance = sum of all wallets, in paise.
final totalProvider = FutureProvider<int>((ref) async {
  final wallets = await ref.watch(walletsProvider.future);
  return wallets.fold<int>(0, (sum, w) => sum + w.balancePaise);
});

/// Newest 10 transactions for the home list.
final recentProvider = FutureProvider<List<Txn>>((ref) async {
  final repo = await ref.watch(txnRepoProvider.future);
  return repo.recentTxns();
});

/// All transactions newest-first for the History tab.
final historyProvider = FutureProvider<List<Txn>>((ref) async {
  final repo = await ref.watch(txnRepoProvider.future);
  return repo.allTxns();
});

/// Today's in/out sums for the home hero card.
final todayProvider = FutureProvider<TodayTotals>((ref) async {
  final repo = await ref.watch(txnRepoProvider.future);
  return repo.todayTotals();
});

/// Call after every txn mutation so Home + History update instantly.
void refreshAfterMutation(WidgetRef ref) {
  ref.invalidate(walletsProvider);
  ref.invalidate(totalProvider);
  ref.invalidate(recentProvider);
  ref.invalidate(todayProvider);
  ref.invalidate(historyProvider);
  ref.invalidate(cartItemsProvider);
  ref.invalidate(cartCountProvider);
  ref.invalidate(dailyExpensesProvider);
  ref.invalidate(walletShareProvider);
  ref.invalidate(incomeExpenseProvider);
  ref.invalidate(expenseCategoryProvider);
  ref.invalidate(templatesProvider);
  ref.invalidate(debtsProvider);
  ref.invalidate(debtTotalsProvider);
  ref.invalidate(debtOpenCountProvider);
}

final cartRepoProvider = FutureProvider<CartRepo>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return CartRepo(db);
});

/// Cart rows oldest-first.
final cartItemsProvider = FutureProvider<List<CartItem>>((ref) async {
  final repo = await ref.watch(cartRepoProvider.future);
  return repo.items();
});

/// Total item qty (for the Cart tab badge).
final cartCountProvider = FutureProvider<int>((ref) async {
  final repo = await ref.watch(cartRepoProvider.future);
  return repo.itemCount();
});

final statsRepoProvider = FutureProvider<StatsRepo>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return StatsRepo(db);
});

/// Daily expense activity for the last 120 days (heatmap).
final dailyExpensesProvider =
    FutureProvider<Map<DateTime, DayExpense>>((ref) async {
  final repo = await ref.watch(statsRepoProvider.future);
  return repo.dailyExpenses();
});

/// Monthly income/expense pairs for the last [months] calendar months.
final monthlyPairsProvider =
    FutureProvider.family<List<MonthlyPair>, int>((ref, months) async {
  final repo = await ref.watch(statsRepoProvider.future);
  return repo.monthlyPairs(months);
});

/// Per-wallet expense sums (wallet-share donut).
final walletShareProvider = FutureProvider<List<WalletShare>>((ref) async {
  final repo = await ref.watch(statsRepoProvider.future);
  return repo.expenseShareByWallet();
});

/// Lifetime income vs expense (second donut).
final incomeExpenseProvider = FutureProvider<IncomeExpense>((ref) async {
  final repo = await ref.watch(statsRepoProvider.future);
  return repo.incomeVsExpense();
});

/// Lifetime expense grouped by category, largest first (category donut).
final expenseCategoryProvider =
    FutureProvider<List<CategoryShare>>((ref) async {
  final repo = await ref.watch(statsRepoProvider.future);
  return repo.expenseByCategory();
});

final recurringRepoProvider = FutureProvider<RecurringRepo>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return RecurringRepo(db);
});
/// All monthly templates oldest-first.
final templatesProvider =
    FutureProvider<List<RecurringTemplate>>((ref) async {
  final repo = await ref.watch(recurringRepoProvider.future);
  return repo.listTemplates();
});

final debtRepoProvider = FutureProvider<DebtRepo>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return DebtRepo(db);
});

/// All debts newest-first (UI splits by direction/status itself).
final debtsProvider = FutureProvider<List<Debt>>((ref) async {
  final repo = await ref.watch(debtRepoProvider.future);
  return repo.listDebts();
});

/// Open-debt remaining totals per direction (header + LAN reuse the repo).
final debtTotalsProvider = FutureProvider<DebtTotals>((ref) async {
  final repo = await ref.watch(debtRepoProvider.future);
  return repo.totals();
});

/// Open debt count (Debt tab badge).
final debtOpenCountProvider = FutureProvider<int>((ref) async {
  final repo = await ref.watch(debtRepoProvider.future);
  return repo.openCount();
});

/// Read-only stats queries for the Stats tab (Phase 4).
///
/// All money is int paise. Day keys are local-midnight [DateTime]s.
library;

import 'package:sqflite/sqflite.dart';

/// One day of expense activity (for the heatmap tooltip).
class DayExpense {
  final int totalPaise;
  final int count;
  const DayExpense({required this.totalPaise, required this.count});
}

/// One month column for the income-vs-expense bar chart.
class MonthlyPair {
  final String label;
  final int incomePaise;
  final int expensePaise;
  const MonthlyPair({
    required this.label,
    required this.incomePaise,
    required this.expensePaise,
  });
}

/// One slice of the wallet-share donut.
class WalletShare {
  final int walletId;
  final String walletName;
  final int expensePaise;
  const WalletShare({
    required this.walletId,
    required this.walletName,
    required this.expensePaise,
  });
}

/// One slice of the expense-by-category donut.
class CategoryShare {
  final String category;
  final int expensePaise;
  const CategoryShare({required this.category, required this.expensePaise});
}

/// Lifetime income-vs-expense totals (for the second donut).
class IncomeExpense {
  final int incomePaise;
  final int expensePaise;
  const IncomeExpense({required this.incomePaise, required this.expensePaise});
}

const List<String> _months = <String>[
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class StatsRepo {
  final DatabaseExecutor db;
  const StatsRepo(this.db);

  /// Daily expense totals for the last [days] days (default 120).
  Future<Map<DateTime, int>> dailyExpenseTotals({int days = 120}) async {
    final stats = await dailyExpenses(days: days);
    return stats.map((day, s) => MapEntry(day, s.totalPaise));
  }

  /// Daily expense totals + txn counts for the last [days] days.
  ///
  /// `transactions.date` is written by `DateTime.now().toIso8601String()`,
  /// which is already a NAIVE LOCAL timestamp (no offset). SQLite parses such
  /// a string as UTC, so applying `'localtime'` to the column would shift every
  /// evening txn into the next day. We therefore only apply `localtime` to
  /// `'now'`, matching [TxnRepo.todayTotals].
  Future<Map<DateTime, DayExpense>> dailyExpenses({int days = 120}) async {
    final rows = await db.rawQuery(
      'SELECT date(date) AS day, '
      "SUM(amount) AS total, COUNT(*) AS n FROM transactions "
      "WHERE type = 'expense' AND date(date) >= "
      "date('now', 'localtime', ?) "
      'GROUP BY day ORDER BY day ASC',
      <Object?>['-$days days'],
    );
    final out = <DateTime, DayExpense>{};
    for (final row in rows) {
      final parts = (row['day'] as String).split('-');
      final day = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      out[day] = DayExpense(
        totalPaise: ((row['total'] as num?) ?? 0).toInt(),
        count: ((row['n'] as num?) ?? 0).toInt(),
      );
    }
    return out;
  }

  /// Last [months] calendar months (including the current one), oldest first.
  Future<List<MonthlyPair>> monthlyPairs(int months) async {
    if (months < 1) throw ArgumentError('months must be >= 1');
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - months + 1, 1);
    final startIso = start.toIso8601String();
    final rows = await db.rawQuery(
      "SELECT strftime('%Y-%m', date) AS ym, type, "
      'SUM(amount) AS total FROM transactions WHERE date >= ? '
      'GROUP BY ym, type',
      <Object?>[startIso],
    );
    final sums = <String, ({int income, int expense})>{};
    for (final row in rows) {
      final ym = row['ym'] as String;
      final total = ((row['total'] as num?) ?? 0).toInt();
      final prev = sums[ym] ?? (income: 0, expense: 0);
      sums[ym] = row['type'] == 'income'
          ? (income: prev.income + total, expense: prev.expense)
          : (income: prev.income, expense: prev.expense + total);
    }
    final out = <MonthlyPair>[];
    for (var i = 0; i < months; i++) {
      final m = DateTime(start.year, start.month + i, 1);
      final key =
          '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';
      final s = sums[key] ?? (income: 0, expense: 0);
      out.add(
        MonthlyPair(
          label: _months[m.month],
          incomePaise: s.income,
          expensePaise: s.expense,
        ),
      );
    }
    return out;
  }

  /// Per-wallet lifetime expense sums (wallets with zero spend included).
  Future<List<WalletShare>> expenseShareByWallet() async {
    final rows = await db.rawQuery(
      'SELECT w.id AS wallet_id, w.name AS wallet_name, '
      'COALESCE(SUM(CASE WHEN t.type = \'expense\' THEN t.amount END), 0) '
      'AS total FROM wallets w LEFT JOIN transactions t '
      'ON t.wallet_id = w.id GROUP BY w.id, w.name ORDER BY w.id ASC',
    );
    return rows
        .map(
          (row) => WalletShare(
            walletId: (row['wallet_id'] as num).toInt(),
            walletName: row['wallet_name'] as String,
            expensePaise: ((row['total'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  /// Lifetime expense sums grouped by category, largest first. Rows that
  /// predate v2 carry the backfilled default, so they land in Miscellaneous.
  Future<List<CategoryShare>> expenseByCategory() async {
    final rows = await db.rawQuery(
      "SELECT COALESCE(category, 'Miscellaneous') AS category, "
      "SUM(amount) AS total FROM transactions WHERE type = 'expense' "
      'GROUP BY category ORDER BY total DESC',
    );
    return rows
        .map(
          (row) => CategoryShare(
            category: row['category'] as String,
            expensePaise: ((row['total'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  /// Lifetime income vs expense totals.
  Future<IncomeExpense> incomeVsExpense() async {
    final rows = await db.rawQuery(
      'SELECT type, SUM(amount) AS total FROM transactions GROUP BY type',
    );
    var income = 0;
    var expense = 0;
    for (final row in rows) {
      final total = ((row['total'] as num?) ?? 0).toInt();
      if (row['type'] == 'income') {
        income = total;
      } else {
        expense = total;
      }
    }
    return IncomeExpense(incomePaise: income, expensePaise: expense);
  }
}

/// Stats tab (Phase 4 + Phase 8): GitHub-style expense heatmap, grouped
/// monthly income-vs-expense bars (fl_chart), and three donuts (wallet share
/// + category share + income vs expense). Range chips 3M / 6M / 1Y select
/// 3 / 6 / 12 months.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/repos/stats_repo.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';
import 'stats_math.dart';

/// Donut slice palette (Demo-1 emerald + gold + rose + teal + white).
const List<Color> _sliceColors = <Color>[
  AppColors.primary,
  AppColors.gold,
  Color(0xFF2DD4BF),
  AppColors.text2,
  AppColors.danger,
];

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _months = 6;

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyExpensesProvider);
    final monthly = ref.watch(monthlyPairsProvider(_months));
    final share = ref.watch(walletShareProvider);
    final byCategory = ref.watch(expenseCategoryProvider);
    final totals = ref.watch(incomeExpenseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 3, label: Text('3M')),
              ButtonSegment<int>(value: 6, label: Text('6M')),
              ButtonSegment<int>(value: 12, label: Text('1Y')),
            ],
            selected: <int>{_months},
            onSelectionChanged: (set) =>
                setState(() => _months = set.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.2),
              selectedForegroundColor: AppColors.text,
              foregroundColor: AppColors.text2,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const _SectionTitle('Spending heatmap · 120 days'),
          const SizedBox(height: 8),
          daily.when(
            data: (map) => map.isEmpty
                ? const EmptyState(
                    icon: Icons.calendar_view_month_outlined,
                    title: 'No data yet — add your first entry',
                    subtitle:
                        'Daily spending intensity shows up here.',
                  )
                : _Heatmap(data: map),
            loading: () => const _Loading(),
            error: (_, _) => const _LoadError(),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Income vs expense · $_months months'),
          const SizedBox(height: 8),
          monthly.when(
            data: (pairs) {
              final hasData = pairs.any(
                (p) => p.incomePaise > 0 || p.expensePaise > 0,
              );
              if (!hasData) {
                return const EmptyState(
                  icon: Icons.bar_chart_outlined,
                  title: 'No data yet — add your first entry',
                  subtitle: 'Monthly income vs expense renders here.',
                );
              }
              return _MonthlyBars(pairs: pairs);
            },
            loading: () => const _Loading(),
            error: (_, _) => const _LoadError(),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Wallet share'),
          const SizedBox(height: 8),
          share.when(
            data: (slices) {
              final hasData =
                  slices.any((s) => s.expensePaise > 0);
              if (!hasData) {
                return const EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: 'No data yet — add your first entry',
                  subtitle: 'Wallet-wise expense share renders here.',
                );
              }
              return _DonutCard(
                title: 'Expense by wallet',
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    if (slices[i].expensePaise > 0)
                      PieChartSectionData(
                        value: slices[i].expensePaise.toDouble(),
                        color: _sliceColors[i % _sliceColors.length],
                        title:
                            '${(100 * slices[i].expensePaise / slices.fold<int>(0, (s, e) => s + e.expensePaise)).round()}%',
                        radius: 44,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkOnPrimary,
                        ),
                      ),
                ],
                centerLabel: formatPaise(
                  slices.fold<int>(0, (s, e) => s + e.expensePaise),
                ),
                legend: [
                  for (var i = 0; i < slices.length; i++)
                    if (slices[i].expensePaise > 0)
                      _LegendItem(
                        color: _sliceColors[i % _sliceColors.length],
                        label:
                            '${slices[i].walletName} ${formatPaise(slices[i].expensePaise)}',
                      ),
                ],
              );
            },
            loading: () => const _Loading(),
            error: (_, _) => const _LoadError(),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Expense by category'),
          const SizedBox(height: 8),
          byCategory.when(
            data: (slices) {
              final nonZero =
                  slices.where((s) => s.expensePaise > 0).toList();
              if (nonZero.isEmpty) {
                return const EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: 'No data yet — add your first entry',
                  subtitle: 'Category-wise expense share renders here.',
                );
              }
              // Top 6 + Other (rest).
              final top = nonZero.take(6).toList();
              final rest = nonZero.skip(6).toList();
              final shown = <CategoryShare>[
                ...top,
                if (rest.isNotEmpty)
                  CategoryShare(
                    category: 'Other',
                    expensePaise: rest.fold<int>(
                      0,
                      (s, e) => s + e.expensePaise,
                    ),
                  ),
              ];
              final grand = shown.fold<int>(
                0,
                (s, e) => s + e.expensePaise,
              );
              return _DonutCard(
                title: 'Expense by category',
                sections: [
                  for (var i = 0; i < shown.length; i++)
                    PieChartSectionData(
                      value: shown[i].expensePaise.toDouble(),
                      color: _sliceColors[i % _sliceColors.length],
                      title:
                          '${(100 * shown[i].expensePaise / grand).round()}%',
                      radius: 44,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkOnPrimary,
                      ),
                    ),
                ],
                centerLabel: formatPaise(grand),
                legend: [
                  for (var i = 0; i < shown.length; i++)
                    _LegendItem(
                      color: _sliceColors[i % _sliceColors.length],
                      label:
                          '${shown[i].category} ${formatPaise(shown[i].expensePaise)}',
                    ),
                ],
              );
            },
            loading: () => const _Loading(),
            error: (_, _) => const _LoadError(),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Income vs expense'),
          const SizedBox(height: 8),
          totals.when(
            data: (t) {
              if (t.incomePaise == 0 && t.expensePaise == 0) {
                return const EmptyState(
                  icon: Icons.donut_small_outlined,
                  title: 'No data yet — add your first entry',
                  subtitle: 'Lifetime income vs expense renders here.',
                );
              }
              final total = t.incomePaise + t.expensePaise;
              return _DonutCard(
                title: 'Lifetime',
                sections: [
                  if (t.incomePaise > 0)
                    PieChartSectionData(
                      value: t.incomePaise.toDouble(),
                      color: AppColors.primary,
                      title: '${(100 * t.incomePaise / total).round()}%',
                      radius: 44,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkOnPrimary,
                      ),
                    ),
                  if (t.expensePaise > 0)
                    PieChartSectionData(
                      value: t.expensePaise.toDouble(),
                      color: AppColors.danger,
                      title: '${(100 * t.expensePaise / total).round()}%',
                      radius: 44,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkOnPrimary,
                      ),
                    ),
                ],
                centerLabel: formatPaise(total),
                legend: [
                  _LegendItem(
                    color: AppColors.primary,
                    label: 'In ${formatPaise(t.incomePaise)}',
                  ),
                  _LegendItem(
                    color: AppColors.danger,
                    label: 'Out ${formatPaise(t.expensePaise)}',
                  ),
                ],
              );
            },
            loading: () => const _Loading(),
            error: (_, _) => const _LoadError(),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Could not load stats',
        style: TextStyle(color: AppColors.danger),
      ),
    );
  }
}

/// GitHub-style heatmap: 7 rows (Mon..Sun) × week columns. 12px cells, 4px
/// gap, 5-step scale (emerald 1..3, gold top bucket). Tap → snackbar with
/// the day total + txn count. Entrance staggers ≤6ms/cell (skipped when
/// the OS disables animations).
class _Heatmap extends StatefulWidget {
  final Map<DateTime, DayExpense> data;
  const _Heatmap({required this.data});

  @override
  State<_Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends State<_Heatmap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const double _cell = 12;
  static const double _gap = 4;

  Color _colorFor(int intensity) {
    switch (intensity) {
      case 1:
        return AppColors.primary.withValues(alpha: 0.25);
      case 2:
        return AppColors.primary.withValues(alpha: 0.55);
      case 3:
        return AppColors.primary;
      case 4:
        return AppColors.gold;
      default:
        return AppColors.line;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    const days = 120;
    final first = todayMid.subtract(const Duration(days: days - 1));
    // Align the grid start back to Monday (weekday 1).
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final totalDays = todayMid.difference(gridStart).inDays + 1;
    final weeks = (totalDays / 7).ceil();

    var maxTotal = 0;
    for (final s in widget.data.values) {
      if (s.totalPaise > maxTotal) maxTotal = s.totalPaise;
    }

    var cellIndex = 0;
    final columns = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final cells = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final day = gridStart.add(Duration(days: w * 7 + d));
        if (day.isAfter(todayMid) || day.isBefore(first)) {
          cells.add(const SizedBox(width: _cell, height: _cell));
        } else {
          final stat = widget.data[day];
          final intensity =
              intensityFor(stat?.totalPaise ?? 0, maxTotal);
          final color = _colorFor(intensity);
          final tooltipText = stat == null
              ? '${_fmtDay(day)} · no spend'
              : '${_fmtDay(day)} · ${formatPaise(stat.totalPaise)}'
                  ' · ${stat.count} txn${stat.count == 1 ? '' : 's'}';
          final cell = GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tooltipText),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Semantics(
              button: true,
              label: tooltipText,
              child: Container(
                width: _cell,
                height: _cell,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          );
          if (reduceMotion) {
            cells.add(cell);
          } else {
            // Stagger ≤6ms/cell, capped so the whole grid lands ≤ ~500ms.
            final delayMs = (cellIndex * 6).clamp(0, 300);
            final start = delayMs / 500;
            cells.add(
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: _controller,
                  curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
                      curve: Curves.easeOut),
                ),
                child: cell,
              ),
            );
          }
          cellIndex++;
        }
        if (d < 6) cells.add(const SizedBox(height: _gap));
      }
      columns.add(Column(mainAxisSize: MainAxisSize.min, children: cells));
      if (w < weeks - 1) columns.add(const SizedBox(width: _gap));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Less',
                  style: TextStyle(fontSize: 11, color: AppColors.text3)),
              const SizedBox(width: 6),
              for (var i = 0; i <= 4; i++) ...[
                Container(
                  width: _cell,
                  height: _cell,
                  decoration: BoxDecoration(
                    color: _colorFor(i),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Text('More',
                  style: TextStyle(fontSize: 11, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDay(DateTime day) =>
      '${day.day} ${_shortMonth(day.month)} ${day.year}';

  static String _shortMonth(int m) => const <String>[
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m];
}

/// Grouped monthly bars: income (emerald) vs expense (rose), rounded tops,
/// touch tooltip with ₹. Grows in ≤500ms once via fl_chart swap animation.
class _MonthlyBars extends StatelessWidget {
  final List<MonthlyPair> pairs;
  const _MonthlyBars({required this.pairs});

  @override
  Widget build(BuildContext context) {
    var maxY = 0.0;
    for (final p in pairs) {
      if (p.incomePaise.toDouble() > maxY) maxY = p.incomePaise.toDouble();
      if (p.expensePaise.toDouble() > maxY) maxY = p.expensePaise.toDouble();
    }
    if (maxY <= 0) maxY = 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.15,
                barGroups: [
                  for (var i = 0; i < pairs.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: pairs[i].incomePaise.toDouble(),
                          color: AppColors.primary,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                        BarChartRodData(
                          toY: pairs[i].expensePaise.toDouble(),
                          color: AppColors.danger,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                ],
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= pairs.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            pairs[i].label,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.text3,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBorder: BorderSide(color: AppColors.line),
                    getTooltipItem:
                        (group, groupIndex, rod, rodIndex) {
                      final p = pairs[group.x];
                      final amount = rodIndex == 0
                          ? p.incomePaise
                          : p.expensePaise;
                      return BarTooltipItem(
                        '${p.label} ${rodIndex == 0 ? 'in' : 'out'}\n'
                        '${formatPaise(amount)}',
                        const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      );
                    },
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendItem(color: AppColors.primary, label: 'Income'),
              SizedBox(width: 16),
              _LegendItem(color: AppColors.danger, label: 'Expense'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutCard extends StatelessWidget {
  final String title;
  final List<PieChartSectionData> sections;
  final String centerLabel;
  final List<Widget> legend;

  const _DonutCard({
    required this.title,
    required this.sections,
    required this.centerLabel,
    required this.legend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 52,
                    sectionsSpace: 2,
                  ),
                  duration:
                      const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                ),
                Text(
                  centerLabel,
                  style: AppText.mono(15),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 6, children: legend),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.text2),
        ),
      ],
    );
  }
}

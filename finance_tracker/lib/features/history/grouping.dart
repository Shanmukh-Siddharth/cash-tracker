/// Pure History helpers: day grouping + search/filter predicates.
///
/// No Flutter imports — unit-testable with plain `Txn` objects.
library;

import 'package:intl/intl.dart';

import '../../data/models/transaction.dart';

/// One date section in the History list (newest first).
class DayGroup {
  final DateTime day;
  final String header;
  final List<Txn> txns;

  const DayGroup({
    required this.day,
    required this.header,
    required this.txns,
  });
}

final _headerFormat = DateFormat('d MMM yyyy');

String _headerFor(DateTime day, DateTime today) {
  final todayDate = DateTime(today.year, today.month, today.day);
  final diff = todayDate.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return _headerFormat.format(day);
}

/// Groups txns into day sections, newest day first, txns newest-first inside.
///
/// [now] is injectable for tests; defaults to [DateTime.now].
List<DayGroup> groupByDay(List<Txn> txns, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final sorted = List<Txn>.of(txns)
    ..sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      return (b.id ?? 0).compareTo(a.id ?? 0);
    });
  final groups = <DayGroup>[];
  for (final txn in sorted) {
    final parsed = DateTime.tryParse(txn.date)?.toLocal();
    final day = parsed == null
        ? DateTime(today.year, today.month, today.day)
        : DateTime(parsed.year, parsed.month, parsed.day);
    if (groups.isNotEmpty &&
        groups.last.day.year == day.year &&
        groups.last.day.month == day.month &&
        groups.last.day.day == day.day) {
      groups.last.txns.add(txn);
    } else {
      groups.add(
        DayGroup(day: day, header: _headerFor(day, today), txns: <Txn>[txn]),
      );
    }
  }
  return groups;
}

enum TxnFilter { all, income, expense }

/// True when [txn] matches the free-text query (from_for + note + category,
/// any case).
bool txnMatchesQuery(Txn txn, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (txn.fromFor.toLowerCase().contains(q)) return true;
  if ((txn.note ?? '').toLowerCase().contains(q)) return true;
  return txn.category.toLowerCase().contains(q);
}

/// Applies type + wallet + query filters. [walletId] null = all wallets.
List<Txn> filterTxns(
  List<Txn> txns, {
  TxnFilter type = TxnFilter.all,
  int? walletId,
  String query = '',
}) {
  return txns.where((t) {
    if (type == TxnFilter.income && t.type != TxnType.income) return false;
    if (type == TxnFilter.expense && t.type != TxnType.expense) return false;
    if (walletId != null && t.walletId != walletId) return false;
    return txnMatchesQuery(t, query);
  }).toList();
}

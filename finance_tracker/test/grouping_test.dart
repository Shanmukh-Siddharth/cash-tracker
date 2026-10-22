// Unit tests for History grouping + search/filter predicates (pure logic).
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/features/history/grouping.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _txn({
  int? id,
  int walletId = 1,
  TxnType type = TxnType.expense,
  int amountPaise = 1000,
  String fromFor = 'Chai',
  String? note,
  required DateTime date,
}) {
  final iso = date.toIso8601String();
  return Txn(
    id: id,
    walletId: walletId,
    type: type,
    amountPaise: amountPaise,
    fromFor: fromFor,
    note: note,
    date: iso,
    createdAt: iso,
  );
}

void main() {
  group('groupByDay', () {
    test('empty list gives no groups', () {
      expect(groupByDay(const <Txn>[], now: DateTime(2026, 10, 8)), isEmpty);
    });

    test('today / yesterday / date headers in newest-first order', () {
      final now = DateTime(2026, 10, 8, 12);
      final txns = <Txn>[
        _txn(id: 1, fromFor: 'Old', date: DateTime(2026, 10, 6, 9)),
        _txn(id: 2, fromFor: 'Now', date: DateTime(2026, 10, 8, 9)),
        _txn(id: 3, fromFor: 'Yday', date: DateTime(2026, 10, 7, 20)),
        _txn(id: 4, fromFor: 'Now2', date: DateTime(2026, 10, 8, 8)),
      ];
      final groups = groupByDay(txns, now: now);
      expect(groups.map((g) => g.header), ['Today', 'Yesterday', '6 Oct 2026']);
      expect(groups[0].txns.map((t) => t.fromFor), ['Now', 'Now2']);
      expect(groups[1].txns.single.fromFor, 'Yday');
      expect(groups[2].txns.single.fromFor, 'Old');
    });

    test('same-day txns share one group', () {
      final now = DateTime(2026, 10, 8, 12);
      final txns = <Txn>[
        _txn(id: 1, date: DateTime(2026, 10, 8, 9)),
        _txn(id: 2, date: DateTime(2026, 10, 8, 10)),
      ];
      final groups = groupByDay(txns, now: now);
      expect(groups, hasLength(1));
      expect(groups.single.header, 'Today');
      expect(groups.single.txns, hasLength(2));
    });
  });

  group('txnMatchesQuery', () {
    final txn = _txn(
      fromFor: 'Salary',
      note: 'October payout',
      date: DateTime(2026, 10, 8),
    );

    test('matches from_for case-insensitively', () {
      expect(txnMatchesQuery(txn, 'salary'), isTrue);
      expect(txnMatchesQuery(txn, 'SAL'), isTrue);
    });

    test('matches note', () {
      expect(txnMatchesQuery(txn, 'payout'), isTrue);
    });

    test('empty query matches everything', () {
      expect(txnMatchesQuery(txn, ''), isTrue);
      expect(txnMatchesQuery(txn, '   '), isTrue);
    });

    test('non-matching query returns false', () {
      expect(txnMatchesQuery(txn, 'chai'), isFalse);
    });
  });

  group('filterTxns', () {
    final now = DateTime(2026, 10, 8);
    final txns = <Txn>[
      _txn(id: 1, walletId: 1, type: TxnType.income, fromFor: 'Salary', date: now),
      _txn(id: 2, walletId: 1, type: TxnType.expense, fromFor: 'Chai', date: now),
      _txn(id: 3, walletId: 2, type: TxnType.expense, fromFor: 'Petrol', date: now),
    ];

    test('type filter', () {
      expect(filterTxns(txns, type: TxnFilter.income).map((t) => t.id), [1]);
      expect(
        filterTxns(txns, type: TxnFilter.expense).map((t) => t.id),
        [2, 3],
      );
      expect(filterTxns(txns), hasLength(3));
    });

    test('wallet filter', () {
      expect(filterTxns(txns, walletId: 2).map((t) => t.id), [3]);
    });

    test('query filter', () {
      expect(filterTxns(txns, query: 'chai').map((t) => t.id), [2]);
    });

    test('combined filters intersect', () {
      expect(
        filterTxns(txns, type: TxnFilter.expense, walletId: 1).map((t) => t.id),
        [2],
      );
    });
  });
}

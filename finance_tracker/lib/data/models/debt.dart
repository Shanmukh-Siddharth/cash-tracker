/// Track-only debt memo models (v3). Debts NEVER touch wallet balances and
/// create NO transactions — pure memo rows with computed `remaining`.
library;

class Debt {
  final int? id;
  final String person;
  final int amountPaise;
  final String direction; // 'owe' (I owe them) | 'lent'
  final String? note;
  final String date;
  final String status; // 'open' | 'settled'
  final String createdAt;

  /// Paid so far (paise). Filled by the repo; 0 for hand-built rows.
  final int paidPaise;

  const Debt({
    this.id,
    required this.person,
    required this.amountPaise,
    required this.direction,
    this.note,
    required this.date,
    this.status = 'open',
    required this.createdAt,
    this.paidPaise = 0,
  });

  int get remainingPaise => amountPaise - paidPaise;

  bool get isOwe => direction == 'owe';
  bool get isOpen => status == 'open';

  factory Debt.fromMap(Map<String, Object?> map, {int paidPaise = 0}) => Debt(
        id: map['id'] as int?,
        person: map['person'] as String,
        amountPaise: (map['amount'] as num).toInt(),
        direction: map['direction'] as String,
        note: map['note'] as String?,
        date: map['date'] as String,
        status: (map['status'] as String?) ?? 'open',
        createdAt: map['created_at'] as String,
        paidPaise: paidPaise,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'person': person,
        'amount': amountPaise,
        'direction': direction,
        'note': note,
        'date': date,
        'status': status,
        'created_at': createdAt,
      };
}

class DebtPayment {
  final int? id;
  final int debtId;
  final int amountPaise;
  final String date;
  final String? note;

  const DebtPayment({
    this.id,
    required this.debtId,
    required this.amountPaise,
    required this.date,
    this.note,
  });

  factory DebtPayment.fromMap(Map<String, Object?> map) => DebtPayment(
        id: map['id'] as int?,
        debtId: (map['debt_id'] as num).toInt(),
        amountPaise: (map['amount'] as num).toInt(),
        date: map['date'] as String,
        note: map['note'] as String?,
      );
}

/// Pure helper: remaining = amount - SUM(payments). Never negative-clamped
/// here — overpay is rejected in [DebtRepo.addPayment] instead.
int remainingOf(int amountPaise, List<DebtPayment> payments) =>
    amountPaise - payments.fold<int>(0, (s, p) => s + p.amountPaise);

/// Open-debt remaining totals, in paise.
class DebtTotals {
  final int oweTotal;
  final int lentTotal;
  const DebtTotals({required this.oweTotal, required this.lentTotal});
}

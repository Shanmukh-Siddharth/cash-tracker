/// Transaction model. Amount is int paise. Category defaults to the list
/// tail (Miscellaneous/Other) when the DB row predates v2 (no column).
library;

import '../categories.dart';

enum TxnType { income, expense }

TxnType txnTypeFromString(String value) =>
    value == 'income' ? TxnType.income : TxnType.expense;

String txnTypeToString(TxnType type) =>
    type == TxnType.income ? 'income' : 'expense';

class Txn {
  final int? id;
  final int walletId;
  final TxnType type;

  /// Amount in paise, always > 0.
  final int amountPaise;

  /// "From whom" (income) or "For what" (expense). Required.
  final String fromFor;
  final String? note;

  /// Category tag (e.g. Food, Salary). Never null in memory: v1 rows without
  /// the column backfill to the expense default.
  final String category;

  /// ISO8601 transaction date (may differ from createdAt after edits).
  final String date;
  final String createdAt;

  /// Populated only on joined reads (recent list). Never written to DB.
  final String? walletName;

  const Txn({
    this.id,
    required this.walletId,
    required this.type,
    required this.amountPaise,
    required this.fromFor,
    this.note,
    this.category = 'Miscellaneous',
    required this.date,
    required this.createdAt,
    this.walletName,
  });

  factory Txn.fromMap(Map<String, Object?> map) => Txn(
        id: map['id'] as int?,
        walletId: (map['wallet_id'] as num).toInt(),
        type: txnTypeFromString(map['type'] as String),
        amountPaise: (map['amount'] as num).toInt(),
        fromFor: map['from_for'] as String,
        note: map['note'] as String?,
        category: (map['category'] as String?) ??
            defaultCategory(
              (map['type'] as String) == 'income',
            ),
        date: map['date'] as String,
        createdAt: map['created_at'] as String,
        walletName: map['wallet_name'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'wallet_id': walletId,
        'type': txnTypeToString(type),
        'amount': amountPaise,
        'from_for': fromFor,
        'note': note,
        'category': category,
        'date': date,
        'created_at': createdAt,
      };
}

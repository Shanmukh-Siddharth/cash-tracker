/// Monthly template model (Phase 8).
///
/// Templates never move money by themselves — the user materializes them
/// into REAL txns via [+ Add] or Add-all-due on the Monthly items screen.
/// No scheduler reads this table.
library;

import 'transaction.dart';

class RecurringTemplate {
  final int? id;
  final String name;
  final int amountPaise;
  final int walletId;
  final TxnType type;
  final String createdAt;

  /// ISO8601 of the last manual add, or null when never added.
  final String? lastAddedAt;

  /// Populated only on joined reads. Never written to DB.
  final String? walletName;

  const RecurringTemplate({
    this.id,
    required this.name,
    required this.amountPaise,
    required this.walletId,
    required this.type,
    required this.createdAt,
    this.lastAddedAt,
    this.walletName,
  });

  factory RecurringTemplate.fromMap(Map<String, Object?> map) =>
      RecurringTemplate(
        id: map['id'] as int?,
        name: map['name'] as String,
        amountPaise: (map['amount'] as num).toInt(),
        walletId: (map['wallet_id'] as num).toInt(),
        type: txnTypeFromString(map['type'] as String),
        createdAt: map['created_at'] as String,
        lastAddedAt: map['last_added_at'] as String?,
        walletName: map['wallet_name'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'amount': amountPaise,
        'wallet_id': walletId,
        'type': txnTypeToString(type),
        'created_at': createdAt,
        'last_added_at': lastAddedAt,
      };

  /// Due when never added, or the last add is older than 30 days.
  bool get isDue {
    final last = lastAddedAt;
    if (last == null) return true;
    final parsed = DateTime.tryParse(last);
    if (parsed == null) return true;
    return DateTime.now().difference(parsed).inDays >= 30;
  }
}

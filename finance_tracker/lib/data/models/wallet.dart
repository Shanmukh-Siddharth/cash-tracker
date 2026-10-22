/// Wallet model. Balance is int paise.
library;

class Wallet {
  final int? id;
  final String name;

  /// Balance in paise (can be 0, never negative via repo guards).
  final int balancePaise;
  final String createdAt;

  const Wallet({
    this.id,
    required this.name,
    required this.balancePaise,
    required this.createdAt,
  });

  factory Wallet.fromMap(Map<String, Object?> map) => Wallet(
        id: map['id'] as int?,
        name: map['name'] as String,
        balancePaise: (map['balance'] as num).toInt(),
        createdAt: map['created_at'] as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'balance': balancePaise,
        'created_at': createdAt,
      };
}

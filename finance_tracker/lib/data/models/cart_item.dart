/// Cart item model (Phase 3). Price is int paise. No balance effect until Buy.
library;

class CartItem {
  final int? id;
  final String name;

  /// Unit price in paise, always > 0.
  final int pricePaise;
  final int qty;
  final String addedAt;

  const CartItem({
    this.id,
    required this.name,
    required this.pricePaise,
    required this.qty,
    required this.addedAt,
  });

  int get totalPaise => pricePaise * qty;

  factory CartItem.fromMap(Map<String, Object?> map) => CartItem(
        id: map['id'] as int?,
        name: map['name'] as String,
        pricePaise: (map['price'] as num).toInt(),
        qty: (map['qty'] as num).toInt(),
        addedAt: map['added_at'] as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'price': pricePaise,
        'qty': qty,
        'added_at': addedAt,
      };
}

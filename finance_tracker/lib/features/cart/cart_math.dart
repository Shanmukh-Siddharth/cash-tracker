/// Pure cart math (paise ints, no Flutter imports — unit-testable).
library;

import '../../data/models/cart_item.dart';

/// Total cost = sum(price * qty).
int cartTotal(List<CartItem> items) =>
    items.fold<int>(0, (sum, i) => sum + i.pricePaise * i.qty);

/// Balance the selected wallet would have after buying. May be negative
/// (caller treats < 0 as "insufficient" and blocks Buy).
int ifBought(int balancePaise, int totalPaise) => balancePaise - totalPaise;

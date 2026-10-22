/// Transaction categories (Phase 8).
///
/// Expense list keeps `Miscellaneous` LAST; income list keeps `Other` last.
/// New transactions default to the list tail when no category is given.
library;

/// Expense categories in dropdown order (Miscellaneous LAST — do not move).
const List<String> expenseCategories = <String>[
  'Food',
  'Travel',
  'Fuel',
  'Shopping',
  'Bills',
  'Mobile Recharge',
  'Health',
  'Entertainment',
  'Education',
  'Rent',
  'Subscriptions',
  'Miscellaneous',
];

/// Income categories in dropdown order (Other last — do not move).
const List<String> incomeCategories = <String>[
  'Salary',
  'Refund',
  'Gift',
  'Bonus',
  'Other',
];

/// Default category when none is supplied for [income] (true) or expense.
String defaultCategory(bool income) =>
    income ? incomeCategories.last : expenseCategories.last;

/// True when [category] is a known value for the given side.
bool isValidCategory(String category, {required bool income}) =>
    (income ? incomeCategories : expenseCategories).contains(category);

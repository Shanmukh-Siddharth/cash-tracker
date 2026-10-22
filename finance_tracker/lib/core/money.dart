/// Money helpers: amounts are stored as **int paise** everywhere in the DB.
///
/// Pure functions, no dependencies — safe to unit test.
library;

/// Formats paise as INR with Indian digit grouping, e.g. 1245000 -> ₹12,450.00.
String formatPaise(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '$sign₹${_groupIndian(rupees)}.$frac';
}

/// Indian grouping: last 3 digits, then groups of 2 (e.g. 100000 -> 1,00,000).
String _groupIndian(int n) {
  final s = n.toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var head = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.add(head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  parts.add(head);
  return '${parts.reversed.join(',')},$last3';
}

/// Parses user input to paise. Strips ₹, commas and spaces.
///
/// Returns null for: empty, non-numeric, zero, negative, or >2 decimals.
int? parseToPaise(String raw) {
  var s = raw.trim().replaceAll('₹', '').replaceAll(',', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (s.startsWith('-') || s.startsWith('+')) return null;
  if (RegExp(r'^\d+(\.\d{1,2})?$').firstMatch(s) == null) return null;
  final dot = s.indexOf('.');
  if (dot == -1) {
    final rupees = int.tryParse(s);
    if (rupees == null) return null;
    final total = rupees * 100;
    return total > 0 ? total : null;
  }
  final whole = s.substring(0, dot);
  final frac = s.substring(dot + 1);
  if (whole.isEmpty) return null;
  final rupees = int.tryParse(whole);
  final fracValue = int.tryParse(('${frac}00').substring(0, 2));
  if (rupees == null || fracValue == null) return null;
  final total = rupees * 100 + fracValue;
  return total > 0 ? total : null;
}

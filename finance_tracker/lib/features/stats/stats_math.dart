/// Pure stats helpers (no Flutter imports — unit-testable).
library;

/// Maps a day total to a heatmap intensity bucket 0..4.
///
/// 0 = no spend. Otherwise the day is ranked against [maxTotal] by quartiles;
/// the top bucket (4) renders gold, 1..3 emerald steps.
int intensityFor(int totalPaise, int maxTotal) {
  if (totalPaise <= 0 || maxTotal <= 0) return 0;
  final ratio = totalPaise / maxTotal;
  if (ratio >= 0.75) return 4;
  if (ratio >= 0.5) return 3;
  if (ratio >= 0.25) return 2;
  return 1;
}

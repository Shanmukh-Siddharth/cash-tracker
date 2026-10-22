// Heatmap intensity-bucket tests: raw day totals map to 0..4.
import 'package:finance_tracker/features/stats/stats_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero spend (or zero max) is bucket 0', () {
    expect(intensityFor(0, 10000), 0);
    expect(intensityFor(5000, 0), 0);
    expect(intensityFor(-5, 10000), 0);
  });

  test('quartiles map to buckets 1..3', () {
    expect(intensityFor(1000, 10000), 1); // 10%
    expect(intensityFor(3000, 10000), 2); // 30%
    expect(intensityFor(6000, 10000), 3); // 60%
  });

  test('top quartile is the gold bucket 4', () {
    expect(intensityFor(8000, 10000), 4);
    expect(intensityFor(10000, 10000), 4);
  });

  test('bucket boundaries are inclusive at the bottom', () {
    expect(intensityFor(2500, 10000), 2);
    expect(intensityFor(5000, 10000), 3);
    expect(intensityFor(7500, 10000), 4);
  });
}

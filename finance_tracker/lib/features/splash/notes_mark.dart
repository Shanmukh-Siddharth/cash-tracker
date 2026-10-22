/// Note and Bars mark (concept-C) painter for the cold-start splash sting.
///
/// Mirrors `Logos/anim-c-note-bars.html`: four build-on pieces painted from
/// the `Logos/concept-c-note-bars.svg` 256-box coordinates —
/// bars (3 emerald rounded rects), arrows (2 white triangles),
/// note (gold note + ink coin + gold dot), swoosh (teal arc + head) —
/// each driven by a 0..1 progress for fade + pop-scale. No new dependencies.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Stagger math for the splash build-on: maps controller time `t` (0..1) to
/// a per-piece 0..1 progress over `[start..end]`, clamped at both ends.
double pieceProgress(double t, double start, double end) {
  if (t <= start) return 0.0;
  if (t >= end) return 1.0;
  return (t - start) / (end - start);
}

/// Pop easing shared by every piece: scale 0.6→1 with overshoot.
/// Same curve as the web sting (`cubic-bezier(.34,1.56,.64,1)`).
const notesPop = Cubic(0.34, 1.56, 0.64, 1);

/// Teal swoosh ink (`#2DD4BF` in the SVG kit; not an app theme token).
const notesTeal = Color(0xFF2DD4BF);

/// Sized mark widget. The parent fixes the box (splash uses ~160px, lock
/// uses 56px); coordinates below are authored in the 256 SVG box and
/// scaled to fit.
class NotesMark extends StatelessWidget {
  final double bar1;
  final double bar2;
  final double bar3;
  final double arrows;
  final double note;
  final double swoosh;

  const NotesMark({
    super.key,
    required this.bar1,
    required this.bar2,
    required this.bar3,
    required this.arrows,
    required this.note,
    required this.swoosh,
  });

  /// Static full mark (every piece at progress 1), e.g. for the lock screen.
  const NotesMark.full({super.key})
      : bar1 = 1.0,
        bar2 = 1.0,
        bar3 = 1.0,
        arrows = 1.0,
        note = 1.0,
        swoosh = 1.0;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: NotesMarkPainter(
        bar1: bar1,
        bar2: bar2,
        bar3: bar3,
        arrows: arrows,
        note: note,
        swoosh: swoosh,
      ),
    );
  }
}

class NotesMarkPainter extends CustomPainter {
  final double bar1;
  final double bar2;
  final double bar3;
  final double arrows;
  final double note;
  final double swoosh;

  const NotesMarkPainter({
    required this.bar1,
    required this.bar2,
    required this.bar3,
    required this.arrows,
    required this.note,
    required this.swoosh,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Author in the 256 SVG box, scale to the laid-out (square) size.
    final s = size.width / 256.0;
    canvas.save();
    canvas.scale(s);

    // Bars grow bottom-up from the shared y=200 baseline (each rect's
    // bottom edge), mirroring `transform-origin:50% 100%` in the web sting.
    _piece(canvas, bar1, const Offset(67, 200),
        (c) => _paintBar(c, 52, 132, 30, 68));
    _piece(canvas, bar2, const Offset(107, 200),
        (c) => _paintBar(c, 92, 100, 30, 100));
    _piece(canvas, bar3, const Offset(147, 200),
        (c) => _paintBar(c, 132, 68, 30, 132));

    // Both white triangles are one build-on piece (single `.arr` group in
    // the web sting); pivot at the pair's bbox bottom-center.
    _piece(canvas, arrows, const Offset(127, 108), _paintArrows);

    // Gold note + ink coin + gold dot, one piece pivoting at note center.
    _piece(canvas, note, const Offset(102, 184), _paintNote);

    // Teal arc slides in from the left with a fade (no pop-scale).
    _swoosh(canvas, swoosh);

    canvas.restore();
  }

  /// One build-on piece: linear fade (opacity = raw progress) + pop scale
  /// 0.6→1 about [pivot] (mirrors per-piece `transform-origin`).
  void _piece(
    Canvas canvas,
    double progress,
    Offset pivot,
    void Function(Canvas) draw,
  ) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.scale(0.6 + 0.4 * notesPop.transform(p));
    canvas.translate(-pivot.dx, -pivot.dy);
    // Group fade via an alpha layer (saveLayer + translucent paint).
    canvas.saveLayer(
      null,
      Paint()..color = Color.fromARGB((255 * p).round(), 0, 0, 0),
    );
    draw(canvas);
    canvas.restore(); // layer
    canvas.restore(); // scale
  }

  /// Emerald rounded rect (r6) from the SVG kit.
  void _paintBar(Canvas canvas, double x, double y, double w, double h) {
    canvas.drawRRect(
      RRect.fromLTRBR(x, y, x + w, y + h, const Radius.circular(6)),
      Paint()..color = AppColors.primary,
    );
  }

  /// Two white triangles above bars 1–2 and 2–3 (SVG `polygon` points).
  void _paintArrows(Canvas canvas) {
    final white = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(107, 86)
        ..lineTo(119.7, 108)
        ..lineTo(94.3, 108)
        ..close(),
      white,
    );
    canvas.drawPath(
      Path()
        ..moveTo(147, 54)
        ..lineTo(159.7, 76)
        ..lineTo(134.3, 76)
        ..close(),
      white,
    );
  }

  /// Gold note ribbon + ink coin cutout + gold dot (SVG kit coordinates).
  void _paintNote(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(58, 162)
        ..cubicTo(88, 152, 114, 170, 146, 159)
        ..lineTo(146, 209)
        ..cubicTo(114, 220, 88, 202, 58, 212)
        ..close(),
      Paint()
        ..color = AppColors.gold
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      const Offset(101, 186),
      17,
      Paint()..color = AppColors.bg,
    );
    canvas.drawCircle(
      const Offset(101, 186),
      7,
      Paint()..color = AppColors.gold,
    );
  }

  /// Teal arc M28 224 C100 244 174 240 228 200 (sw14, round) + triangle
  /// head at the (228,200) end. Fade + slide in from the left; no pop.
  void _swoosh(Canvas canvas, double progress) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    // Ease-out slide: 24px left → 0.
    final e = 1 - (1 - p) * (1 - p);
    canvas.save();
    canvas.translate(-24 * (1 - e), 0);
    canvas.saveLayer(
      null,
      Paint()..color = Color.fromARGB((255 * p).round(), 0, 0, 0),
    );
    final tealStroke = Paint()
      ..color = notesTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(28, 224)
        ..cubicTo(100, 244, 174, 240, 228, 200),
      tealStroke,
    );
    // Head angle follows the SVG `arr2` marker tangent: the arc's end
    // tangent runs from control (174,240) to end (228,200), and the
    // marker (10×10 box at 3× scale, refX=8 refY=5) lands as tip (6,0)
    // with base corners (-24,±15) in the rotated frame.
    _paintHead(
      canvas,
      const Offset(228, 200),
      math.atan2(200 - 240, 228 - 174),
    );
    canvas.restore(); // layer
    canvas.restore(); // slide
  }

  /// Arrowhead matching the SVG `arr2` marker: tip 6 units past the path
  /// end along [angleRad], base 24 back and ±15 wide.
  void _paintHead(Canvas canvas, Offset at, double angleRad) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angleRad);
    canvas.drawPath(
      Path()
        ..moveTo(6, 0)
        ..lineTo(-24, -15)
        ..lineTo(-24, 15)
        ..close(),
      Paint()
        ..color = notesTeal
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(NotesMarkPainter old) =>
      old.bar1 != bar1 ||
      old.bar2 != bar2 ||
      old.bar3 != bar3 ||
      old.arrows != arrows ||
      old.note != note ||
      old.swoosh != swoosh;
}

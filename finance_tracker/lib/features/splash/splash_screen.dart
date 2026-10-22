/// Animated cold-start splash: concept-C Note and Bars build-on sting (~1.2s).
///
/// Piece intervals mirror `Logos/anim-c-note-bars.html` delays over the 1200ms
/// controller: bars 0–0.33 (bar1 0–0.20, bar2 0.07–0.27, bar3 0.13–0.33),
/// arrows 0.25–0.5, note+coin 0.42–0.67, swoosh 0.58–0.88, caption 0.75–1.0.
/// Ink bg, ~160px mark, letterspaced caption fading in last.
/// On complete [onDone] fires once (parent swaps to the lock gate — splash
/// never bypasses lock). Reduced motion: static full mark, 300ms → done.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'notes_mark.dart';

// C-sting intervals (fractions of the 1200ms controller), mirroring the
// `Logos/anim-c-note-bars.html` piece order and stagger delays.
const cBarsStart = 0.0;
const cBarsEnd = 0.33;

/// Per-bar start offsets inside the bars window (b1 0, b2 .07, b3 .13).
const cBarOffsets = <double>[0.0, 0.07, 0.13];

/// Per-bar window length: every bar is done by [cBarsEnd].
const cBarDuration = 0.20;

const cArrowsStart = 0.25;
const cArrowsEnd = 0.5;
const cNoteStart = 0.42;
const cNoteEnd = 0.67;
const cSwooshStart = 0.58;
const cSwooshEnd = 0.88;
const cCaptionStart = 0.75;
const cCaptionEnd = 1.0;

/// Reduced-motion path: static full mark, then done after this delay.
const cReducedDelayMs = 300;

/// Bar `i` (0..2) progress: staggered window inside [cBarsStart..cBarsEnd].
double cBarProgress(double t, int i) =>
    pieceProgress(t, cBarOffsets[i], cBarOffsets[i] + cBarDuration);

class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;

  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      Future.delayed(const Duration(milliseconds: cReducedDelayMs), _finish);
    } else {
      _ctrl.forward();
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Static full mark when the OS requests reduced motion.
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          final bar1 = reduced ? 1.0 : cBarProgress(t, 0);
          final bar2 = reduced ? 1.0 : cBarProgress(t, 1);
          final bar3 = reduced ? 1.0 : cBarProgress(t, 2);
          final arrows =
              reduced ? 1.0 : pieceProgress(t, cArrowsStart, cArrowsEnd);
          final note = reduced ? 1.0 : pieceProgress(t, cNoteStart, cNoteEnd);
          final swoosh =
              reduced ? 1.0 : pieceProgress(t, cSwooshStart, cSwooshEnd);
          final caption =
              reduced ? 1.0 : pieceProgress(t, cCaptionStart, cCaptionEnd);
          return SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: NotesMark(
                      bar1: bar1,
                      bar2: bar2,
                      bar3: bar3,
                      arrows: arrows,
                      note: note,
                      swoosh: swoosh,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: caption,
                    child: const Text(
                      'NEB:EXPENSE TRACKER',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.7,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

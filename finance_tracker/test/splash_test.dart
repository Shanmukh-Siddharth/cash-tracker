/// Splash stagger math + display version format + C-sting widget contract.
/// No goldens by design.
library;

import 'package:finance_tracker/core/app_version.dart';
import 'package:finance_tracker/features/splash/notes_mark.dart';
import 'package:finance_tracker/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pieceProgress', () {
    test('clamps below start to 0', () {
      expect(pieceProgress(-0.1, 0.25, 0.5), 0.0);
      expect(pieceProgress(0.0, 0.0, 0.33), 0.0);
      expect(pieceProgress(0.24, 0.25, 0.5), 0.0);
    });

    test('clamps above end to 1', () {
      expect(pieceProgress(1.0, 0.58, 0.88), 1.0);
      expect(pieceProgress(0.9, 0.58, 0.88), 1.0);
    });

    test('maps the window linearly', () {
      expect(pieceProgress(0.5, 0.25, 0.75), closeTo(0.5, 1e-9));
      expect(pieceProgress(0.25, 0.0, 0.5), closeTo(0.5, 1e-9));
    });

    test('C sting windows build bars -> arrows -> note -> swoosh in order',
        () {
      // t=0.3: lead bars done, trailing bar nearly done, arrows just
      // started, note/swoosh/caption hidden.
      expect(cBarProgress(0.3, 0), 1.0);
      expect(cBarProgress(0.3, 1), 1.0);
      expect(cBarProgress(0.3, 2), closeTo(0.17 / 0.20, 1e-9));
      expect(pieceProgress(0.3, cArrowsStart, cArrowsEnd),
          closeTo(0.05 / 0.25, 1e-9));
      expect(pieceProgress(0.3, cNoteStart, cNoteEnd), 0.0);
      expect(pieceProgress(0.3, cSwooshStart, cSwooshEnd), 0.0);
      expect(pieceProgress(0.3, cCaptionStart, cCaptionEnd), 0.0);
      // t=0.55: arrows done, note underway, swoosh hidden.
      expect(pieceProgress(0.55, cArrowsStart, cArrowsEnd), 1.0);
      expect(pieceProgress(0.55, cNoteStart, cNoteEnd), greaterThan(0.0));
      expect(pieceProgress(0.55, cNoteStart, cNoteEnd), lessThan(1.0));
      expect(pieceProgress(0.55, cSwooshStart, cSwooshEnd), 0.0);
      // t=0.8: note done, swoosh underway, caption fading in.
      expect(pieceProgress(0.8, cNoteStart, cNoteEnd), 1.0);
      expect(pieceProgress(0.8, cSwooshStart, cSwooshEnd), greaterThan(0.0));
      expect(pieceProgress(0.8, cSwooshStart, cSwooshEnd), lessThan(1.0));
      expect(pieceProgress(0.8, cCaptionStart, cCaptionEnd),
          closeTo(0.05 / 0.25, 1e-9));
      // t=1: everything complete.
      expect(cBarProgress(0.34, 0), 1.0);
      expect(cBarProgress(0.34, 1), 1.0);
      expect(cBarProgress(0.34, 2), 1.0);
      expect(pieceProgress(1.0, cArrowsStart, cArrowsEnd), 1.0);
      expect(pieceProgress(1.0, cNoteStart, cNoteEnd), 1.0);
      expect(pieceProgress(1.0, cSwooshStart, cSwooshEnd), 1.0);
      expect(pieceProgress(1.0, cCaptionStart, cCaptionEnd), 1.0);
    });

    test('interval starts are ordered bars < arrows < note < swoosh < caption',
        () {
      expect(cBarsStart, lessThan(cArrowsStart));
      expect(cArrowsStart, lessThan(cNoteStart));
      expect(cNoteStart, lessThan(cSwooshStart));
      expect(cSwooshStart, lessThan(cCaptionStart));
      expect(cCaptionEnd, 1.0);
    });

    test('bar stagger offsets are b1 0, b2 .07, b3 .13 within 0–0.33', () {
      expect(cBarOffsets, [0.0, 0.07, 0.13]);
      expect(cBarsStart, 0.0);
      expect(cBarsEnd, 0.33);
      // Only the trailing bar finishes at the window end; the lead bars
      // finish sooner (each window is [offset, offset + duration]).
      expect(cBarOffsets[2] + cBarDuration, closeTo(cBarsEnd, 1e-9));
      expect(cBarOffsets[0] + cBarDuration, lessThan(cBarsEnd));
      expect(cBarOffsets[1] + cBarDuration, lessThan(cBarsEnd));
      // Mid-window the lead bar is ahead of the trailing ones.
      expect(cBarProgress(0.0, 0), 0.0);
      expect(cBarProgress(0.1, 0), greaterThan(cBarProgress(0.1, 1)));
      expect(cBarProgress(0.1, 1), greaterThan(cBarProgress(0.1, 2)));
      for (var i = 0; i < 3; i++) {
        expect(cBarProgress(0.34, i), 1.0);
      }
    });

    test('reduced-motion path waits 300ms before finishing', () {
      expect(cReducedDelayMs, 300);
    });
  });

  group('SplashScreen widget', () {
    testWidgets('plays the C sting then calls onDone exactly once',
        (tester) async {
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(home: SplashScreen(onDone: () => done++)),
      );
      expect(find.byType(NotesMark), findsOneWidget);
      expect(find.text('NEB:EXPENSE TRACKER'), findsOneWidget);
      expect(done, 0);
      // One zero-time frame first so the ticker starts before the time
      // jump; one trailing frame after, because the completed status (and
      // thus onDone) fires on the frame after the value reaches 1.0.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(done, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(done, 1);
    });

    testWidgets('reduced motion shows the static mark and finishes in 300ms',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(home: SplashScreen(onDone: () => done++)),
      );
      expect(find.byType(NotesMark), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(done, 1);
    });
  });

  group('appVersion', () {
    test('matches V.MAJOR.MINOR.PATCH display format', () {
      expect(appVersion, matches(RegExp(r'^V\.\d+\.\d+\.\d+$')));
    });
  });
}

/// Add / Subtract / Edit sheet validation rules (pure).
///
/// Note is OPTIONAL (owner order): the field stays and persists, but it
/// never blocks Save and never shows an inline error.
library;

import 'package:finance_tracker/features/add_edit/txn_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canSaveTxn', () {
    test('a fully filled draft saves', () {
      expect(
        canSaveTxn(amountPaise: 1000, fromFor: 'Chai', note: 'Morning chai'),
        isTrue,
      );
    });

    test('a blank note does NOT block the save (note is optional)', () {
      expect(
        canSaveTxn(amountPaise: 1000, fromFor: 'Chai', note: ''),
        isTrue,
      );
      // Whitespace-only is still fine.
      expect(
        canSaveTxn(amountPaise: 1000, fromFor: 'Chai', note: '   '),
        isTrue,
      );
    });

    test('note defaults to empty when omitted', () {
      expect(
        canSaveTxn(amountPaise: 1000, fromFor: 'Chai'),
        isTrue,
      );
    });

    test('blank from/for blocks the save', () {
      expect(
        canSaveTxn(amountPaise: 1000, fromFor: '', note: 'ok'),
        isFalse,
      );
      expect(
        canSaveTxn(amountPaise: 1000, fromFor: '  ', note: 'ok'),
        isFalse,
      );
    });

    test('invalid or missing amount blocks the save', () {
      expect(canSaveTxn(amountPaise: null, fromFor: 'Chai', note: 'ok'), isFalse);
      expect(canSaveTxn(amountPaise: 0, fromFor: 'Chai', note: 'ok'), isFalse);
      expect(canSaveTxn(amountPaise: -1, fromFor: 'Chai', note: 'ok'), isFalse);
    });

    test('accepts surrounding whitespace on from/for and note', () {
      expect(
        canSaveTxn(amountPaise: 500, fromFor: '  Petrol  ', note: '  fill  '),
        isTrue,
      );
    });
  });

  group('txnNoteError', () {
    test('never errors: filled, blank, or untouched (note optional)', () {
      expect(
        txnNoteError(rawNote: 'Lunch', typedAnythingElse: true, saveAttempted: true),
        isNull,
      );
      expect(
        txnNoteError(
          rawNote: '',
          typedAnythingElse: false,
          saveAttempted: false,
        ),
        isNull,
      );
      expect(
        txnNoteError(
          rawNote: '',
          typedAnythingElse: true,
          saveAttempted: false,
        ),
        isNull,
      );
      expect(
        txnNoteError(
          rawNote: '',
          typedAnythingElse: false,
          saveAttempted: true,
        ),
        isNull,
      );
      expect(
        txnNoteError(
          rawNote: '   ',
          typedAnythingElse: false,
          saveAttempted: false,
        ),
        isNull,
      );
    });

    test('label marks the field optional', () {
      expect(noteLabel, 'Note (optional)');
    });
  });

  group('sheetEngaged', () {
    test('false until the amount or from/for field has content', () {
      expect(
        sheetEngaged(rawAmount: '', rawFromFor: ''),
        isFalse,
      );
      expect(
        sheetEngaged(rawAmount: '  ', rawFromFor: ''),
        isFalse,
      );
    });

    test('true once either other field has content', () {
      expect(sheetEngaged(rawAmount: '10', rawFromFor: ''), isTrue);
      expect(sheetEngaged(rawAmount: '', rawFromFor: 'Chai'), isTrue);
    });
  });
}

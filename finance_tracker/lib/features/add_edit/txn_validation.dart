/// Pure validation for the Add / Subtract / Edit sheet (Design.md §3.3).
///
/// Note is OPTIONAL (owner order): the field stays visible and persists, but
/// it never blocks Save and never shows an inline error.
library;

/// Kept for API compatibility; the sheet no longer shows a note error.
const String noteRequiredMessage = 'Note is required';

/// Label hint marking the note as optional.
const String noteLabel = 'Note (optional)';

/// Save gate for a txn draft. Amount must parse to >0 paise and from/for
/// must be non-blank after trimming. [note] is accepted for call-site
/// compatibility but never blocks the save.
bool canSaveTxn({
  required int? amountPaise,
  required String fromFor,
  String note = '',
}) =>
    amountPaise != null && amountPaise > 0 && fromFor.trim().isNotEmpty;

/// Inline note error — always null: the note is optional and never nags.
/// Kept (same signature) so existing call sites keep compiling.
String? txnNoteError({
  required String rawNote,
  required bool typedAnythingElse,
  required bool saveAttempted,
}) {
  return null;
}

/// True once the owner has interacted with any other field in the sheet.
bool sheetEngaged({
  required String rawAmount,
  required String rawFromFor,
}) =>
    rawAmount.trim().isNotEmpty || rawFromFor.trim().isNotEmpty;

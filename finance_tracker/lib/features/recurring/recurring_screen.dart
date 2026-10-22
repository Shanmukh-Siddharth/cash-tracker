/// Monthly items screen (Phase 8): user-triggered recurring templates.
///
/// Settings → Monthly items. Templates are inert until the user taps [+ Add]
/// (one row) or "Add all due" (every template with last_added_at older than
/// 30 days, or never). Each add creates a REAL txn through [TxnRepo] — same
/// validation incl. overspend (error snackbar, nothing added) — then stamps
/// last_added_at, refreshes, and shows a success snackbar. NO auto-scheduler.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models/recurring_template.dart';
import '../../data/models/transaction.dart';
import '../../data/models/wallet.dart';
import '../../data/repos/recurring_repo.dart';
import '../../data/repos/txn_repo.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';

class MonthlyItemsScreen extends ConsumerStatefulWidget {
  const MonthlyItemsScreen({super.key});

  @override
  ConsumerState<MonthlyItemsScreen> createState() => _MonthlyItemsState();
}

class _MonthlyItemsState extends ConsumerState<MonthlyItemsScreen> {
  bool _busy = false;

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Materializes one template into a real txn. Returns true on success.
  /// Overspend → error snackbar, nothing added, last_added_at untouched.
  /// The note is auto-filled as `Monthly: name` so it always satisfies the
  /// mandatory-note rule without prompting the owner (choice 2026-10-08).
  Future<bool> _addOne(RecurringTemplate t) async {
    try {
      final repo = await ref.read(txnRepoProvider.future);
      final note = recurringTxnNote(t.name);
      if (t.type == TxnType.income) {
        await repo.addIncome(
          walletId: t.walletId,
          amountPaise: t.amountPaise,
          fromFor: t.name,
          note: note,
        );
      } else {
        await repo.addExpense(
          walletId: t.walletId,
          amountPaise: t.amountPaise,
          fromFor: t.name,
          note: note,
        );
      }
      final recurring = await ref.read(recurringRepoProvider.future);
      await recurring.markAdded(t.id!);
      return true;
    } on InsufficientBalance catch (e) {
      if (mounted) _snack(e.toString(), error: true);
      return false;
    } catch (_) {
      if (mounted) _snack('Could not add "${t.name}"', error: true);
      return false;
    }
  }

  Future<void> _addSingle(RecurringTemplate t) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _addOne(t);
      if (!mounted) return;
      refreshAfterMutation(ref);
      if (ok) _snack('Added "${t.name}"');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAllDue(List<RecurringTemplate> templates) async {
    if (_busy) return;
    final due = templates.where((t) => t.isDue).toList();
    if (due.isEmpty) {
      _snack('Nothing due — all added within 30 days');
      return;
    }
    setState(() => _busy = true);
    var added = 0;
    var skipped = 0;
    try {
      for (final t in due) {
        if (await _addOne(t)) {
          added++;
        } else {
          skipped++;
        }
      }
      if (!mounted) return;
      refreshAfterMutation(ref);
      _snack(
        skipped == 0
            ? '$added added'
            : '$added added, $skipped skipped (low balance)',
        error: skipped > 0 && added == 0,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(RecurringTemplate t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text(
          '"${t.name}" · ${formatPaise(t.amountPaise)}\n'
          'Past transactions stay untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.inkOnPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = await ref.read(recurringRepoProvider.future);
    await repo.deleteTemplate(t.id!);
    if (!mounted) return;
    refreshAfterMutation(ref);
    _snack('Template deleted');
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly items')),
      body: templates.when(
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.event_repeat_outlined,
              title: 'No monthly items yet',
              subtitle: 'Add rent, salary or subscriptions you repeat by hand.',
            );
          }
          final dueCount = list.where((t) => t.isDue).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.inkOnPrimary,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _busy ? null : () => _addAllDue(list),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_outlined),
                    label: Text(
                      'Add all due${dueCount > 0 ? ' ($dueCount)' : ''}',
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _row(list[i]),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text(
            'Could not load templates',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.inkOnPrimary,
        onPressed: _busy
            ? null
            : () async {
                final saved = await showTemplateSheet(context);
                if (saved && mounted) refreshAfterMutation(ref);
              },
        icon: const Icon(Icons.add),
        label: const Text('Template'),
      ),
    );
  }

  Widget _row(RecurringTemplate t) {
    final isIncome = t.type == TxnType.income;
    final tint = isIncome ? AppColors.primary : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                isIncome ? '+' : '−',
                style: TextStyle(
                  color: tint,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  style: const TextStyle(fontSize: 14, color: AppColors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      t.walletName ?? '',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text3,
                      ),
                    ),
                    const Text(
                      ' · ',
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                    Text(
                      t.lastAddedAt == null
                          ? 'never added'
                          : 'added ${_shortDate(t.lastAddedAt!)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(t.formatAmount, style: AppText.mono(13, color: tint)),
          IconButton(
            tooltip: 'Add now',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => _addSingle(t),
            icon: const Icon(
              Icons.add_circle_outline,
              size: 22,
              color: AppColors.primary,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              if (v == 'edit') {
                final saved = await showTemplateSheet(
                  context,
                  existing: t,
                );
                if (saved && mounted) refreshAfterMutation(ref);
              } else if (v == 'delete') {
                await _confirmDelete(t);
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortDate(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    return '${parsed.day} ${_months[parsed.month]} ${parsed.year}';
  }

  static const _months = <String>[
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

extension on RecurringTemplate {
  String get formatAmount => formatPaise(amountPaise);
}

/// Opens the add/edit template sheet. Returns true when saved.
Future<bool> showTemplateSheet(
  BuildContext context, {
  RecurringTemplate? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    isDismissible: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _TemplateSheet(existing: existing),
    ),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Template saved'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
  return saved == true;
}

class _TemplateSheet extends ConsumerStatefulWidget {
  final RecurringTemplate? existing;
  const _TemplateSheet({this.existing});

  @override
  ConsumerState<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends ConsumerState<_TemplateSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late bool _isIncome;
  int? _walletId;
  bool _saving = false;
  String? _saveError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _amountCtrl = TextEditingController(
      text: e == null ? '' : _paiseToInput(e.amountPaise),
    );
    _isIncome = e == null ? false : e.type == TxnType.income;
    _walletId = e?.walletId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  static String _paiseToInput(int paise) {
    if (paise % 100 == 0) return '${paise ~/ 100}';
    return (paise / 100).toStringAsFixed(2);
  }

  Future<void> _save(int walletId) async {
    final name = _nameCtrl.text.trim();
    final amount = parseToPaise(_amountCtrl.text);
    if (name.isEmpty || amount == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final repo = await ref.read(recurringRepoProvider.future);
      if (_isEdit) {
        await repo.updateTemplate(
          id: widget.existing!.id!,
          name: name,
          amountPaise: amount,
          walletId: walletId,
          type: _isIncome ? TxnType.income : TxnType.expense,
        );
      } else {
        await repo.addTemplate(
          name: name,
          amountPaise: amount,
          walletId: walletId,
          type: _isIncome ? TxnType.income : TxnType.expense,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Something went wrong, try again';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletsAsync = ref.watch(walletsProvider);
    return walletsAsync.when(
      data: (wallets) {
        if (wallets.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Text(
              'No wallets found. Restart the app to reseed.',
              style: TextStyle(color: AppColors.danger),
            ),
          );
        }
        return _form(wallets);
      },
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Text(
          'Could not load wallets',
          style: TextStyle(color: AppColors.danger),
        ),
      ),
    );
  }

  Widget _form(List<Wallet> wallets) {
    final walletId = _walletId != null &&
            wallets.any((w) => w.id == _walletId)
        ? _walletId!
        : wallets.first.id!;
    final name = _nameCtrl.text.trim();
    final amount = parseToPaise(_amountCtrl.text);
    final String? amountError = _amountCtrl.text.trim().isEmpty
        ? null
        : (amount == null ? 'Enter an amount greater than zero' : null);
    final String? nameError =
        _nameCtrl.text.isNotEmpty && name.isEmpty ? 'Required' : null;
    final valid = name.isNotEmpty && amount != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isEdit ? 'Edit template' : 'New monthly item',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                color: AppColors.text2,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: false, label: Text('Expense')),
              ButtonSegment<bool>(value: true, label: Text('Income')),
            ],
            selected: <bool>{_isIncome},
            onSelectionChanged: (set) =>
                setState(() => _isIncome = set.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.2),
              selectedForegroundColor: AppColors.text,
              foregroundColor: AppColors.text2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Name (required)',
              hintText: 'e.g. Rent, Salary',
              errorText: nameError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: AppText.mono(24),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: AppText.mono(24, color: AppColors.text3),
              hintText: '0.00',
              hintStyle: AppText.mono(24, color: AppColors.text3),
              errorText: amountError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [
              for (final w in wallets)
                ButtonSegment<int>(value: w.id!, label: Text(w.name)),
            ],
            selected: <int>{walletId},
            onSelectionChanged: (set) =>
                setState(() => _walletId = set.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.2),
              selectedForegroundColor: AppColors.text,
              foregroundColor: AppColors.text2,
            ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 8),
            Text(
              _saveError!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.danger,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.inkOnPrimary,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              onPressed: valid && !_saving ? () => _save(walletId) : null,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Save changes' : 'Add template'),
            ),
          ),
        ],
      ),
    );
  }
}

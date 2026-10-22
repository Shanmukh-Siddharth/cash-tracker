/// Debt tab (track-only memo): owe/lent toggle, header totals, rows with
/// remaining/total, detail sheet (payments, record payment capped at
/// remaining, settle, delete), add sheet.
///
/// Debts NEVER touch wallet balances and create NO transactions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/repos/debt_repo.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';

class DebtScreen extends ConsumerStatefulWidget {
  const DebtScreen({super.key});

  @override
  ConsumerState<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends ConsumerState<DebtScreen> {
  /// true = "You owe" (direction owe), false = "Owed to you" (lent).
  bool _showOwe = true;

  /// Show settled rows too (dimmed).
  bool _showSettled = false;

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openAdd() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _AddDebtSheet(
          initialOwe: _showOwe,
          onAdded: (owe) {
            refreshAfterMutation(ref);
            if (mounted) setState(() => _showOwe = owe);
          },
        ),
      ),
    );
  }

  void _openDetail(Debt debt) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DebtDetailSheet(
        debtId: debt.id!,
        onChanged: () => refreshAfterMutation(ref),
        onSnack: _snack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debtsAsync = ref.watch(debtsProvider);
    final totalsAsync = ref.watch(debtTotalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Debts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: totalsAsync.maybeWhen(
              data: (t) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  'You owe ${formatPaise(t.oweTotal)} · '
                  'Owed to you ${formatPaise(t.lentTotal)}',
                  style: AppText.mono(15),
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('You owe', style: TextStyle(fontSize: 13)),
                        icon: Icon(Icons.arrow_upward_outlined, size: 16),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label:
                            Text('Owed to you', style: TextStyle(fontSize: 13)),
                        icon: Icon(Icons.arrow_downward_outlined, size: 16),
                      ),
                    ],
                    selected: <bool>{_showOwe},
                    onSelectionChanged: (s) =>
                        setState(() => _showOwe = s.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.2),
                      selectedForegroundColor: AppColors.text,
                      foregroundColor: AppColors.text2,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Show settled',
                  child: FilterChip(
                    label: const Text('Settled', style: TextStyle(fontSize: 12)),
                    selected: _showSettled,
                    onSelected: (v) => setState(() => _showSettled = v),
                    selectedColor:
                        AppColors.primary.withValues(alpha: 0.25),
                    showCheckmark: false,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: debtsAsync.when(
              data: (debts) => _body(debts),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Text(
                  'Could not load debts',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        // Lifted clear of the floating pill nav (~96px) so it never hides
        // behind it (same as the cart [+]).
        padding: const EdgeInsets.only(bottom: 96),
        child: FloatingActionButton(
          heroTag: 'debt_add',
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.inkOnPrimary,
          tooltip: 'New debt',
          onPressed: _openAdd,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _body(List<Debt> debts) {
    final dir = _showOwe ? 'owe' : 'lent';
    final rows = debts
        .where((d) => d.direction == dir)
        .where((d) => _showSettled ? true : d.isOpen)
        .toList();
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.handshake_outlined,
        title: _showOwe ? 'Nothing you owe' : 'Nothing owed to you',
        subtitle: _showSettled
            ? 'Tap + to add a debt note.'
            : 'Tap + to add a debt note. Settled ones hide here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 180),
      children: [
        for (final d in rows) _DebtRow(debt: d, onTap: () => _openDetail(d)),
        // Clearance so the last row scrolls above the floating pill nav.
        const SizedBox(height: 84),
      ],
    );
  }
}

class _DebtRow extends StatelessWidget {
  final Debt debt;
  final VoidCallback onTap;
  const _DebtRow({required this.debt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final settled = !debt.isOpen;
    final date = DateTime.tryParse(debt.date);
    final dateShown =
        date == null ? debt.date : DateFormat('yyyy-MM-dd').format(date);
    return Opacity(
      opacity: settled ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: ListTile(
          onTap: onTap,
          title: Text(
            debt.person,
            style: const TextStyle(fontSize: 14, color: AppColors.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '$dateShown${settled ? ' · settled' : ''}'
            '${debt.note?.isNotEmpty ?? false ? ' · ${debt.note}' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.text2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            '${formatPaise(debt.remainingPaise)} / ${formatPaise(debt.amountPaise)}',
            style: AppText.mono(
              13,
              color: settled ? AppColors.text3 : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Detail sheet: payments list, record-payment (capped), settle, delete.
class _DebtDetailSheet extends ConsumerStatefulWidget {
  final int debtId;
  final VoidCallback onChanged;
  final void Function(String msg, {bool error}) onSnack;
  const _DebtDetailSheet({
    required this.debtId,
    required this.onChanged,
    required this.onSnack,
  });

  @override
  ConsumerState<_DebtDetailSheet> createState() => _DebtDetailSheetState();
}

class _DebtDetailSheetState extends ConsumerState<_DebtDetailSheet> {
  final _payCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _payCtrl.dispose();
    super.dispose();
  }

  Future<void> _record(Debt debt) async {
    final amount = parseToPaise(_payCtrl.text);
    if (amount == null) {
      widget.onSnack('Enter an amount greater than zero', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = await ref.read(debtRepoProvider.future);
      await repo.addPayment(debtId: debt.id!, amountPaise: amount);
      _payCtrl.clear();
      widget.onChanged();
      if (mounted) setState(() {});
    } on DebtOverpay catch (e) {
      if (mounted) {
        widget.onSnack(
          'Overpay — remaining is ${formatPaise(e.remaining)}',
          error: true,
        );
      }
    } catch (_) {
      if (mounted) widget.onSnack('Could not record payment', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _settle(Debt debt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle debt?'),
        content: Text(
          'Mark "${debt.person}" settled? '
          'Remaining ${formatPaise(debt.remainingPaise)} is forgiven.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = await ref.read(debtRepoProvider.future);
      await repo.settle(debt.id!);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) widget.onSnack('Could not settle', error: true);
    }
  }

  Future<void> _delete(Debt debt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete debt?'),
        content: Text(
          'Removes "${debt.person}" and its payments. '
          'Balances are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = await ref.read(debtRepoProvider.future);
      await repo.deleteDebt(debt.id!);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) widget.onSnack('Could not delete', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debtsAsync = ref.watch(debtsProvider);
    return debtsAsync.maybeWhen(
      data: (debts) {
        Debt? debt;
        for (final d in debts) {
          if (d.id == widget.debtId) debt = d;
        }
        if (debt == null) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Text('Debt no longer exists'),
          );
        }
        final current = debt;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                current.person,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Remaining ${formatPaise(current.remainingPaise)} '
                'of ${formatPaise(current.amountPaise)}'
                '${current.isOpen ? '' : ' · settled'}',
                style: AppText.mono(14, color: AppColors.text2),
              ),
              const SizedBox(height: 12),
              const Text('PAYMENTS', style: AppText.eyebrow),
              const SizedBox(height: 6),
              _PaymentsList(debtId: current.id!),
              const SizedBox(height: 12),
              if (current.isOpen) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _payCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: AppText.mono(18),
                        decoration: InputDecoration(
                          prefixText: '₹ ',
                          hintText: '0.00',
                          helperText:
                              'Max ${formatPaise(current.remainingPaise)}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.inkOnPrimary,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _saving ? null : () => _record(current),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('+ Record payment'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _settle(current),
                        child: const Text('Settle'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        onPressed: () => _delete(current),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: () => _delete(current),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        );
      },
      orElse: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _PaymentsList extends ConsumerWidget {
  final int debtId;
  const _PaymentsList({required this.debtId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref
          .watch(debtRepoProvider.future)
          .then((r) => r.paymentsFor(debtId)),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final payments = snap.data ?? const <DebtPayment>[];
        if (payments.isEmpty) {
          return const Text(
            'No payments yet.',
            style: TextStyle(fontSize: 13, color: AppColors.text3),
          );
        }
        return Column(
          children: [
            for (final p in payments)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.note?.isNotEmpty ?? false
                            ? p.note!
                            : DateFormat('yyyy-MM-dd').format(
                                DateTime.tryParse(p.date) ?? DateTime.now(),
                              ),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatPaise(p.amountPaise),
                      style: AppText.mono(13),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Add sheet: person required, amount > 0, owe/lent toggle, note optional.
class _AddDebtSheet extends StatefulWidget {
  final bool initialOwe;
  final void Function(bool owe) onAdded;
  const _AddDebtSheet({required this.initialOwe, required this.onAdded});

  @override
  State<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends State<_AddDebtSheet> {
  final _personCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late bool _owe;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _owe = widget.initialOwe;
  }

  @override
  void dispose() {
    _personCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseToPaise(_amountCtrl.text);
    final valid = _personCtrl.text.trim().isNotEmpty && amount != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'New debt',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: true,
                label: Text('I owe them'),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text('They owe me'),
              ),
            ],
            selected: <bool>{_owe},
            onSelectionChanged: (s) => setState(() => _owe = s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.2),
              selectedForegroundColor: AppColors.text,
              foregroundColor: AppColors.text2,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Person', style: _LabelStyle()),
          const SizedBox(height: 6),
          TextField(
            controller: _personCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. Rahul',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          const Text('Amount', style: _LabelStyle()),
          const SizedBox(height: 6),
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: AppText.mono(24),
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: '0.00',
              errorText: _amountCtrl.text.trim().isEmpty || amount != null
                  ? null
                  : 'Enter an amount greater than zero',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          const Text('Note (optional)', style: _LabelStyle()),
          const SizedBox(height: 6),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              hintText: 'e.g. Lunch split',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Memo only — wallets and transactions are never touched.',
            style: TextStyle(fontSize: 11, color: AppColors.text3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
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
              onPressed: valid && !_saving
                  ? () async {
                      setState(() => _saving = true);
                      try {
                        final container =
                            ProviderScope.containerOf(context);
                        final repo =
                            await container.read(debtRepoProvider.future);
                        await repo.addDebt(
                          person: _personCtrl.text,
                          amountPaise: amount,
                          direction: _owe ? 'owe' : 'lent',
                          note: _noteCtrl.text.trim().isEmpty
                              ? null
                              : _noteCtrl.text,
                        );
                        widget.onAdded(_owe);
                        if (context.mounted) Navigator.of(context).pop();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not add debt'),
                              backgroundColor: AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    }
                  : null,
              child: const Text('Add debt'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelStyle extends TextStyle {
  const _LabelStyle()
      : super(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppColors.text2,
        );
}

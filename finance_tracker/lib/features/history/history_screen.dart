/// History tab: search, type/wallet filters, day-grouped list, tap-to-edit,
/// swipe-or-icon delete with confirm (balance reverts via repo).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models/transaction.dart';
import '../../data/models/wallet.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';
import '../add_edit/add_sheet.dart';
import 'grouping.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchCtrl = TextEditingController();
  TxnFilter _type = TxnFilter.all;
  int? _walletId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(Txn txn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          '${txn.fromFor} · ${formatPaise(txn.amountPaise)}\n'
          'The wallet balance will be reverted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.inkOnPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = await ref.read(txnRepoProvider.future);
    await repo.deleteTxn(txn.id!);
    if (!mounted) return;
    refreshAfterMutation(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deleted'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final wallets = ref.watch(walletsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Text(
              'History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _searchCtrl.clear()),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            _filterRow(wallets),
            const SizedBox(height: 4),
            Expanded(
              child: history.when(
                data: (txns) => _list(context, txns),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (_, _) => const Center(
                  child: Text(
                    'Could not load history',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterRow(AsyncValue<List<Wallet>> wallets) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _chip('All', _type == TxnFilter.all, () {
            setState(() => _type = TxnFilter.all);
          }),
          const SizedBox(width: 8),
          _chip('In', _type == TxnFilter.income, () {
            setState(() => _type = TxnFilter.income);
          }),
          const SizedBox(width: 8),
          _chip('Out', _type == TxnFilter.expense, () {
            setState(() => _type = TxnFilter.expense);
          }),
          ...wallets.when(
            data: (list) => [
              const SizedBox(width: 8),
              _chip('All wallets', _walletId == null, () {
                setState(() => _walletId = null);
              }),
              for (final w in list) ...[
                const SizedBox(width: 8),
                _chip(w.name, _walletId == w.id, () {
                  setState(() => _walletId = w.id);
                }),
              ],
            ],
            loading: () => const <Widget>[],
            error: (_, _) => const <Widget>[],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.22),
      labelStyle: TextStyle(
        color: selected ? AppColors.text : AppColors.text2,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: AppColors.line),
    );
  }

  Widget _list(BuildContext context, List<Txn> txns) {
    if (txns.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions yet',
        subtitle: 'Tap + Add or − Subtract to record money in or out.',
      );
    }
    final filtered = filterTxns(
      txns,
      type: _type,
      walletId: _walletId,
      query: _searchCtrl.text,
    );
    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_outlined,
        title: 'No matches',
        subtitle: 'Try a different search or filter.',
      );
    }
    final groups = groupByDay(filtered);
    return RefreshIndicator(
      onRefresh: () async {
        refreshAfterMutation(ref);
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: groups.fold<int>(0, (n, g) => n + 1 + g.txns.length),
        itemBuilder: (context, index) {
          var remaining = index;
          for (final group in groups) {
            if (remaining == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  group.header,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text3,
                  ),
                ),
              );
            }
            remaining -= 1;
            if (remaining < group.txns.length) {
              return _row(context, group.txns[remaining]);
            }
            remaining -= group.txns.length;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _row(BuildContext context, Txn txn) {
    final isIncome = txn.type == TxnType.income;
    final tint = isIncome ? AppColors.primary : AppColors.danger;
    final sign = isIncome ? '+' : '−';
    return Dismissible(
      key: ValueKey<int>(txn.id!),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      confirmDismiss: (_) async {
        await _confirmDelete(txn);
        return false; // provider refresh rebuilds the list instead
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showTxnSheet(
          context,
          mode: SheetMode.edit,
          existing: txn,
        ),
        child: Container(
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
                    sign,
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
                      txn.fromFor,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            txn.category,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          txn.walletName ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.text3,
                          ),
                        ),
                        if (txn.note != null && txn.note!.isNotEmpty) ...[
                          const Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.text3,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              txn.note!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.text3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${formatPaise(txn.amountPaise)}',
                style: AppText.mono(13, color: tint),
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.text3,
                ),
                onPressed: () => _confirmDelete(txn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

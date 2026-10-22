/// Home tab: total hero card, wallet chips, Add/Subtract pills, and the 10
/// most recent transactions from the DB. Tapping recent jumps to History.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models/transaction.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';
import '../add_edit/add_sheet.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  /// Called when the user taps the recent list (jumps to the History tab).
  final VoidCallback? onOpenHistory;

  const HomeScreen({super.key, this.onOpenHistory});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _hideAmounts = false;

  String _amount(int paise) => _hideAmounts ? '₹ ••••••' : formatPaise(paise);

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(totalProvider);
    final wallets = ref.watch(walletsProvider);
    final recent = ref.watch(recentProvider);
    final today = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NEB'),
        actions: [
          IconButton(
            tooltip: _hideAmounts ? 'Show balances' : 'Hide balances',
            icon: Icon(
              _hideAmounts
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () =>
                setState(() => _hideAmounts = !_hideAmounts),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        // 96px bottom clearance so the last recent row scrolls above the
        // floating pill nav.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // Hero total card.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL BALANCE', style: AppText.eyebrow),
                const SizedBox(height: 4),
                total.when(
                  data: (value) => Text(
                    _amount(value),
                    style: AppText.mono(34),
                  ),
                  loading: () => Text('…', style: AppText.mono(34)),
                  error: (_, _) => const Text(
                    'Unavailable',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
                const SizedBox(height: 4),
                today.when(
                  data: (t) => Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text2,
                      ),
                      children: [
                        TextSpan(
                          text: '↑ ${_amount(t.incomePaise)} in',
                          style: const TextStyle(color: AppColors.primary),
                        ),
                        TextSpan(
                          text:
                              ' · ↓ ${_amount(t.expensePaise)} out today',
                        ),
                      ],
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                wallets.when(
                  data: (list) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in list)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Text(
                            '${w.name} ${_amount(w.balancePaise)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.text2,
                            ),
                          ),
                        ),
                    ],
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const Text(
                    'Wallets unavailable',
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Quick actions (real sheets land in Phase 2).
          Row(
            children: [
              Expanded(
                child: _PillButton(
                  label: '+ Add',
                  filled: true,
                  onTap: () => showTxnSheet(
                    context,
                    mode: SheetMode.addIncome,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PillButton(
                  label: '− Subtract',
                  filled: false,
                  onTap: () => showTxnSheet(
                    context,
                    mode: SheetMode.addExpense,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              TextButton(
                onPressed: widget.onOpenHistory,
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          recent.when(
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.add_card_outlined,
                  title: 'Add your first entry',
                  subtitle:
                      'Tap + Add or − Subtract to record money in or out.',
                );
              }
              return Column(
                children: [
                  for (final txn in list)
                    _RecentRow(
                      txn: txn,
                      onTap: widget.onOpenHistory,
                    ),
                ],
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => const Text(
              'Could not load transactions',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: filled
          ? FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.inkOnPrimary,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              onPressed: onTap,
              child: Text(label),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              onPressed: onTap,
              child: Text(label),
            ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final Txn txn;
  final VoidCallback? onTap;
  const _RecentRow({required this.txn, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIncome = txn.type == TxnType.income;
    final tint = isIncome ? AppColors.primary : AppColors.danger;
    final sign = isIncome ? '+' : '−';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
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
                Text(
                  txn.walletName ?? '',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$sign${formatPaise(txn.amountPaise)}',
            style: AppText.mono(13, color: tint),
          ),
        ],
      ),
      ),
    );
  }
}

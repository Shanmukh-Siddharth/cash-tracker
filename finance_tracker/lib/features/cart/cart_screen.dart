/// Cart tab (Phase 3): wishlist rows with qty steppers, swipe-to-remove,
/// clear-all, sticky preview bar (Total + wallet selector + Current balance
/// + If-bought pill) and a single-transaction [Buy All].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/wallet.dart';
import '../../data/repos/txn_repo.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';
import '../add_edit/last_wallet_store.dart';
import 'cart_math.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  int? _walletId;
  int? _lastUsedId;
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    LastWalletStore.load().then((store) {
      if (mounted) setState(() => _lastUsedId = store.read());
    });
  }

  int? _selectedWalletId(List<Wallet> wallets) {
    if (_walletId != null && wallets.any((w) => w.id == _walletId)) {
      return _walletId;
    }
    return resolveDefaultWallet(
      wallets.map((w) => (id: w.id!)).toList(),
      _lastUsedId,
    );
  }

  Future<void> _buyAll(int walletId, int total) async {
    setState(() => _buying = true);
    try {
      final repo = await ref.read(cartRepoProvider.future);
      await repo.buyAll(walletId: walletId);
      final store = await LastWalletStore.load();
      await store.write(walletId);
      if (!mounted) return;
      refreshAfterMutation(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bought for ${formatPaise(total)}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } on InsufficientBalance catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong, try again'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('Removes every item. Balances are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = await ref.read(cartRepoProvider.future);
    await repo.clear();
    refreshAfterMutation(ref);
  }

  void _openAddItem() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      isDismissible: true,
      builder: (sheetContext) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _AddItemSheet(
          onAdded: () => refreshAfterMutation(ref),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(cartItemsProvider);
    final walletsAsync = ref.watch(walletsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart'),
        actions: [
          TextButton(onPressed: _clearAll, child: const Text('Clear all')),
        ],
      ),
      body: itemsAsync.when(
        data: (items) => walletsAsync.when(
          data: (wallets) => _body(context, items, wallets),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(
            child: Text('Could not load wallets',
                style: TextStyle(color: AppColors.danger)),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Could not load cart',
              style: TextStyle(color: AppColors.danger)),
        ),
      ),
      floatingActionButton: Padding(
        // Lifted clear of the floating pill nav (~96px) so it never hides
        // behind it.
        padding: const EdgeInsets.only(bottom: 96),
        child: FloatingActionButton(
          heroTag: 'cart_add',
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.inkOnPrimary,
          tooltip: 'Add item',
          onPressed: _openAddItem,
          child: const Icon(Icons.add),
        ),
      ),
      bottomNavigationBar: itemsAsync.maybeWhen(
        data: (items) => walletsAsync.maybeWhen(
          data: (wallets) => _PreviewBar(
            items: items,
            wallets: wallets,
            walletId: _selectedWalletId(wallets),
            buying: _buying,
            onWalletChanged: (id) => setState(() => _walletId = id),
            onBuy: _buyAll,
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<CartItem> items,
    List<Wallet> wallets,
  ) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.shopping_cart_outlined,
        title: 'Cart is empty',
        subtitle: 'Tap + to add something you plan to buy.',
      );
    }
    final total = cartTotal(items);
    final walletId = _selectedWalletId(wallets);
    Wallet? wallet;
    for (final w in wallets) {
      if (w.id == walletId) wallet = w;
    }
    final balance = wallet?.balancePaise ?? 0;
    final after = ifBought(balance, total);
    final safe = after >= 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
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
              const Text('TOTAL', style: AppText.eyebrow),
              const SizedBox(height: 4),
              Text(formatPaise(total), style: AppText.mono(30)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${wallet?.name ?? '—'} ${formatPaise(balance)} →',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.text2),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: (safe ? AppColors.primary : AppColors.danger)
                          .withValues(alpha: 0.15),
                      border: Border.all(
                        color: safe ? AppColors.primary : AppColors.danger,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!safe)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.warning_amber_rounded,
                                size: 14, color: AppColors.danger),
                          ),
                        Text(
                          'If-bought ${formatPaise(after)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                            color: safe
                                ? AppColors.primary
                                : AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items) _ItemRow(item: item),
        // Clearance so the last row scrolls above the floating pill nav.
        const SizedBox(height: 84),
      ],
    );
  }
}

class _ItemRow extends ConsumerWidget {
  final CartItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('cart_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      onDismissed: (_) async {
        final repo = await ref.read(cartRepoProvider.future);
        await repo.removeItem(item.id!);
        refreshAfterMutation(ref);
      },
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    formatPaise(item.pricePaise),
                    style: AppText.mono(12, color: AppColors.text2),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Decrease quantity',
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: const Icon(Icons.remove_circle_outline, size: 22),
              color: AppColors.text2,
              onPressed: item.qty <= 1
                  ? null
                  : () async {
                      final repo =
                          await ref.read(cartRepoProvider.future);
                      await repo.setQty(item.id!, item.qty - 1);
                      refreshAfterMutation(ref);
                    },
            ),
            Text('${item.qty}', style: AppText.mono(14)),
            IconButton(
              tooltip: 'Increase quantity',
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: const Icon(Icons.add_circle_outline, size: 22),
              color: AppColors.primary,
              onPressed: () async {
                final repo = await ref.read(cartRepoProvider.future);
                await repo.setQty(item.id!, item.qty + 1);
                refreshAfterMutation(ref);
              },
            ),
            const SizedBox(width: 4),
            Text(
              formatPaise(item.totalPaise),
              style: AppText.mono(13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sticky bottom preview bar: always visible. Total + wallet selector +
/// current balance + if-bought pill + Buy All.
class _PreviewBar extends StatelessWidget {
  final List<CartItem> items;
  final List<Wallet> wallets;
  final int? walletId;
  final bool buying;
  final ValueChanged<int> onWalletChanged;
  final Future<void> Function(int walletId, int total) onBuy;

  const _PreviewBar({
    required this.items,
    required this.wallets,
    required this.walletId,
    required this.buying,
    required this.onWalletChanged,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty || wallets.isEmpty || walletId == null) {
      return const SizedBox.shrink();
    }
    final total = cartTotal(items);
    Wallet wallet = wallets.first;
    for (final w in wallets) {
      if (w.id == walletId) wallet = w;
    }
    final after = ifBought(wallet.balancePaise, total);
    final safe = after >= 0;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: [
                      for (final w in wallets)
                        ButtonSegment<int>(
                          value: w.id!,
                          label: Text(w.name,
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                    selected: <int>{wallet.id!},
                    onSelectionChanged: (set) =>
                        onWalletChanged(set.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.2),
                      selectedForegroundColor: AppColors.text,
                      foregroundColor: AppColors.text2,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total ${formatPaise(total)}',
                        style: AppText.mono(15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Current ${formatPaise(wallet.balancePaise)} · '
                        'If-bought ${formatPaise(after)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                          color: safe
                              ? AppColors.primary
                              : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.inkOnPrimary,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    onPressed: !safe || buying
                        ? null
                        : () => onBuy(wallet.id!, total),
                    child: buying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Buy All • ${formatPaise(total)}'),
                  ),
                ),
              ],
            ),
            if (!safe)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Not enough in ${wallet.name}. '
                  'Available: ${formatPaise(wallet.balancePaise)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddItemSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddItemSheet({required this.onAdded});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  int _qty = 1;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = parseToPaise(_priceCtrl.text);
    final valid = _nameCtrl.text.trim().isNotEmpty && price != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Add item',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                color: AppColors.text2,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Name', style: _LabelStyle()),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'e.g. Headphones',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          const Text('Price', style: _LabelStyle()),
          const SizedBox(height: 6),
          TextField(
            controller: _priceCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: AppText.mono(24),
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: '0.00',
              errorText: _priceCtrl.text.trim().isEmpty || price != null
                  ? null
                  : 'Enter an amount greater than zero',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Qty', style: _LabelStyle()),
              const Spacer(),
              IconButton(
                tooltip: 'Decrease quantity',
                onPressed: _qty <= 1
                    ? null
                    : () => setState(() => _qty--),
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.text2,
              ),
              Text('$_qty', style: AppText.mono(16)),
              IconButton(
                tooltip: 'Increase quantity',
                onPressed: () => setState(() => _qty++),
                icon: const Icon(Icons.add_circle_outline),
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.inkOnPrimary,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
              onPressed: valid && !_saving
                  ? () async {
                      setState(() => _saving = true);
                      final container = ProviderScope.containerOf(context);
                      final repo =
                          await container.read(cartRepoProvider.future);
                      await repo.addItem(
                        name: _nameCtrl.text,
                        pricePaise: price,
                        qty: _qty,
                      );
                      widget.onAdded();
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('Add to cart'),
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

/// Shared Add / Subtract / Edit bottom sheet (Phase 2).
///
/// - Add income: emerald Save. Add expense: rose/danger Save.
/// - Edit: prefilled amount/from-for/note/wallet; type + date fixed in v1.
/// - Wallet picker defaults to last-used wallet ([LastWalletStore]).
/// - ONE animation driver: the native [showModalBottomSheet] transition. The
///   old in-sheet [TweenAnimationBuilder] was deleted (it double-animated the
///   same properties and put an Opacity layer over the glass backdrop, which
///   forced extra compositing and read as "lagging").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/categories.dart';
import '../../data/models/transaction.dart';
import '../../data/models/wallet.dart';
import '../../data/repos/txn_repo.dart';
import '../../state/providers.dart';
import 'last_category_store.dart';
import 'last_wallet_store.dart';
import 'txn_validation.dart';

enum SheetMode { addIncome, addExpense, edit }

/// Sheet transition timing. Single driver, transform-only underneath.
const Duration kTxnSheetTransition = Duration(milliseconds: 250);

/// Material's standard emphasized-decelerate-ish curve: leaves fast, settles
/// without overshoot. Keeps the sheet feeling crisp instead of slow.
const Curve kTxnSheetCurve = Cubic(0.2, 0, 0, 1);

/// Opens the sheet. Returns true when a save happened (caller shows snackbar).
Future<bool> showTxnSheet(
  BuildContext context, {
  required SheetMode mode,
  Txn? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Own controller so the curve/duration are ours; still the only driver of
  // the sheet's motion (the sheet content itself never animates).
  //
  // The controller MUST outlive the pop: [Route.didPop] resolves the sheet
  // future at pop time, before the exit animation runs. Disposing here in a
  // `finally` would kill the custom transition mid-reverse (and drop the
  // route's own status listener), stranding the sheet on screen. It is
  // disposed on dismissal instead; the route's listener was registered
  // first (synchronously during push), so it finalizes before we dispose.
  final controller = AnimationController(
    vsync: Navigator.of(context),
    duration: kTxnSheetTransition,
    reverseDuration: const Duration(milliseconds: 200),
  );
  var controllerDisposed = false;
  void onSheetDismissed(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !controllerDisposed) {
      controllerDisposed = true;
      controller.removeStatusListener(onSheetDismissed);
      controller.dispose();
    }
  }

  void disposeController() {
    if (!controllerDisposed) {
      controllerDisposed = true;
      controller.removeStatusListener(onSheetDismissed);
      controller.dispose();
    }
  }

  late final Future<bool?> pushFuture;
  try {
    pushFuture = showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      backgroundColor: AppColors.surface2,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      transitionAnimationController: controller,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: TxnSheet(mode: mode, existing: existing),
      ),
    );
  } catch (_) {
    disposeController();
    rethrow;
  }
  controller.addStatusListener(onSheetDismissed);
  final saved = await pushFuture;
  if (saved == true) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Saved'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
  final result = saved == true;
  // No exit animation is running (route removed abruptly): no dismissed
  // event will arrive, so dispose now. Otherwise onSheetDismissed owns it.
  if (controller.status != AnimationStatus.reverse) disposeController();
  return result;
}

class TxnSheet extends ConsumerStatefulWidget {
  final SheetMode mode;
  final Txn? existing;

  const TxnSheet({super.key, required this.mode, this.existing});

  @override
  ConsumerState<TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends ConsumerState<TxnSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _fromForCtrl;
  late final TextEditingController _noteCtrl;
  int? _walletId;
  int? _lastUsedId;
  String? _category;
  bool _saving = false;
  String? _saveError;

  bool get _isEdit => widget.mode == SheetMode.edit;

  /// Effective type: fixed for edit, chosen for add.
  TxnType get _type {
    if (_isEdit) return widget.existing!.type;
    return widget.mode == SheetMode.addIncome
        ? TxnType.income
        : TxnType.expense;
  }

  bool get _isIncome => _type == TxnType.income;

  String get _title {
    if (_isEdit) return _isIncome ? 'Edit income' : 'Edit expense';
    return _isIncome ? 'Add money' : 'Subtract money';
  }

  String get _fromForLabel => _isIncome ? 'From whom' : 'For what';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amountCtrl = TextEditingController(
      text: existing == null ? '' : _paiseToInput(existing.amountPaise),
    );
    _fromForCtrl = TextEditingController(text: existing?.fromFor ?? '');
    _noteCtrl = TextEditingController(text: existing?.note ?? '');
    _walletId = existing?.walletId;
    LastWalletStore.load().then((store) {
      if (mounted) setState(() => _lastUsedId = store.read());
    });
    if (existing != null) {
      _category = existing.category;
    } else {
      // Default: last-used category for this type, else the list tail.
      _category = defaultCategory(_isIncome);
      LastCategoryStore.load().then((store) {
        if (!mounted) return;
        final last = store.read(_isIncome);
        final options = _isIncome ? incomeCategories : expenseCategories;
        if (last != null && options.contains(last)) {
          setState(() => _category = last);
        }
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _fromForCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  static String _paiseToInput(int paise) {
    if (paise % 100 == 0) return '${paise ~/ 100}';
    return (paise / 100).toStringAsFixed(2);
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

  /// Balance the new amount is checked against. For a same-wallet edit the
  /// repo reverts the old effect first, so credit it back here to match.
  int _effectiveAvailable(Wallet wallet) {
    final existing = widget.existing;
    if (_isEdit && existing != null && existing.walletId == wallet.id) {
      final revert =
          existing.type == TxnType.income ? -existing.amountPaise : existing.amountPaise;
      return wallet.balancePaise + revert;
    }
    return wallet.balancePaise;
  }

  Future<void> _save(int walletId) async {
    final amount = parseToPaise(_amountCtrl.text);
    final fromFor = _fromForCtrl.text.trim();
    final note = _noteCtrl.text.trim();
    // Note is optional: never blocks Save. Only amount/from-for gate.
    if (amount == null ||
        !canSaveTxn(amountPaise: amount, fromFor: fromFor, note: note)) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final repo = await ref.read(txnRepoProvider.future);
      final options = _isIncome ? incomeCategories : expenseCategories;
      final category = (_category != null && options.contains(_category))
          ? _category
          : defaultCategory(_isIncome);
      if (_isEdit) {
        await repo.editTxn(
          id: widget.existing!.id!,
          walletId: walletId,
          type: _type,
          amountPaise: amount,
          fromFor: fromFor,
          note: note,
          category: category,
        );
      } else if (_isIncome) {
        await repo.addIncome(
          walletId: walletId,
          amountPaise: amount,
          fromFor: fromFor,
          note: note,
          category: category,
        );
      } else {
        await repo.addExpense(
          walletId: walletId,
          amountPaise: amount,
          fromFor: fromFor,
          note: note,
          category: category,
        );
      }
      final store = await LastWalletStore.load();
      await store.write(walletId);
      final catStore = await LastCategoryStore.load();
      await catStore.write(_isIncome, category!);
      if (!mounted) return;
      refreshAfterMutation(ref);
      Navigator.of(context).pop(true);
    } on InsufficientBalance catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = e.toString();
        });
      }
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
        return _form(context, wallets);
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

  Widget _form(BuildContext context, List<Wallet> wallets) {
    final walletId = _selectedWalletId(wallets)!;
    final wallet = wallets.firstWhere((w) => w.id == walletId);

    final amount = parseToPaise(_amountCtrl.text);
    final fromFor = _fromForCtrl.text.trim();
    final note = _noteCtrl.text.trim();
    final String? amountError = _amountCtrl.text.trim().isEmpty
        ? null
        : (amount == null ? 'Enter an amount greater than zero' : null);
    final String? fromForError =
        _fromForCtrl.text.isNotEmpty && fromFor.isEmpty ? 'Required' : null;
    // Note is optional: no inline error, never gates Save.
    const String? noteError = null;
    String? balanceError;
    if (!_isIncome && amount != null) {
      final available = _effectiveAvailable(wallet);
      if (amount > available) {
        balanceError =
            'Not enough in ${wallet.name}. Available: ${formatPaise(available)}';
      }
    }
    final valid =
        canSaveTxn(amountPaise: amount, fromFor: fromFor, note: note) &&
        balanceError == null;
    final saveError = _saveError ?? balanceError;

    final saveBg = _isIncome ? AppColors.primary : AppColors.danger;

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
                  _title,
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
          if (_isEdit) ...[
            const SizedBox(height: 4),
            Text(
              '${_isIncome ? 'Income' : 'Expense'} · ${_formatDate(widget.existing!.date)} (fixed)',
              style: const TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: AppText.mono(32),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: AppText.mono(32, color: AppColors.text3),
              hintText: '0.00',
              hintStyle: AppText.mono(32, color: AppColors.text3),
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
                ButtonSegment<int>(
                  value: w.id!,
                  label: Text(w.name),
                ),
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
          const SizedBox(height: 12),
          Text(
            _fromForLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _fromForCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _isIncome ? 'e.g. Salary, Mom' : 'e.g. Chai, Petrol',
              errorText: fromForError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: noteLabel,
              hintText: _isIncome ? 'e.g. October salary' : 'e.g. Lunch bill',
              errorText: noteError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _CategoryField(
            isIncome: _isIncome,
            value: _category,
            onChanged: (v) => setState(() => _category = v),
          ),
          if (saveError != null) ...[
            const SizedBox(height: 8),
            Text(
              saveError,
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
                backgroundColor: saveBg,
                foregroundColor: AppColors.inkOnPrimary,
                // Explicit dimmed disabled state — a blank note / bad amount
                // reads as "enforced rule", not "dead button".
                disabledBackgroundColor: saveBg.withValues(alpha: 0.28),
                disabledForegroundColor:
                    AppColors.inkOnPrimary.withValues(alpha: 0.55),
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
                  : Text(
                      _isEdit
                          ? 'Save changes'
                          : (_isIncome ? 'Save' : 'Save'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    return '${parsed.day} ${_month(parsed.month)} ${parsed.year}';
  }

  static String _month(int m) => const <String>[
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m];
}

/// Category dropdown for the txn sheet. Options follow the txn type;
/// the sheet owns the default (last-used per type, else the list tail).
class _CategoryField extends StatelessWidget {
  final bool isIncome;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _CategoryField({
    required this.isIncome,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = isIncome ? incomeCategories : expenseCategories;
    final effective =
        (value != null && options.contains(value)) ? value : options.last;
    return DropdownButtonFormField<String>(
      initialValue: effective,
      decoration: InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: [
        for (final c in options)
          DropdownMenuItem<String>(value: c, child: Text(c)),
      ],
      onChanged: onChanged,
    );
  }
}

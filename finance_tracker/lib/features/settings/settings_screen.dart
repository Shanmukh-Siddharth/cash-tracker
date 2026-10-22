/// Settings: backup export/import, PIN + biometric lock prefs, safe reset,
/// about. Demo-1 emerald styling. Destructive ops are double-confirmed:
/// import = file-pick + "Replace all data?" dialog, reset = two dialogs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_version.dart';
import '../../core/files.dart';
import '../../core/theme.dart';
import '../../data/repos/export_repo.dart';
import '../../state/providers.dart';
import '../lan_api/lan_api_screen.dart';
import '../lock/pin_store.dart';
import '../recurring/recurring_screen.dart';
import 'settings_store.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;
  String? _lastExportAt;
  bool _bioEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final last = await SettingsStore.readLastExport();
    final bio = await SettingsStore.readBiometric();
    if (!mounted) return;
    setState(() {
      _lastExportAt = last;
      _bioEnabled = bio;
    });
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  String _exportSubtitle() {
    final raw = _lastExportAt;
    if (raw == null) return 'Never exported';
    final parsed = DateTime.tryParse(raw);
    final shown = parsed == null
        ? raw
        : DateFormat('yyyy-MM-dd HH:mm').format(parsed);
    return 'Last export: $shown';
  }

  /// Shared confirm dialog. Returns true only on explicit confirmation.
  Future<bool> _confirm(
    String title,
    String body, {
    required String okLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: AppColors.text,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _runExport({required bool csv}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final db = await ref.read(databaseProvider.future);
      final repo = ExportRepo(db);
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String filename;
      final String content;
      if (csv) {
        content = await repo.buildCsv();
        filename = 'finance_export_$stamp.csv';
      } else {
        content = jsonEncode(await repo.buildJson());
        filename = 'finance_backup_$stamp.json';
      }
      final path = await saveAndShare(filename, content);
      final nowIso = DateTime.now().toIso8601String();
      await SettingsStore.writeLastExport(nowIso);
      if (!mounted) return;
      setState(() => _lastExportAt = nowIso);
      _snack('${csv ? 'CSV' : 'JSON'} saved: $path');
    } catch (e) {
      if (!mounted) return;
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importJson() async {
    if (_busy) return;
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Could not open file picker: $e', error: true);
      return;
    }
    if (picked == null || !mounted) return;
    final path = picked.path;
    if (path == null) {
      _snack('Could not read that file', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final raw = await File(path).readAsString();
      final db = await ref.read(databaseProvider.future);
      final repo = ExportRepo(db);
      late final Map<String, dynamic> backup;
      try {
        backup = repo.parseBackup(raw);
      } on InvalidBackup catch (e) {
        if (!mounted) return;
        _snack('Invalid backup file: ${e.message}', error: true);
        return;
      }
      final walletCount = (backup['wallets'] as List).length;
      final txnCount = (backup['transactions'] as List).length;
      if (!mounted) return;
      final ok = await _confirm(
        'Replace all data?',
        'Restore backup with $walletCount wallets and $txnCount '
        'transactions? Current data will be replaced.',
        okLabel: 'Restore',
        destructive: true,
      );
      if (!ok || !mounted) return;
      await repo.restoreFromJson(backup);
      refreshAfterMutation(ref);
      if (!mounted) return;
      _snack('Backup restored ($txnCount transactions)');
    } on InvalidBackup {
      if (!mounted) return;
      _snack('Invalid backup file', error: true);
    } catch (e) {
      if (!mounted) return;
      _snack('Restore failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePin() async {
    if (_busy) return;
    const store = PinStore();
    final has = await store.hasPin();
    if (!mounted) return;
    final cur = TextEditingController();
    final next = TextEditingController();
    final again = TextEditingController();
    var saved = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx2, setD) => AlertDialog(
            title: const Text('Change PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (has) ...[
                  _PinField(controller: cur, label: 'Current PIN'),
                  const SizedBox(height: 8),
                ],
                _PinField(controller: next, label: 'New PIN (4 digits)'),
                const SizedBox(height: 8),
                _PinField(controller: again, label: 'Confirm new PIN'),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    err!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx2).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final problem = await _trySavePin(
                    store,
                    has,
                    cur.text,
                    next.text,
                    again.text,
                  );
                  if (problem != null) {
                    setD(() => err = problem);
                  } else {
                    saved = true;
                    if (ctx2.mounted) Navigator.of(ctx2).pop();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    cur.dispose();
    next.dispose();
    again.dispose();
    if (!mounted) return;
    if (saved) _snack('PIN changed');
  }

  /// Returns an error string, or null on success (PIN saved).
  Future<String?> _trySavePin(
    PinStore store,
    bool has,
    String cur,
    String next,
    String again,
  ) async {
    if (has && !await store.verifyPin(cur.trim())) {
      return 'Current PIN is wrong';
    }
    if (!RegExp(r'^\d{4}$').hasMatch(next.trim())) {
      return 'New PIN must be 4 digits';
    }
    if (next.trim() != again.trim()) {
      return 'New PINs do not match';
    }
    await store.setPin(next.trim());
    return null;
  }

  Future<void> _resetAll() async {
    if (_busy) return;
    final step1 = await _confirm(
      'Reset all data?',
      'All wallets, transactions, cart items and debts will be deleted, '
      'and the app PIN removed (fresh setup on next lock).',
      okLabel: 'Continue',
      destructive: true,
    );
    if (!step1 || !mounted) return;
    final step2 = await _confirm(
      'Really delete everything?',
      'This cannot be undone. Default wallets (Cash, UPI, Bank) '
      'will be reseeded.',
      okLabel: 'Reset',
      destructive: true,
    );
    if (!step2 || !mounted) return;
    setState(() => _busy = true);
    try {
      final db = await ref.read(databaseProvider.future);
      await ExportRepo(db).resetAll();
      // PIN lives in secure storage (resetAll cannot reach it from unit
      // tests): delete it here so the lock gate re-probes into SETUP mode.
      // Device-verified half of reset; the prefs half is unit-tested.
      try {
        await const PinStore().clearPin();
      } catch (_) {
        // Secure storage unavailable (e.g. tests) — prefs/DB half still done.
      }
      if (!mounted) return;
      setState(() => _lastExportAt = null);
      refreshAfterMutation(ref);
      // Force a fresh lock session even if reset ran while unlocked: the
      // lock gate remounts, re-probes hasPin()==false, and shows PIN setup.
      ref.read(lockServiceProvider).lock();
      if (!mounted) return;
      _snack('All data reset');
    } catch (e) {
      if (!mounted) return;
      _snack('Reset failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _about() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About'),
        content: const Text(
          'NEB:Expense Tracker $appVersion\nOffline • Emerald build\n\n'
          'All data stays on this phone. Export JSON regularly as backup.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exportSubtitle = _exportSubtitle();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Section('Backup'),
          _TileCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.table_view_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Export CSV'),
                subtitle: Text(exportSubtitle),
                trailing: const Icon(Icons.share_outlined),
                enabled: !_busy,
                onTap: () => _runExport(csv: true),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.data_object_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Export JSON'),
                subtitle: Text(exportSubtitle),
                trailing: const Icon(Icons.share_outlined),
                enabled: !_busy,
                onTap: () => _runExport(csv: false),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.upload_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Import JSON'),
                subtitle: const Text('Replaces all data after confirm'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: _importJson,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('Security'),
          _TileCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.pin_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Change PIN'),
                subtitle: const Text('Verify current, then enter new twice'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: _changePin,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(
                  Icons.fingerprint,
                  color: AppColors.primary,
                ),
                title: const Text('Biometric unlock'),
                subtitle: const Text('Off means PIN only'),
                value: _bioEnabled,
                onChanged: _busy
                    ? null
                    : (v) async {
                        await SettingsStore.writeBiometric(v);
                        if (!mounted) return;
                        setState(() => _bioEnabled = v);
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('Local network'),
          _TileCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.wifi_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('LAN API'),
                subtitle: const Text('View dashboard from a PC browser'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LanApiScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.event_repeat_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Monthly items'),
                subtitle: const Text('Rent, salary, subscriptions — add by hand'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MonthlyItemsScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('Danger zone'),
          _TileCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: AppColors.danger,
                ),
                title: const Text(
                  'Reset all data',
                  style: TextStyle(color: AppColors.danger),
                ),
                subtitle: const Text('Double confirm, wallets reseeded'),
                enabled: !_busy,
                onTap: _resetAll,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('About'),
          _TileCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.info_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('About'),
                subtitle: const Text(
                  'NEB:Expense Tracker • $appVersion • Offline',
                ),
                enabled: !_busy,
                onTap: _about,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(label, style: AppText.eyebrow),
    );
  }
}

class _TileCard extends StatelessWidget {
  final List<Widget> children;
  const _TileCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: children),
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _PinField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

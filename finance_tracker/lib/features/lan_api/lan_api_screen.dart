/// LAN API screen: Settings → LAN API. The server keeps running in the
/// background (foreground service) until the user taps Stop or the process
/// is killed — leaving this screen, backgrounding or locking does NOT stop
/// it. Reopening the screen re-attaches to the running server.
///
/// Flow: on open, re-attach when a server is already running; else check
/// WiFi (wifi/ethernet OK; none/mobile → popup "Connect to WiFi first …" and
/// do NOT start). On pass: resolve the WiFi IPv4 via [NetworkInterface],
/// start [LanApiServer], launch the foreground service, show URL + token
/// (big mono + copy buttons). Emerald theme.
///
/// Device-only note: background survival is verified on-device
/// (owner-excluded from automated tests). Unit tests set
/// [backgroundEnabled] = false so the platform service never starts.
library;

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../data/repos/debt_repo.dart';
import '../../data/repos/export_repo.dart';
import '../../data/repos/stats_repo.dart';
import '../../data/repos/txn_repo.dart';
import '../../data/repos/wallet_repo.dart';
import '../../state/providers.dart';
import 'lan_background.dart';
import 'lan_qr.dart';
import 'lan_server.dart';

/// First non-loopback private IPv4 on the device (WiFi interface).
/// Null when none (WiFi off / mobile-only).
Future<String?> resolveWifiIpv4() async {
  try {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (addr.isLoopback) continue;
        if (ip == '0.0.0.0') continue;
        if (ip.startsWith('10.') ||
            ip.startsWith('192.168.') ||
            _is172Private(ip)) {
          return ip;
        }
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

bool _is172Private(String ip) {
  final second = int.tryParse(ip.split('.').elementAtOrNull(1) ?? '');
  return ip.startsWith('172.') &&
      second != null &&
      second >= 16 &&
      second <= 31;
}

class LanApiScreen extends ConsumerStatefulWidget {
  /// When false, the foreground service is never started (unit tests).
  /// Default true (production behavior).
  final bool backgroundEnabled;

  const LanApiScreen({super.key, this.backgroundEnabled = true});

  @override
  ConsumerState<LanApiScreen> createState() => _LanApiScreenState();
}

class _LanApiScreenState extends ConsumerState<LanApiScreen> {
  LanApiServer? _server;
  String? _error;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    // Start after first frame so dialogs/popups have a context.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  // No WidgetsBindingObserver: background/lock must NOT stop the server.
  // No dispose-stop either: leaving the screen keeps it running (Stop button
  // or process kill ends it).

  Future<void> _boot() async {
    if (!mounted) return;
    // 0. Re-attach when a server is already running (started from an
    // earlier visit — it survives screen pops and backgrounding).
    final held = LanServerHolder.instance.server;
    if (held != null && held.isRunning) {
      setState(() {
        _server = held;
        _starting = false;
        _error = null;
      });
      return;
    }
    // 1. WiFi check: wifi or ethernet OK; none/mobile-only → popup, no start.
    List<ConnectivityResult> results;
    try {
      results = await Connectivity().checkConnectivity();
    } catch (_) {
      results = const <ConnectivityResult>[ConnectivityResult.none];
    }
    final onLan = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    if (!mounted) return;
    if (!onLan) {
      setState(() {
        _starting = false;
        _error = 'no_wifi';
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connect to WiFi first'),
          content: const Text(
            'Connect to WiFi first — both devices must be on the same '
            'network.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    // 2. Resolve the WiFi IPv4.
    final wifiIp = await resolveWifiIpv4();
    if (!mounted) return;
    if (wifiIp == null) {
      setState(() {
        _starting = false;
        _error = 'no_ip';
      });
      return;
    }
    // 3. Start the server on the WiFi IP only.
    try {
      final db = await ref.read(databaseProvider.future);
      final server = LanApiServer(
        wallets: WalletRepo(db),
        txns: TxnRepo(db),
        stats: StatsRepo(db),
        exports: ExportRepo(db),
        debts: DebtRepo(db),
        // LAN writes refresh Home/History/Stats like any in-app write.
        onMutated: () {
          if (mounted) refreshAfterMutation(ref);
        },
      );
      await server.start(wifiIp: wifiIp);
      if (!mounted) {
        await server.stop();
        return;
      }
      LanServerHolder.instance.attach(server);
      // Foreground service so Android keeps serving while minimized,
      // backgrounded or UI-locked. Skipped when backgroundEnabled is false
      // (unit tests) — the HTTP server itself still starts.
      if (widget.backgroundEnabled) {
        await LanBackground.ensureNotificationPermission();
        await LanBackground.start(server.url);
      }
      setState(() {
        _server = server;
        _starting = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'start_failed';
      });
    }
  }

  /// The ONLY in-app way to stop the server (besides process kill).
  Future<void> _stop() async {
    final s = _server;
    if (s == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await s.stop();
    LanServerHolder.instance.detach();
    if (widget.backgroundEnabled) await LanBackground.stop();
    _server = null;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final running = _server?.isRunning ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('LAN API')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(
            running: running,
            starting: _starting,
            error: _error,
          ),
          const SizedBox(height: 16),
          if (running && _server != null) ...[
            _CredentialCard(
              label: 'URL (type on PC browser)',
              value: _server!.url,
              onCopy: () => _copy('URL', _server!.url),
            ),
            const SizedBox(height: 12),
            _CredentialCard(
              label: 'Token (regenerates every start)',
              value: _server!.token,
              onCopy: () => _copy('Token', _server!.token),
            ),
            const SizedBox(height: 12),
            _QrCard(
              payload: buildQrPayload(_server!.url, _server!.token),
              onCopy: () => _copy(
                'QR payload',
                buildQrPayload(_server!.url, _server!.token),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'On your PC browser open the URL above, then pass the token '
              'as ?token=… or an Authorization: Bearer header. '
              'First visit: browser warns (self-signed) → Advanced → '
              'Proceed (safe: your own phone, LAN only). Read + write · '
              'same WiFi only · keeps running in the background until '
              'you tap Stop below or the app is killed.',
              style: TextStyle(color: AppColors.text2, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.text,
              ),
              onPressed: () => _stop(),
              icon: const Icon(Icons.stop_outlined),
              label: const Text('Stop server'),
            ),
          ] else if (!_starting) ...[
            const Text(
              'Server is off. Re-open this screen on WiFi to start it.',
              style: TextStyle(color: AppColors.text2, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool running;
  final bool starting;
  final String? error;
  const _StatusCard({
    required this.running,
    required this.starting,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String text;
    if (starting) {
      dot = AppColors.gold;
      text = 'Starting…';
    } else if (running) {
      dot = AppColors.primary;
      text = 'Live on your WiFi · running in background';
    } else {
      dot = AppColors.text3;
      text = 'Off';
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(text, style: AppText.mono(16)),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  final String payload;
  final VoidCallback onCopy;
  const _QrCard({required this.payload, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Scan to connect', style: AppText.eyebrow)),
              IconButton(
                tooltip: 'Copy QR payload',
                onPressed: onCopy,
                icon: const Icon(
                  Icons.copy_outlined,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialCard extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  const _CredentialCard({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.eyebrow),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(value, style: AppText.mono(18)),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: onCopy,
                icon: const Icon(
                  Icons.copy_outlined,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// LAN API tests (contract: docs/API.md v2):
// - lan_guard matrix: /24 compare, public IP reject, loopback, IPv6 skip.
// - lan_token: shape, validate right/wrong, rotation invalidates old.
// - Envelope: real HTTPS GETs (dart:io HttpClient with badCertificateCallback)
//   against a testMode server on 127.0.0.1 with a seeded ffi in-memory DB:
//   auth 401→200, wallets, transactions pagination/filters, summary, stats,
//   exports, 404 JSON.
// - HTTPS enforced: plain http:// never gets a response (throws, not 200);
//   https without accepting the self-signed cert also fails.
// - POST /transactions: income+expense happy paths (exact balances, 201 +
//   Location), 422 overspend (balance untouched, available_paise echoed),
//   400/404/422 matrix, CORS preflight OPTIONS → 204 + headers, POST counts
//   toward the 60/min rate limit, onMutated fires only on success.
// - QR: buildQrPayload pure-function test.
// - Guard bypass happens ONLY in testMode (unit-asserted separately).
// - Rate limit: 61st request in a minute → 429 + Retry-After (own server).
import 'dart:convert';
import 'dart:io';

import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/repos/export_repo.dart';
import 'package:finance_tracker/data/repos/stats_repo.dart';
import 'package:finance_tracker/data/repos/txn_repo.dart';
import 'package:finance_tracker/data/repos/wallet_repo.dart';
import 'package:finance_tracker/features/lan_api/lan_cert.dart';
import 'package:finance_tracker/features/lan_api/lan_guard.dart';
import 'package:finance_tracker/features/lan_api/lan_qr.dart';
import 'package:finance_tracker/features/lan_api/lan_server.dart';
import 'package:finance_tracker/features/lan_api/lan_token.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<int> _walletId(WalletRepo repo, String name) async {
  final wallets = await repo.listWallets();
  return wallets.firstWhere((w) => w.name == name).id!;
}

/// Direct insert (bypasses overspend guards); balances rebuilt after.
Future<void> _seed(Database db) async {
  final wallets = WalletRepo(db);
  final cash = await _walletId(wallets, 'Cash');
  final upi = await _walletId(wallets, 'UPI');
  final bank = await _walletId(wallets, 'Bank');
  final now = DateTime.now().toIso8601String();
  Future<void> row(
    int wallet,
    String type,
    int amount,
    String fromFor, [
    String? note,
  ]) => db.insert('transactions', <String, Object?>{
    'wallet_id': wallet,
    'type': type,
    'amount': amount,
    'from_for': fromFor,
    'note': note,
    'date': now,
    'created_at': now,
  });
  await row(cash, 'income', 10000, 'Salary', 'Monthly pay');
  await row(cash, 'expense', 2500, 'Chai break');
  await row(upi, 'income', 50000, 'Freelance');
  await row(bank, 'income', 20000, 'Transfer in');
  await row(bank, 'expense', 12000, 'Laptop', 'Work machine');
  await row(cash, 'expense', 300, 'Chai refill');
  await recalculateBalances(db);
}

/// TLS client that accepts the self-signed LAN cert (testMode only).
HttpClient _tlsClient() {
  final client = HttpClient();
  client.badCertificateCallback = (_, _, _) => true;
  return client;
}

class _Resp {
  final int status;
  final String body;
  final HttpHeaders headers;
  const _Resp(this.status, this.body, this.headers);

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

Future<_Resp> _get(
  HttpClient client,
  String base,
  String path, {
  String? token,
  bool viaHeader = false,
}) async {
  final uri = (token != null && !viaHeader)
      ? Uri.parse('$base$path${path.contains('?') ? '&' : '?'}token=$token')
      : Uri.parse('$base$path');
  final req = await client.getUrl(uri);
  if (token != null && viaHeader) {
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  return _Resp(resp.statusCode, body, resp.headers);
}

Future<_Resp> _post(
  HttpClient client,
  String base,
  String path,
  Map<String, Object?> body, {
  String? token,
  bool viaHeader = false,
}) async {
  return _postRaw(
    client,
    base,
    path,
    jsonEncode(body),
    token: token,
    viaHeader: viaHeader,
  );
}

Future<_Resp> _postRaw(
  HttpClient client,
  String base,
  String path,
  String rawBody, {
  String? token,
  bool viaHeader = false,
}) async {
  final uri = (token != null && !viaHeader)
      ? Uri.parse('$base$path${path.contains('?') ? '&' : '?'}token=$token')
      : Uri.parse('$base$path');
  final req = await client.postUrl(uri);
  req.headers.contentType = ContentType.json;
  if (token != null && viaHeader) {
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  req.write(rawBody);
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  return _Resp(resp.statusCode, body, resp.headers);
}

Future<_Resp> _options(HttpClient client, String base, String path) async {
  final req = await client.openUrl('OPTIONS', Uri.parse('$base$path'));
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  return _Resp(resp.statusCode, body, resp.headers);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // One shared TLS identity dir for the whole file: RSA-2048 keygen happens
  // once (first server start), every later start reuses the PEMs.
  late Directory tlsDir;
  setUpAll(() async {
    tlsDir = await Directory.systemTemp.createTemp('lan_tls_');
  });
  tearDownAll(() async {
    try {
      await tlsDir.delete(recursive: true);
    } catch (_) {}
  });

  group('lan_guard', () {
    test('isPrivateIp accepts 10/8, 172.16/12, 192.168/16', () {
      expect(isPrivateIp('10.0.0.1'), true);
      expect(isPrivateIp('10.255.200.9'), true);
      expect(isPrivateIp('172.16.0.1'), true);
      expect(isPrivateIp('172.31.255.255'), true);
      expect(isPrivateIp('192.168.0.1'), true);
      expect(isPrivateIp('192.168.1.77'), true);
    });

    test('isPrivateIp rejects public, loopback, v6, garbage', () {
      expect(isPrivateIp('8.8.8.8'), false); // public
      expect(isPrivateIp('1.2.3.4'), false);
      expect(isPrivateIp('172.15.0.1'), false); // just below 172.16/12
      expect(isPrivateIp('172.32.0.1'), false); // just above
      expect(isPrivateIp('127.0.0.1'), false); // loopback, not private
      expect(isPrivateIp('::1'), false); // IPv6 skipped in v1
      expect(isPrivateIp('fe80::1'), false);
      expect(isPrivateIp('not-an-ip'), false);
      expect(isPrivateIp(''), false);
    });

    test('isSameLan /24 compare', () {
      expect(isSameLan('192.168.1.10', '192.168.1.77'), true);
      expect(isSameLan('192.168.1.10', '192.168.2.9'), false);
      expect(isSameLan('10.0.0.5', '10.0.0.200'), true);
      expect(isSameLan('10.0.0.5', '10.0.1.5'), false);
      expect(isSameLan('127.0.0.1', '127.0.0.1'), true);
      expect(isSameLan('8.8.8.8', '8.8.8.8'), true); // pure compare…
      expect(isPrivateIp('8.8.8.8'), false); // …guard still rejects
      expect(isSameLan('::1', '::1'), false); // IPv6 skipped
      expect(isSameLan('192.168.1.1', 'nope'), false);
      expect(isSameLan('', ''), false);
    });

    test('guard would reject cross-subnet and public clients', () {
      // The middleware rule is: private && sameLan. Spot-check the
      // combinations a 403 depends on.
      bool allowed(String server, String client) =>
          isPrivateIp(client) && isSameLan(server, client);
      expect(allowed('192.168.1.50', '192.168.1.51'), true);
      expect(allowed('192.168.1.50', '192.168.2.9'), false);
      expect(allowed('192.168.1.50', '8.8.8.8'), false);
      expect(allowed('192.168.1.50', '127.0.0.1'), false);
    });
  });

  group('lan_token', () {
    test('generateToken is 6-char unambiguous + unique', () {
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        final t = generateToken();
        expect(t.length, 6);
        expect(RegExp(r'^[A-Z2-9]+$').hasMatch(t), true);
        expect(t.contains('0'), false);
        expect(t.contains('O'), false);
        expect(t.contains('1'), false);
        expect(t.contains('I'), false);
        expect(t.contains('L'), false);
        seen.add(t);
      }
      expect(seen.length, greaterThan(45)); // effectively unique
    });

    test('validate accepts current, rejects wrong/null/empty', () {
      final holder = LanToken();
      expect(holder.validate('ABCDEF'), false); // nothing issued yet
      final current = holder.rotate();
      expect(holder.validate(current), true);
      expect(holder.validate('WRONG!'), false);
      expect(holder.validate(null), false);
      expect(holder.validate(''), false);
      expect(holder.validate(current.toLowerCase()), false);
    });

    test('rotate invalidates the previous token', () {
      final holder = LanToken();
      final first = holder.rotate();
      final second = holder.rotate();
      expect(first, isNot(second));
      expect(holder.validate(first), false);
      expect(holder.validate(second), true);
    });
  });

  group('lan_cert', () {
    test('generateLanIdentity: PEMs parse back with expected subject', () async {
      final (keyPem, certPem) = await generateLanIdentity();
      expect(keyPem, contains('-----BEGIN RSA PRIVATE KEY-----'));
      expect(certPem, contains('-----BEGIN CERTIFICATE-----'));
      final subject = lanCertSubject(certPem);
      expect(subject, contains('finance-tracker.local'));
      expect(subject, contains('Personal Finance Tracker'));
      // BoringSSL itself must accept the chain (the real proof).
      final ctx = SecurityContext();
      ctx.useCertificateChainBytes(utf8.encode(certPem));
      ctx.usePrivateKeyBytes(utf8.encode(keyPem));
    });

    test('loadOrCreate persists once and reuses PEMs', () async {
      final dir = await Directory.systemTemp.createTemp('lan_cert_reuse_');
      try {
        await loadOrCreateLanSecurityContext(directory: dir);
        final keyFile = File('${dir.path}/lan_api_key.pem');
        final certFile = File('${dir.path}/lan_api_cert.pem');
        expect(await keyFile.exists(), true);
        expect(await certFile.exists(), true);
        final key1 = await keyFile.readAsString();
        final cert1 = await certFile.readAsString();
        await loadOrCreateLanSecurityContext(directory: dir);
        expect(await keyFile.readAsString(), key1); // reused, not regenned
        expect(await certFile.readAsString(), cert1);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('lan_qr', () {
    test('buildQrPayload encodes url+token JSON exactly', () {
      const url = 'https://192.168.1.5:8080/api/v1';
      const token = 'ABC123';
      final payload = buildQrPayload(url, token);
      expect(
        jsonDecode(payload),
        {'url': url, 'token': token},
      );
      // Compact: no whitespace/newlines for a small QR.
      expect(payload.contains('\n'), false);
      expect(payload.contains(' '), false);
    });
  });

  group('lan_server envelope (testMode, real HTTPS)', () {
    late Database db;
    late LanApiServer server;
    late HttpClient client;
    late String base;

    setUpAll(() async {
      db = await openAppDatabase(path: inMemoryDatabasePath);
      await _seed(db);
      server = LanApiServer(
        wallets: WalletRepo(db),
        txns: TxnRepo(db),
        stats: StatsRepo(db),
        exports: ExportRepo(db),
        certDirectory: tlsDir,
      );
      // Loopback bind is allowed ONLY via testMode; guard is bypassed
      // for these direct-connect 127.0.0.1 clients.
      await server.start(wifiIp: '127.0.0.1', port: 0, testMode: true);
      base = 'https://127.0.0.1:${server.port}/api/v1';
      client = _tlsClient();
    });

    tearDownAll(() async {
      client.close(force: true);
      await server.stop();
      await db.close();
    });

    test('server exposes https url/token/isRunning, refuses wildcard', () async {
      expect(server.isRunning, true);
      expect(server.url.startsWith('https://127.0.0.1:'), true);
      expect(server.url.endsWith('/api/v1'), true);
      expect(server.token.length, 6);
      final probe = LanApiServer(
        wallets: WalletRepo(db),
        txns: TxnRepo(db),
        stats: StatsRepo(db),
        exports: ExportRepo(db),
        certDirectory: tlsDir,
      );
      expect(
        () => probe.start(wifiIp: '0.0.0.0', testMode: true),
        throwsArgumentError,
      );
      expect(
        () => probe.start(wifiIp: '127.0.0.1'), // no testMode → refuse
        throwsArgumentError,
      );
    });

    test('TLS-only: plain http and untrusted https fail, never 200', () async {
      final strict = HttpClient(); // no badCertificateCallback
      try {
        // https WITHOUT accepting the self-signed cert → handshake fails.
        await expectLater(
          strict
              .getUrl(Uri.parse('$base/health?token=${server.token}'))
              .then((req) => req.close()),
          throwsA(anything),
        );
        // Plain http:// to the TLS port → closed/hangup, never a response.
        await expectLater(
          strict
              .getUrl(
                Uri.parse(
                  'http://127.0.0.1:${server.port}/api/v1/health?token=${server.token}',
                ),
              )
              .then((req) => req.close()),
          throwsA(anything),
        );
      } finally {
        strict.close(force: true);
      }
    });

    test('/health 401 without token, 200 with token', () async {
      final anon = await _get(client, base, '/health');
      expect(anon.status, 401);
      expect(anon.json['error']['code'], 'unauthorized');

      final bad = await _get(client, base, '/health?token=WRONG!!');
      expect(bad.status, 401);

      final viaQuery = await _get(
        client,
        base,
        '/health',
        token: server.token,
      );
      expect(viaQuery.status, 200);
      expect(viaQuery.json['data']['status'], 'ok');
      expect(viaQuery.json['data']['version'], 'V.0.0.1');
      expect(viaQuery.json['data']['lan_only'], true);

      final viaHeader = await _get(
        client,
        base,
        '/health',
        token: server.token,
        viaHeader: true,
      );
      expect(viaHeader.status, 200);
    });

    test('/wallets shape with paise+inr', () async {
      final r = await _get(client, base, '/wallets', token: server.token);
      expect(r.status, 200);
      final data = r.json['data'] as List;
      expect(data.length, 3);
      final cash = data
          .map((e) => e as Map<String, dynamic>)
          .firstWhere((w) => w['name'] == 'Cash');
      expect(cash['balance_paise'], 7200); // 10000-2500-300
      expect(cash['balance_inr'], '72.00');
      expect(cash['id'] is int, true);
    });

    test('/transactions pagination meta + filters', () async {
      Future<List<dynamic>> items(String query) async {
        final r = await _get(
          client,
          base,
          '/transactions$query',
          token: server.token,
          viaHeader: true,
        );
        expect(r.status, 200);
        return (r.json['data'] as List);
      }

      final first = await _get(
        client,
        base,
        '/transactions',
        token: server.token,
      );
      expect(first.status, 200);
      expect(first.json['meta'], {
        'total': 6,
        'page': 1,
        'per_page': 20,
      });
      expect((first.json['data'] as List).length, 6);

      final p2 = await _get(
        client,
        base,
        '/transactions?per_page=2&page=2',
        token: server.token,
      );
      expect(p2.json['meta']['total'], 6);
      expect(p2.json['meta']['page'], 2);
      expect((p2.json['data'] as List).length, 2);

      expect((await items('?type=expense')).length, 3);
      expect((await items('?type=income')).length, 3);

      final cashId = await _walletId(WalletRepo(db), 'Cash');
      expect((await items('?wallet_id=$cashId')).length, 3);
      expect((await items('?q=chai')).length, 2); // matches from_for
      expect((await items('?q=WORK')).length, 1); // matches note, case-free
      expect((await items('?q=miscellaneous')).length, 6); // category match
      expect((await items('?type=expense&q=chai')).length, 2);

      final one = (await items('?per_page=1'))..first;
      final txn = (one.first as Map).cast<String, dynamic>();
      expect(txn['amount_paise'] is int, true);
      expect(txn['amount_inr'] is String, true);
      expect(txn['date'] is String, true);
      expect(DateTime.tryParse(txn['date'] as String), isNotNull);
      expect(txn['category'] is String, true); // v2 field, always present

      final tooBig = await _get(
        client,
        base,
        '/transactions?per_page=101',
        token: server.token,
      );
      expect(tooBig.status, 400);
      final badType = await _get(
        client,
        base,
        '/transactions?type=gift',
        token: server.token,
      );
      expect(badType.status, 422);
    });

    test('/summary totals + today', () async {
      final r = await _get(client, base, '/summary', token: server.token);
      expect(r.status, 200);
      final data = r.json['data'] as Map<String, dynamic>;
      // Cash 7200 + UPI 50000 + Bank (20000-12000).
      expect(data['total_paise'], 65200);
      expect(data['total_inr'], '652.00');
      final today = data['today'] as Map<String, dynamic>;
      expect(today['income_paise'], 80000);
      expect(today['expense_paise'], 14800);
    });

    test('/stats shapes', () async {
      final daily = await _get(
        client,
        base,
        '/stats/daily?days=7',
        token: server.token,
      );
      expect(daily.status, 200);
      final days = daily.json['data'] as List;
      expect(days.isNotEmpty, true);
      final last = (days.last as Map).cast<String, dynamic>();
      expect(last['expense_paise'], 14800);
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(last['date'] as String),
          true);

      final monthly = await _get(
        client,
        base,
        '/stats/monthly?months=2',
        token: server.token,
      );
      expect(monthly.status, 200);
      final months = monthly.json['data'] as List;
      expect(months.length, 2);
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
      final current = (months.last as Map).cast<String, dynamic>();
      expect(current['month'], key);
      expect(current['income_paise'], 80000);
      expect(current['expense_paise'], 14800);

      final share = await _get(
        client,
        base,
        '/stats/share',
        token: server.token,
      );
      expect(share.status, 200);
      final shareData = share.json['data'] as Map<String, dynamic>;
      expect((shareData['by_wallet'] as List).length, 3);
      expect(shareData['income_paise'], 80000);
      expect(shareData['expense_paise'], 14800);
    });

    test('/export.csv header + /export.json keys', () async {
      final csv = await _get(
        client,
        base,
        '/export.csv',
        token: server.token,
      );
      expect(csv.status, 200);
      expect(csv.headers.contentType?.mimeType, 'text/csv');
      expect(
        csv.headers.value('content-disposition'),
        contains('finance_export_'),
      );
      expect(
        csv.body.split('\n').first,
        'id,date,type,amount,from_for,wallet,note,created_at,category',
      );

      final backup = await _get(
        client,
        base,
        '/export.json',
        token: server.token,
      );
      expect(backup.status, 200);
      final map = backup.json;
      expect(map['schema_version'], 3);
      expect(map['wallets'] is List, true);
      expect((map['transactions'] as List).length, 6);
      expect(map['cart'] is List, true);
    });

    test('unknown endpoint is JSON 404, still authed', () async {
      final anon = await _get(client, base, '/nope');
      expect(anon.status, 401); // auth runs before routing
      final r = await _get(client, base, '/nope', token: server.token);
      expect(r.status, 404);
      expect(r.json['error']['code'], 'not_found');
    });

    test('stop() kills the server', () async {
      final db2 = await openAppDatabase(path: inMemoryDatabasePath);
      final s2 = LanApiServer(
        wallets: WalletRepo(db2),
        txns: TxnRepo(db2),
        stats: StatsRepo(db2),
        exports: ExportRepo(db2),
        certDirectory: tlsDir,
      );
      await s2.start(wifiIp: '127.0.0.1', port: 0, testMode: true);
      expect(s2.isRunning, true);
      final probe = _tlsClient();
      try {
        final ok = await _get(
          probe,
          'https://127.0.0.1:${s2.port}/api/v1',
          '/health',
          token: s2.token,
        );
        expect(ok.status, 200);
      } finally {
        probe.close(force: true);
      }
      await s2.stop();
      expect(s2.isRunning, false);
      expect(s2.token, '');
      await db2.close();
    });
  });

  group('lan_server POST /transactions (testMode, real HTTPS)', () {
    late Database db;
    late LanApiServer server;
    late HttpClient client;
    late String base;
    var mutated = 0;

    setUpAll(() async {
      db = await openAppDatabase(path: inMemoryDatabasePath);
      await _seed(db);
      server = LanApiServer(
        wallets: WalletRepo(db),
        txns: TxnRepo(db),
        stats: StatsRepo(db),
        exports: ExportRepo(db),
        certDirectory: tlsDir,
        onMutated: () => mutated++,
      );
      await server.start(wifiIp: '127.0.0.1', port: 0, testMode: true);
      base = 'https://127.0.0.1:${server.port}/api/v1';
      client = _tlsClient();
    });

    tearDownAll(() async {
      client.close(force: true);
      await server.stop();
      await db.close();
    });

    Future<int> cashBalance() async =>
        (await WalletRepo(db).listWallets())
            .firstWhere((w) => w.name == 'Cash')
            .balancePaise;

    test('POST income happy path: 201 + Location + exact balance', () async {
      final r = await _post(
        client,
        base,
        '/transactions',
        <String, Object?>{
          'type': 'income',
          'wallet': 'cash', // name lookup, case-insensitive
          'amount_inr': '12.50',
          'from_for': 'LAN bonus',
          'note': 'Monthly bonus',
          'category': 'Bonus',
        },
        token: server.token,
        viaHeader: true,
      );
      expect(r.status, 201);
      expect(r.headers.value('location'), startsWith('/api/v1/transactions/'));
      expect(
        r.headers.value('access-control-allow-origin'),
        '*',
      ); // CORS on POST too
      final data = r.json['data'] as Map<String, dynamic>;
      expect(data['type'], 'income');
      expect(data['wallet'], 'Cash');
      expect(data['amount_paise'], 1250);
      expect(data['amount_inr'], '12.50');
      expect(data['from_for'], 'LAN bonus');
      expect(data['note'], 'Monthly bonus');
      expect(data['category'], 'Bonus');
      expect(data['id'] is int, true);
      expect(await cashBalance(), 7200 + 1250); // exact
      expect(mutated, 1);
    });

    test('POST expense happy path: paise wins, exact balance', () async {
      final cashId = await _walletId(WalletRepo(db), 'Cash');
      final r = await _post(
        client,
        base,
        '/transactions',
        <String, Object?>{
          'type': 'expense',
          'wallet_id': cashId,
          'amount_paise': 5000, // wins over amount_inr below
          'amount_inr': '999.99',
          'from_for': 'LAN buy',
          'note': 'via api',
          // no category → expense default
        },
        token: server.token,
      );
      expect(r.status, 201);
      final data = r.json['data'] as Map<String, dynamic>;
      expect(data['amount_paise'], 5000);
      expect(data['note'], 'via api');
      expect(data['category'], 'Miscellaneous');
      expect(await cashBalance(), 7200 + 1250 - 5000); // exact
      expect(mutated, 2);
    });

    test('POST 422 overspend: balance untouched + available_paise', () async {
      final before = await cashBalance();
      final r = await _post(
        client,
        base,
        '/transactions',
        <String, Object?>{
          'type': 'expense',
          'wallet': 'Cash',
          'amount_paise': before + 999999,
          'from_for': 'Too much',
          'note': 'overspend probe',
        },
        token: server.token,
      );
      expect(r.status, 422);
      expect(r.json['error']['code'], 'insufficient_balance');
      expect(r.json['error']['available_paise'], before);
      expect(await cashBalance(), before); // untouched
      expect(mutated, 2); // no refresh on failure
    });

    test('POST 400/404/422 matrix', () async {
      Future<_Resp> bad(
        Object? body, {
        bool raw = false,
      }) => raw
          ? _postRaw(client, base, '/transactions', body as String,
              token: server.token)
          : _post(client, base, '/transactions', body as Map<String, Object?>,
              token: server.token);

      // 400 malformed (not a JSON object).
      var r = await bad('not json{', raw: true);
      expect(r.status, 400);
      expect(r.json['error']['code'], 'malformed_json');
      r = await bad('[1,2]', raw: true);
      expect(r.status, 400);

      // 404 unknown wallet.
      r = await bad(<String, Object?>{
        'type': 'income',
        'wallet_id': 99999,
        'amount_paise': 100,
        'from_for': 'x',
        'note': 'x',
      });
      expect(r.status, 404);
      expect(r.json['error']['code'], 'unknown_wallet');
      r = await bad(<String, Object?>{
        'type': 'income',
        'wallet': 'Nope',
        'amount_paise': 100,
        'from_for': 'x',
        'note': 'x',
      });
      expect(r.status, 404);

      // 422 validation cases.
      final cases = <Map<String, Object?>>[
        // missing type
        {
          'wallet': 'Cash',
          'amount_paise': 100,
          'from_for': 'x',
          'note': 'x',
        },
        // bad type
        {
          'type': 'gift',
          'wallet': 'Cash',
          'amount_paise': 100,
          'from_for': 'x',
          'note': 'x',
        },
        // missing wallet
        {
          'type': 'income',
          'amount_paise': 100,
          'from_for': 'x',
          'note': 'x',
        },
        // zero / bad / missing amount
        {
          'type': 'income',
          'wallet': 'Cash',
          'amount_paise': 0,
          'from_for': 'x',
          'note': 'x',
        },
        {
          'type': 'income',
          'wallet': 'Cash',
          'amount_inr': 'abc',
          'from_for': 'x',
          'note': 'x',
        },
        {
          'type': 'income',
          'wallet': 'Cash',
          'from_for': 'x',
          'note': 'x',
        },
        // missing from_for
        {
          'type': 'income',
          'wallet': 'Cash',
          'amount_paise': 100,
          'note': 'x',
        },
        {
          'type': 'income',
          'wallet': 'Cash',
          'amount_paise': 100,
          'from_for': '  ',
          'note': 'x',
        },
        // NOTE: note is optional — missing/blank notes succeed (covered by
        // the dedicated 'POST without note' test below), so no note cases
        // here.
        // unknown category, incl. a valid income category on an expense
        {
          'type': 'expense',
          'wallet': 'Cash',
          'amount_paise': 100,
          'from_for': 'x',
          'note': 'x',
          'category': 'Nope',
        },
        {
          'type': 'expense',
          'wallet': 'Cash',
          'amount_paise': 100,
          'from_for': 'x',
          'note': 'x',
          'category': 'Salary',
        },
      ];
      for (final body in cases) {
        r = await bad(body);
        expect(r.status, 422, reason: 'body $body');
      }

      // Spot-check the new error codes.
      r = await bad(<String, Object?>{
        'type': 'expense',
        'wallet': 'Cash',
        'amount_paise': 100,
        'from_for': 'x',
        'note': 'x',
        'category': 'Nope',
      });
      expect(r.json['error']['code'], 'invalid_category');

      // 400 non-int wallet_id.
      r = await bad(<String, Object?>{
        'type': 'income',
        'wallet_id': 'abc',
        'amount_paise': 100,
        'from_for': 'x',
      });
      expect(r.status, 400);
      expect(r.json['error']['code'], 'invalid_wallet');

      // 401 without token, still enforced on POST.
      final anon = await _post(client, base, '/transactions',
          <String, Object?>{'type': 'income'});
      expect(anon.status, 401);

      expect(mutated, 2); // failures never refresh
    });

    test('POST without note succeeds (note optional, stored null)', () async {
      // Missing note entirely → 201, note echoes null.
      var r = await _post(
        client,
        base,
        '/transactions',
        <String, Object?>{
          'type': 'income',
          'wallet': 'Cash',
          'amount_paise': 111,
          'from_for': 'No-note bonus',
        },
        token: server.token,
      );
      expect(r.status, 201, reason: 'missing note must not 422');
      expect((r.json['data'] as Map<String, dynamic>)['note'], isNull);

      // Blank note → 201, stored null as before.
      r = await _post(
        client,
        base,
        '/transactions',
        <String, Object?>{
          'type': 'income',
          'wallet': 'Cash',
          'amount_paise': 222,
          'from_for': 'Blank-note bonus',
          'note': '   ',
        },
        token: server.token,
      );
      expect(r.status, 201, reason: 'blank note must not 422');
      expect((r.json['data'] as Map<String, dynamic>)['note'], isNull);
    });

    test('CORS preflight OPTIONS → 204 + headers, no auth', () async {
      final r = await _options(client, base, '/health');
      expect(r.status, 204);
      expect(r.headers.value('access-control-allow-origin'), '*');
      expect(
        r.headers.value('access-control-allow-methods'),
        contains('POST'),
      );
      expect(
        r.headers.value('access-control-allow-headers'),
        contains('Authorization'),
      );
      expect(r.headers.value('access-control-max-age'), '86400');

      final get = await _get(client, base, '/health', token: server.token);
      expect(get.headers.value('access-control-allow-origin'), '*');
    });
  });

  test('rate limit: 61st request in a minute → 429 + Retry-After', () async {
    sqfliteFfiInit();
    final db = await openAppDatabase(path: inMemoryDatabasePath);
    final server = LanApiServer(
      wallets: WalletRepo(db),
      txns: TxnRepo(db),
      stats: StatsRepo(db),
      exports: ExportRepo(db),
      certDirectory: tlsDir,
    );
    await server.start(wifiIp: '127.0.0.1', port: 0, testMode: true);
    final client = _tlsClient();
    try {
      final base = 'https://127.0.0.1:${server.port}/api/v1';
      var status = 0;
      var body = '';
      HttpHeaders? headers;
      for (var i = 0; i < 61; i++) {
        final r = await _get(client, base, '/health', token: server.token);
        status = r.status;
        body = r.body;
        headers = r.headers;
      }
      expect(status, 429);
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      expect((decoded['error'] as Map)['code'], 'rate_limited');
      expect(headers!.value(HttpHeaders.retryAfterHeader), isNotNull);
    } finally {
      client.close(force: true);
      await server.stop();
      await db.close();
    }
  });

  test('POST counts toward the 60/min rate limit', () async {
    sqfliteFfiInit();
    final db = await openAppDatabase(path: inMemoryDatabasePath);
    final server = LanApiServer(
      wallets: WalletRepo(db),
      txns: TxnRepo(db),
      stats: StatsRepo(db),
      exports: ExportRepo(db),
      certDirectory: tlsDir,
    );
    await server.start(wifiIp: '127.0.0.1', port: 0, testMode: true);
    final client = _tlsClient();
    try {
      final base = 'https://127.0.0.1:${server.port}/api/v1';
      for (var i = 0; i < 60; i++) {
        final r = await _get(client, base, '/health', token: server.token);
        expect(r.status, 200);
      }
      final r = await _post(
        client,
        base,
        '/transactions',
        <String, Object?>{
          'type': 'income',
          'wallet': 'Cash',
          'amount_paise': 100,
          'from_for': 'rate test',
          'note': 'rate test',
        },
        token: server.token,
      );
      expect(r.status, 429);
      expect(r.json['error']['code'], 'rate_limited');
    } finally {
      client.close(force: true);
      await server.stop();
      await db.close();
    }
  });
}

// LAN debt-memo endpoint tests (contract-additive, same guards/token/HTTPS):
// GET /debts (filters), POST /debts (201 + Location + 422 matrix),
// POST /debts/:id/payments (201, 422 overpay + remaining_paise, 404).
// Real HTTPS GETs/POSTs against a testMode server on 127.0.0.1 with a
// seeded ffi in-memory DB — mirrors lan_api_test.dart patterns.
import 'dart:convert';
import 'dart:io';

import 'package:finance_tracker/core/database.dart';
import 'package:finance_tracker/data/repos/debt_repo.dart';
import 'package:finance_tracker/data/repos/export_repo.dart';
import 'package:finance_tracker/data/repos/stats_repo.dart';
import 'package:finance_tracker/data/repos/txn_repo.dart';
import 'package:finance_tracker/data/repos/wallet_repo.dart';
import 'package:finance_tracker/features/lan_api/lan_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  required String token,
}) async {
  final uri = Uri.parse(
    '$base$path${path.contains('?') ? '&' : '?'}token=$token',
  );
  final req = await client.getUrl(uri);
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  return _Resp(resp.statusCode, body, resp.headers);
}

Future<_Resp> _post(
  HttpClient client,
  String base,
  String path,
  Map<String, Object?> body, {
  required String token,
}) async {
  final req =
      await client.postUrl(Uri.parse('$base$path?token=$token'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final resp = await req.close();
  final text = await resp.transform(utf8.decoder).join();
  return _Resp(resp.statusCode, text, resp.headers);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tlsDir;
  setUpAll(() async {
    tlsDir = await Directory.systemTemp.createTemp('lan_debt_tls_');
  });
  tearDownAll(() async {
    try {
      await tlsDir.delete(recursive: true);
    } catch (_) {}
  });

  group('lan_server debts (testMode, real HTTPS)', () {
    late Database db;
    late LanApiServer server;
    late HttpClient client;
    late String base;
    var mutated = 0;

    setUpAll(() async {
      db = await openAppDatabase(path: inMemoryDatabasePath);
      final debts = DebtRepo(db);
      final oweId = await debts.addDebt(
        person: 'Rahul',
        amountPaise: 10000,
        direction: 'owe',
      );
      await debts.addPayment(debtId: oweId, amountPaise: 2500);
      await debts.addDebt(
        person: 'Priya',
        amountPaise: 20000,
        direction: 'lent',
      );
      server = LanApiServer(
        wallets: WalletRepo(db),
        txns: TxnRepo(db),
        stats: StatsRepo(db),
        exports: ExportRepo(db),
        debts: DebtRepo(db),
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

    test('GET /debts lists with remaining math + filters', () async {
      var r = await _get(client, base, '/debts', token: server.token);
      expect(r.status, 200);
      var data = r.json['data'] as List;
      expect(data.length, 2);
      final rahul = (data.cast<Map<String, dynamic>>())
          .firstWhere((d) => d['person'] == 'Rahul');
      expect(rahul['amount_paise'], 10000);
      expect(rahul['amount_inr'], '100.00');
      expect(rahul['remaining_paise'], 7500);
      expect(rahul['remaining_inr'], '75.00');
      expect(rahul['direction'], 'owe');
      expect(rahul['status'], 'open');

      r = await _get(
        client,
        base,
        '/debts?direction=lent',
        token: server.token,
      );
      expect(r.status, 200);
      expect((r.json['data'] as List).length, 1);

      r = await _get(
        client,
        base,
        '/debts?status=settled',
        token: server.token,
      );
      expect(r.status, 200);
      expect((r.json['data'] as List), isEmpty);

      r = await _get(
        client,
        base,
        '/debts?direction=owed',
        token: server.token,
      );
      expect(r.status, 422);
      expect(r.json['error']['code'], 'invalid_direction');

      r = await _get(
        client,
        base,
        '/debts?status=done',
        token: server.token,
      );
      expect(r.status, 422);
      expect(r.json['error']['code'], 'invalid_status');
    });

    test('GET /debts requires auth', () async {
      final req =
          await client.getUrl(Uri.parse('$base/debts'));
      final resp = await req.close();
      await resp.transform(utf8.decoder).join();
      expect(resp.statusCode, 401);
    });

    test('POST /debts happy path: 201 + Location', () async {
      final r = await _post(
        client,
        base,
        '/debts',
        <String, Object?>{
          'person': 'LAN friend',
          'amount_inr': '12.50',
          'direction': 'lent',
          'note': 'via api',
        },
        token: server.token,
      );
      expect(r.status, 201);
      expect(r.headers.value('location'), startsWith('/api/v1/debts/'));
      final data = r.json['data'] as Map<String, dynamic>;
      expect(data['person'], 'LAN friend');
      expect(data['amount_paise'], 1250);
      expect(data['remaining_paise'], 1250);
      expect(data['note'], 'via api');
      expect(mutated, 1);
    });

    test('POST /debts 422 matrix', () async {
      Future<_Resp> bad(Map<String, Object?> body) =>
          _post(client, base, '/debts', body, token: server.token);

      var r = await bad(<String, Object?>{
        'amount_paise': 100,
        'direction': 'owe',
      });
      expect(r.status, 422);
      expect(r.json['error']['code'], 'missing_person');

      r = await bad(<String, Object?>{
        'person': '  ',
        'amount_paise': 100,
        'direction': 'owe',
      });
      expect(r.status, 422);

      r = await bad(<String, Object?>{
        'person': 'X',
        'amount_paise': 0,
        'direction': 'owe',
      });
      expect(r.status, 422);
      expect(r.json['error']['code'], 'invalid_amount');

      r = await bad(<String, Object?>{
        'person': 'X',
        'direction': 'owe',
      });
      expect(r.status, 422);

      r = await bad(<String, Object?>{
        'person': 'X',
        'amount_paise': 100,
        'direction': 'owed',
      });
      expect(r.status, 422);
      expect(r.json['error']['code'], 'invalid_direction');

      expect(mutated, 1); // failures never refresh
    });

    test('POST /debts/:id/payments happy + overpay 422 + 404', () async {
      // Rahul owes 10000, paid 2500 → remaining 7500.
      final list = await _get(client, base, '/debts', token: server.token);
      final rahul = (list.json['data'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => d['person'] == 'Rahul');
      final id = rahul['id'] as int;

      var r = await _post(
        client,
        base,
        '/debts/$id/payments',
        <String, Object?>{'amount_paise': 5000},
        token: server.token,
      );
      expect(r.status, 201);
      final data = r.json['data'] as Map<String, dynamic>;
      expect(data['payment_id'] is int, true);
      expect(
        (data['debt'] as Map<String, dynamic>)['remaining_paise'],
        2500,
      );
      expect(mutated, 2);

      // Overpay: remaining is 2500.
      r = await _post(
        client,
        base,
        '/debts/$id/payments',
        <String, Object?>{'amount_paise': 2501},
        token: server.token,
      );
      expect(r.status, 422);
      expect(r.json['error']['code'], 'overpay');
      expect(r.json['error']['remaining_paise'], 2500);

      // Unknown debt.
      r = await _post(
        client,
        base,
        '/debts/99999/payments',
        <String, Object?>{'amount_paise': 100},
        token: server.token,
      );
      expect(r.status, 404);
      expect(r.json['error']['code'], 'unknown_debt');

      expect(mutated, 2); // failures never refresh
    });
  });
}

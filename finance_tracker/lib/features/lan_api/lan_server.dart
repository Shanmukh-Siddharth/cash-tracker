/// LAN-only HTTP API (contract: `docs/API.md` v2).
///
/// Phone hosts a tiny server ONLY while the LAN API screen is visible.
/// Binds the WiFi IPv4 via TLS (self-signed, always-on — never plain HTTP);
/// loopback only via [testMode]. Reads existing repos — no new DB code
/// except [TxnRepo.getTxn] (echo-back for POST).
///
/// Middleware order (per contract): cors (preflight first, no auth) →
/// lanGuard (403) → token (401) → rate limit 60/min/IP (429 + Retry-After)
/// → router. Writes reuse txn_repo (same validation incl. overspend).
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../core/app_version.dart';
import '../../core/money.dart';
import '../../data/categories.dart';
import '../../data/models/transaction.dart';
import '../../data/repos/debt_repo.dart';
import '../../data/repos/export_repo.dart';
import '../../data/repos/stats_repo.dart';
import '../../data/repos/txn_repo.dart';
import '../../data/repos/wallet_repo.dart';
import 'lan_cert.dart';
import 'lan_guard.dart';
import 'lan_token.dart';

/// Paise int → "123.45" display string (integer math, no float).
String _inr(int paise) {
  final rupees = paise ~/ 100;
  final frac = (paise % 100).toString().padLeft(2, '0');
  return '$rupees.$frac';
}

Response _ok(Object data, [Map<String, Object>? meta]) => Response.ok(
  jsonEncode(
    meta == null
        ? <String, Object?>{'data': data}
        : <String, Object?>{'data': data, 'meta': meta},
  ),
  headers: const {'Content-Type': 'application/json'},
);

Response _err(
  int status,
  String code,
  String message, {
  Map<String, String>? headers,
  Map<String, Object?>? extra,
}) {
  final all = <String, String>{'Content-Type': 'application/json'};
  if (headers != null) all.addAll(headers);
  return Response(
    status,
    body: jsonEncode(
      <String, Object?>{
        'error': <String, Object?>{
          'code': code,
          'message': message,
          ...?extra,
        },
      },
    ),
    headers: all,
  );
}

Map<String, Object?> _txnJson(Txn t) => <String, Object?>{
  'id': t.id,
  'wallet_id': t.walletId,
  'wallet': t.walletName,
  'type': txnTypeToString(t.type),
  'amount_paise': t.amountPaise,
  'amount_inr': _inr(t.amountPaise),
  'from_for': t.fromFor,
  'note': t.note,
  'category': t.category,
  'date': t.date,
  'created_at': t.createdAt,
};

/// Track-only debt memo JSON (amounts in paise + display strings).
Map<String, Object?> _debtJson(Debt d) => <String, Object?>{
  'id': d.id,
  'person': d.person,
  'amount_paise': d.amountPaise,
  'amount_inr': _inr(d.amountPaise),
  'direction': d.direction,
  'note': d.note,
  'date': d.date,
  'status': d.status,
  'paid_paise': d.paidPaise,
  'paid_inr': _inr(d.paidPaise),
  'remaining_paise': d.remainingPaise,
  'remaining_inr': _inr(d.remainingPaise),
  'created_at': d.createdAt,
};

String _clientIp(Request req) {
  final info = req.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return '';
}

class LanApiServer {
  final WalletRepo wallets;
  final TxnRepo txns;
  final StatsRepo stats;
  final ExportRepo exports;

  /// Track-only debt repo (v3). Optional so older call sites keep working;
  /// debt routes answer 500 when absent.
  final DebtRepo? debts;

  /// Called after every successful POST so the UI can `refreshAfterMutation`.
  final void Function()? onMutated;

  /// Overrides the TLS PEM directory (tests pass a temp dir so the real app
  /// documents dir is untouched and keygen happens once per dir).
  final Directory? certDirectory;

  HttpServer? _server;
  final LanToken _tokens = LanToken();
  final Map<String, List<DateTime>> _hits = <String, List<DateTime>>{};
  String _wifiIp = '';
  bool _testMode = false;

  LanApiServer({
    required this.wallets,
    required this.txns,
    required this.stats,
    required this.exports,
    this.debts,
    this.onMutated,
    this.certDirectory,
  });

  bool get isRunning => _server != null;

  /// Fresh 6-char token for this run (empty when stopped).
  String get token => isRunning ? _tokens.current : '';

  /// Actual bound port (differs from requested when `port: 0` in tests).
  int get port => _server?.port ?? 0;

  String get url => 'https://$_wifiIp:$port/api/v1';

  /// Starts the TLS server bound to [wifiIp] ONLY. Throws [ArgumentError]
  /// for `0.0.0.0`, or for loopback without [testMode].
  Future<void> start({
    required String wifiIp,
    int port = 8080,
    bool testMode = false,
  }) async {
    if (isRunning) return;
    final addr = InternetAddress.tryParse(wifiIp);
    if (addr == null) {
      throw ArgumentError('Bad WiFi IP: $wifiIp');
    }
    if (wifiIp == '0.0.0.0' || wifiIp == '::') {
      throw ArgumentError('Refusing wildcard bind — LAN IP only');
    }
    final isLoopback = addr.type == InternetAddressType.IPv4
        ? wifiIp.startsWith('127.')
        : addr.isLoopback;
    if (isLoopback && !testMode) {
      throw ArgumentError('Loopback bind is test-only');
    }
    _wifiIp = wifiIp;
    _testMode = testMode;
    _tokens.rotate();
    _hits.clear();

    final router = _buildRouter();
    final handler = const Pipeline()
        .addMiddleware(_cors)
        .addMiddleware(_lanGuard)
        .addMiddleware(_auth)
        .addMiddleware(_rateLimit)
        .addHandler(router.call);
    final context = await loadOrCreateLanSecurityContext(
      directory: certDirectory,
    );
    final raw = await HttpServer.bindSecure(addr, port, context);
    _server = raw;
    shelf_io.serveRequests(raw, handler);
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _hits.clear();
    if (s != null) await s.close(force: true);
  }

  // -- middleware (order matters: cors → guard → auth → rate limit) --

  /// Minimal LAN CORS (contract §7): answers OPTIONS preflights WITHOUT
  /// auth (browsers never send auth on preflight) and stamps
  /// `Access-Control-Allow-Origin: *` on every real response. Token stays
  /// mandatory — origin * is safe here (LAN + token + subnet guard).
  Handler _cors(Handler inner) {
    return (Request req) async {
      if (req.method == 'OPTIONS') {
        return Response(
          204,
          headers: const {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Authorization, Content-Type',
            'Access-Control-Max-Age': '86400',
          },
        );
      }
      final res = await inner(req);
      return res.change(headers: const {'Access-Control-Allow-Origin': '*'});
    };
  }

  Handler _lanGuard(Handler inner) {
    return (Request req) async {
      if (_testMode) return inner(req);
      final client = _clientIp(req);
      if (!isPrivateIp(client) || !isSameLan(_wifiIp, client)) {
        return _err(
          403,
          'subnet_forbidden',
          'Client is outside the server subnet',
        );
      }
      return inner(req);
    };
  }

  Handler _auth(Handler inner) {
    return (Request req) async {
      final header = req.headers['authorization'];
      String? candidate;
      if (header != null && header.toLowerCase().startsWith('bearer ')) {
        candidate = header.substring(7).trim();
      }
      // Header wins; query token is the browser-easy fallback.
      candidate ??= req.url.queryParameters['token'];
      if (!_tokens.validate(candidate)) {
        return _err(401, 'unauthorized', 'Valid token required');
      }
      return inner(req);
    };
  }

  Handler _rateLimit(Handler inner) {
    return (Request req) async {
      final ip = _clientIp(req);
      final now = DateTime.now();
      final hits = _hits.putIfAbsent(ip, () => <DateTime>[]);
      hits.removeWhere((t) => now.difference(t).inSeconds >= 60);
      if (hits.length >= 60) {
        final retry = (60 - now.difference(hits.first).inSeconds).clamp(1, 60);
        return _err(
          429,
          'rate_limited',
          'Slow down — 60 requests per minute',
          headers: {'Retry-After': '$retry'},
        );
      }
      hits.add(now);
      return inner(req);
    };
  }

  // -- router --

  Router _buildRouter() {
    final router = Router();

    Future<Response> safe(Future<Response> Function() fn) async {
      try {
        return await fn();
      } catch (_) {
        // 500 never leaks internals (contract §4).
        return _err(500, 'internal', 'Something went wrong');
      }
    }

    router.get('/api/v1/health', (Request req) {
      return safe(() async {
        return _ok(<String, Object?>{
          'status': 'ok',
          'version': appVersion,
          'lan_only': true,
        });
      });
    });

    router.get('/api/v1/wallets', (Request req) {
      return safe(() async {
        final list = await wallets.listWallets();
        return _ok([
          for (final w in list)
            <String, Object?>{
              'id': w.id,
              'name': w.name,
              'balance_paise': w.balancePaise,
              'balance_inr': _inr(w.balancePaise),
            },
        ]);
      });
    });

    router.get('/api/v1/summary', (Request req) {
      return safe(() async {
        final list = await wallets.listWallets();
        final total = list.fold<int>(0, (s, w) => s + w.balancePaise);
        final today = await txns.todayTotals();
        return _ok(<String, Object?>{
          'total_paise': total,
          'total_inr': _inr(total),
          'today': <String, Object?>{
            'income_paise': today.incomePaise,
            'expense_paise': today.expensePaise,
            'income_inr': _inr(today.incomePaise),
            'expense_inr': _inr(today.expensePaise),
          },
        });
      });
    });

    router.get('/api/v1/transactions', (Request req) {
      return safe(() async {
        final q = req.url.queryParameters;
        final page = int.tryParse(q['page'] ?? '1') ?? 0;
        final perPage = int.tryParse(q['per_page'] ?? '20') ?? 0;
        if (page < 1 || perPage < 1 || perPage > 100) {
          return _err(
            400,
            'invalid_pagination',
            'page >= 1 and 1 <= per_page <= 100 required',
          );
        }
        final typeRaw = q['type'];
        TxnType? type;
        if (typeRaw != null && typeRaw.isNotEmpty) {
          if (typeRaw != 'income' && typeRaw != 'expense') {
            return _err(
              422,
              'invalid_type',
              'type must be income or expense',
            );
          }
          type = txnTypeFromString(typeRaw);
        }
        int? walletId;
        if (q['wallet_id'] != null && q['wallet_id']!.isNotEmpty) {
          walletId = int.tryParse(q['wallet_id']!);
          if (walletId == null) {
            return _err(400, 'invalid_wallet', 'wallet_id must be an int');
          }
        }
        final needle = (q['q'] ?? '').trim().toLowerCase();

        var all = await txns.allTxns(); // newest-first
        if (type != null) {
          all = all.where((t) => t.type == type).toList();
        }
        if (walletId != null) {
          all = all.where((t) => t.walletId == walletId).toList();
        }
        if (needle.isNotEmpty) {
          all = all
              .where(
                (t) =>
                    t.fromFor.toLowerCase().contains(needle) ||
                    (t.note?.toLowerCase().contains(needle) ?? false) ||
                    t.category.toLowerCase().contains(needle),
              )
              .toList();
        }
        final total = all.length;
        final start = (page - 1) * perPage;
        final items = start >= total
            ? <Txn>[]
            : all.sublist(start, (start + perPage).clamp(0, total));
        return _ok(
          [for (final t in items) _txnJson(t)],
          <String, Object>{'total': total, 'page': page, 'per_page': perPage},
        );
      });
    });

    // The single v2 write endpoint (contract §5b): reuses
    // txn_repo.addIncome/addExpense, so validation + balance semantics are
    // identical to the app UI. Counts toward the same 60/min rate limit.
    router.post('/api/v1/transactions', (Request req) {
      return safe(() async {
        Map<String, Object?> body;
        try {
          final decoded = jsonDecode(await req.readAsString());
          if (decoded is! Map) {
            return _err(400, 'malformed_json', 'Body must be a JSON object');
          }
          body = decoded.map(
            (k, v) => MapEntry<String, Object?>('$k', v as Object?),
          );
        } catch (_) {
          return _err(400, 'malformed_json', 'Body must be a JSON object');
        }

        final typeRaw = body['type'];
        if (typeRaw != 'income' && typeRaw != 'expense') {
          return _err(
            422,
            'invalid_type',
            'type must be "income" or "expense"',
          );
        }

        // Wallet: wallet_id (int) wins; else wallet name (case-insensitive).
        int? walletId;
        final widRaw = body['wallet_id'];
        final walletNameRaw = body['wallet'];
        if (widRaw != null) {
          walletId = widRaw is int ? widRaw : int.tryParse('$widRaw');
          if (walletId == null) {
            return _err(400, 'invalid_wallet', 'wallet_id must be an int');
          }
        } else if (walletNameRaw is String &&
            walletNameRaw.trim().isNotEmpty) {
          final needle = walletNameRaw.trim().toLowerCase();
          final all = await wallets.listWallets();
          final match = all
              .where((w) => w.name.toLowerCase() == needle)
              .toList();
          if (match.isEmpty) {
            return _err(
              404,
              'unknown_wallet',
              'No wallet named "${walletNameRaw.trim()}"',
            );
          }
          walletId = match.first.id!;
        } else {
          return _err(
            422,
            'missing_wallet',
            'wallet_id or wallet is required',
          );
        }

        // Amount: amount_paise wins if both; else amount_inr ("12.50").
        int? paise;
        if (body['amount_paise'] != null) {
          final raw = body['amount_paise'];
          paise = raw is int ? raw : int.tryParse('$raw');
        } else if (body['amount_inr'] != null) {
          paise = parseToPaise('${body['amount_inr']}');
        }
        if (paise == null || paise <= 0) {
          return _err(
            422,
            'invalid_amount',
            'amount_paise (>0 int) or amount_inr ("12.50") required',
          );
        }

        final fromFor = '${body['from_for'] ?? ''}'.trim();
        if (fromFor.isEmpty) {
          return _err(422, 'missing_from_for', 'from_for is required');
        }
        // Note is optional: missing/blank → stored null (repo normalizes),
        // never 422.
        final noteRaw = body['note'];
        final String? note = noteRaw == null || '$noteRaw'.trim().isEmpty
            ? null
            : '$noteRaw'.trim();
        // Category is optional: blank/missing → list-tail default for the
        // type; unknown → 422 invalid_category.
        final catRaw = body['category'];
        final category = catRaw == null ? null : '$catRaw'.trim().isEmpty
            ? null
            : '$catRaw'.trim();
        final isIncome = typeRaw == 'income';
        if (category != null &&
            !isValidCategory(category, income: isIncome)) {
          return _err(
            422,
            'invalid_category',
            'Unknown category "$category" for ${isIncome ? 'income' : 'expense'}',
          );
        }

        try {
          final id = typeRaw == 'income'
              ? await txns.addIncome(
                  walletId: walletId,
                  amountPaise: paise,
                  fromFor: fromFor,
                  note: note,
                  category: category,
                )
              : await txns.addExpense(
                  walletId: walletId,
                  amountPaise: paise,
                  fromFor: fromFor,
                  note: note,
                  category: category,
                );
          final created = await txns.getTxn(id);
          if (created == null) {
            return _err(500, 'internal', 'Something went wrong');
          }
          onMutated?.call();
          return Response(
            201,
            body: jsonEncode(<String, Object?>{'data': _txnJson(created)}),
            headers: {
              'Content-Type': 'application/json',
              'Location': '/api/v1/transactions/$id',
            },
          );
        } on InsufficientBalance catch (e) {
          // Same repo semantics as the UI overspend block, plus the balance
          // so the caller can show "Available: ₹X".
          return _err(
            422,
            'insufficient_balance',
            e.toString(),
            extra: <String, Object?>{'available_paise': e.availablePaise},
          );
        } on ArgumentError catch (e) {
          final msg = e.message?.toString() ?? '$e';
          if (msg.startsWith('Unknown wallet')) {
            return _err(404, 'unknown_wallet', msg);
          }
          if (msg.startsWith('Unknown category')) {
            return _err(422, 'invalid_category', msg);
          }
          return _err(422, 'invalid_input', msg);
        }
      });
    });

    router.get('/api/v1/stats/daily', (Request req) {
      return safe(() async {
        final days =
            int.tryParse(req.url.queryParameters['days'] ?? '120') ?? 0;
        if (days < 1) {
          return _err(400, 'invalid_days', 'days must be >= 1');
        }
        final map = await stats.dailyExpenses(days: days);
        final keys = map.keys.toList()..sort();
        String dayKey(DateTime d) =>
            '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        return _ok([
          for (final d in keys)
            <String, Object?>{
              'date': dayKey(d),
              'expense_paise': map[d]!.totalPaise,
              'expense_inr': _inr(map[d]!.totalPaise),
            },
        ]);
      });
    });

    router.get('/api/v1/stats/monthly', (Request req) {
      return safe(() async {
        final months =
            int.tryParse(req.url.queryParameters['months'] ?? '6') ?? 0;
        if (months < 1) {
          return _err(400, 'invalid_months', 'months must be >= 1');
        }
        final pairs = await stats.monthlyPairs(months);
        // Keys mirror StatsRepo windowing: current month last, oldest first.
        final now = DateTime.now();
        final start = DateTime(now.year, now.month - months + 1, 1);
        return _ok([
          for (var i = 0; i < pairs.length; i++)
            <String, Object?>{
              'month':
                  '${DateTime(start.year, start.month + i, 1).year.toString().padLeft(4, '0')}-'
                  '${DateTime(start.year, start.month + i, 1).month.toString().padLeft(2, '0')}',
              'label': pairs[i].label,
              'income_paise': pairs[i].incomePaise,
              'expense_paise': pairs[i].expensePaise,
              'income_inr': _inr(pairs[i].incomePaise),
              'expense_inr': _inr(pairs[i].expensePaise),
            },
        ]);
      });
    });

    router.get('/api/v1/stats/share', (Request req) {
      return safe(() async {
        final byWallet = await stats.expenseShareByWallet();
        final totals = await stats.incomeVsExpense();
        return _ok(<String, Object?>{
          'by_wallet': [
            for (final s in byWallet)
              <String, Object?>{
                'wallet': s.walletName,
                'wallet_id': s.walletId,
                'expense_paise': s.expensePaise,
                'expense_inr': _inr(s.expensePaise),
              },
          ],
          'income_paise': totals.incomePaise,
          'expense_paise': totals.expensePaise,
          'income_inr': _inr(totals.incomePaise),
          'expense_inr': _inr(totals.expensePaise),
        });
      });
    });

    router.get('/api/v1/export.csv', (Request req) {
      return safe(() async {
        final csv = await exports.buildCsv();
        final stamp = DateTime.now().toIso8601String().replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );
        return Response.ok(
          csv,
          headers: {
            'Content-Type': 'text/csv',
            'Content-Disposition':
                'attachment; filename="finance_export_$stamp.csv"',
          },
        );
      });
    });

    router.get('/api/v1/export.json', (Request req) {
      return safe(() async {
        final map = await exports.buildJson();
        return Response.ok(
          jsonEncode(map),
          headers: {'Content-Type': 'application/json'},
        );
      });
    });

    // -- v3 debt-memo endpoints (contract-additive): track-only, never
    // touches wallets/transactions. Same guards/token/HTTPS/rate limit. --
    {
      router.get('/api/v1/debts', (Request req) {
        return safe(() async {
          final repo = debts;
          if (repo == null) {
            return _err(500, 'internal', 'Something went wrong');
          }
          final q = req.url.queryParameters;
          final dirRaw = q['direction'];
          final statusRaw = q['status'];
          if (dirRaw != null &&
              dirRaw.isNotEmpty &&
              !isValidDebtDirection(dirRaw)) {
            return _err(
              422,
              'invalid_direction',
              'direction must be "owe" or "lent"',
            );
          }
          if (statusRaw != null &&
              statusRaw.isNotEmpty &&
              !isValidDebtStatus(statusRaw)) {
            return _err(
              422,
              'invalid_status',
              'status must be "open" or "settled"',
            );
          }
          final list = await repo.listDebts(
            direction:
                dirRaw == null || dirRaw.isEmpty ? null : dirRaw,
            status:
                statusRaw == null || statusRaw.isEmpty ? null : statusRaw,
          );
          return _ok([for (final d in list) _debtJson(d)]);
        });
      });

      router.post('/api/v1/debts', (Request req) {
        return safe(() async {
          final repo = debts;
          if (repo == null) {
            return _err(500, 'internal', 'Something went wrong');
          }
          Map<String, Object?> body;
          try {
            final decoded = jsonDecode(await req.readAsString());
            if (decoded is! Map) {
              return _err(400, 'malformed_json', 'Body must be a JSON object');
            }
            body = decoded.map(
              (k, v) => MapEntry<String, Object?>('$k', v as Object?),
            );
          } catch (_) {
            return _err(400, 'malformed_json', 'Body must be a JSON object');
          }
          final person = '${body['person'] ?? ''}'.trim();
          if (person.isEmpty) {
            return _err(422, 'missing_person', 'person is required');
          }
          int? paise;
          if (body['amount_paise'] != null) {
            final raw = body['amount_paise'];
            paise = raw is int ? raw : int.tryParse('$raw');
          } else if (body['amount_inr'] != null) {
            paise = parseToPaise('${body['amount_inr']}');
          }
          if (paise == null || paise <= 0) {
            return _err(
              422,
              'invalid_amount',
              'amount_paise (>0 int) or amount_inr ("12.50") required',
            );
          }
          final dirRaw = '${body['direction'] ?? ''}'.trim();
          if (!isValidDebtDirection(dirRaw)) {
            return _err(
              422,
              'invalid_direction',
              'direction must be "owe" or "lent"',
            );
          }
          final noteRaw = body['note'];
          final String? note = noteRaw == null || '$noteRaw'.trim().isEmpty
              ? null
              : '$noteRaw'.trim();
          try {
            final id = await repo.addDebt(
              person: person,
              amountPaise: paise,
              direction: dirRaw,
              note: note,
            );
            final created = await repo.getDebt(id);
            if (created == null) {
              return _err(500, 'internal', 'Something went wrong');
            }
            onMutated?.call();
            return Response(
              201,
              body: jsonEncode(<String, Object?>{'data': _debtJson(created)}),
              headers: {
                'Content-Type': 'application/json',
                'Location': '/api/v1/debts/$id',
              },
            );
          } on ArgumentError catch (e) {
            return _err(
              422,
              'invalid_input',
              e.message?.toString() ?? '$e',
            );
          }
        });
      });

      router.post('/api/v1/debts/<id>/payments', (
        Request req,
        String id,
      ) {
        return safe(() async {
          final repo = debts;
          if (repo == null) {
            return _err(500, 'internal', 'Something went wrong');
          }
          final debtId = int.tryParse(id);
          if (debtId == null) {
            return _err(404, 'unknown_debt', 'No debt with id "$id"');
          }
          Map<String, Object?> body;
          try {
            final decoded = jsonDecode(await req.readAsString());
            if (decoded is! Map) {
              return _err(400, 'malformed_json', 'Body must be a JSON object');
            }
            body = decoded.map(
              (k, v) => MapEntry<String, Object?>('$k', v as Object?),
            );
          } catch (_) {
            return _err(400, 'malformed_json', 'Body must be a JSON object');
          }
          int? paise;
          if (body['amount_paise'] != null) {
            final raw = body['amount_paise'];
            paise = raw is int ? raw : int.tryParse('$raw');
          } else if (body['amount_inr'] != null) {
            paise = parseToPaise('${body['amount_inr']}');
          }
          if (paise == null || paise <= 0) {
            return _err(
              422,
              'invalid_amount',
              'amount_paise (>0 int) or amount_inr ("12.50") required',
            );
          }
          final noteRaw = body['note'];
          final String? note = noteRaw == null || '$noteRaw'.trim().isEmpty
              ? null
              : '$noteRaw'.trim();
          try {
            final payId = await repo.addPayment(
              debtId: debtId,
              amountPaise: paise,
              note: note,
            );
            final updated = await repo.getDebt(debtId);
            onMutated?.call();
            return Response(
              201,
              body: jsonEncode(<String, Object?>{
                'data': <String, Object?>{
                  'payment_id': payId,
                  'debt': updated == null ? null : _debtJson(updated),
                },
              }),
              headers: {'Content-Type': 'application/json'},
            );
          } on DebtOverpay catch (e) {
            return _err(
              422,
              'overpay',
              'Payment exceeds remaining balance',
              extra: <String, Object?>{'remaining_paise': e.remaining},
            );
          } on ArgumentError catch (e) {
            final msg = e.message?.toString() ?? '$e';
            if (msg.startsWith('Unknown debt')) {
              return _err(404, 'unknown_debt', msg);
            }
            return _err(422, 'invalid_input', msg);
          }
        });
      });
    }

    // JSON 404 for anything else under the API (contract envelope).
    router.all('/api/v1/<rest|.*>', (Request req) {
      return _err(404, 'not_found', 'Unknown endpoint');
    });

    return router;
  }
}

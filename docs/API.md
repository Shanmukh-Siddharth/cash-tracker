# API.md — LAN-Only API (Contract v3)

**Status:** Canonical contract (contract-first: code + tests verify against this file).
**Base:** `https://<phone-lan-ip>:8080/api/v1` · JSON only · read endpoints + one write endpoint (`POST /transactions`).
**Rule:** works ONLY when both devices are on the same WiFi/LAN. Server binds the WiFi IPv4, rejects anything outside the server's /24 subnet AND outside private ranges. Token required on every call.
**Changed 2026-10-08:** v1 → v2: HTTPS always-on (self-signed), `POST /transactions` (contract-additive), minimal CORS, QR connect payload. All v1 read endpoints byte-identical.
**Changed 2026-10-08:** v2 → v3: `category` everywhere (GET items, POST, exports), `note` REQUIRED on POST, background serving until Stop/kill (foreground service, owner-accepted tradeoff).
**Changed 2026-10-08:** v3 → v4: track-only Debts (`GET /debts`, `POST /debts`, `POST /debts/:id/payments` — never touch balances); export JSON `schema_version: 3`; reset wipes PIN+prefs (fresh setup); `allowBackup=false`.

## 1. Lifecycle (offline-first)

- Server is OFF by default. Settings → **LAN API** button → app checks WiFi connected (via connectivity). If NO network: popup "Connect to WiFi first — LAN API needs both devices on the same network" and server does NOT start.
- On start: fresh random 6-char token (in-memory only, shown once with copy button) + URL `https://<ip>:8080`. A low-importance foreground service ("NEB LAN API", dataSync) keeps the server alive when minimized/backgrounded or screen-locked. It runs until the user taps **Stop** or the process is killed/force-closed (service NOT sticky — dies with task removal). Leaving the screen no longer stops it; reopening re-attaches. No internet needed — WiFi radio only.
- TLS identity is generated ONCE (first start) and reused: RSA-2048 + self-signed cert (CN=`finance-tracker.local`, O=`Personal Finance Tracker`, 10-year validity), PEM key+cert persisted in the app documents dir (`lan_api_key.pem`, `lan_api_cert.pem`).

## 2. Auth

- Every request: `Authorization: Bearer <token>` (browser-easy alt: `?token=<token>`; header wins if both). CORS preflights (`OPTIONS`) are exempt (browsers never send auth on preflight).
- Failures: `401 {error:{code:"unauthorized"}}` missing/bad token; `403 {code:"subnet_forbidden"}` client IP outside server /24 or non-private.

## 3. HTTPS (always-on since v2)

- Scheme is ALWAYS `https://`. There is no plain-HTTP mode: the server binds via `HttpServer.bindSecure` only, so a plain `http://` request never gets a response (connection closed/hangup during handshake).
- The cert is self-signed (LAN-only, no public CA possible for a phone IP), so browsers/clients warn on first visit: Advanced → Proceed. Safe because: your own phone, LAN only, token still required.
- Test clients must accept the self-signed cert (`HttpClient.badCertificateCallback = true` in `testMode`).

## 4. Envelopes

Success: `{ "data": <resource|array>, "meta": {...}? }`
Collection: `{ "data": [...], "meta": { "total": n, "page": p, "per_page": pp } }`
Error: `{ "error": { "code": "<snake>", "message": "<human>", ...extra? } }` with proper HTTP status (200/201/204-preflight/400/401/403/404/422/429/500-never-leaks).

Money: amounts in **paise ints** (`amount_paise`) + display string (`amount_inr: "123.45"`). Dates ISO-8601. Wallet ids ints.

## 5. Endpoints

| Method | Path | Query / Body | Returns |
|---|---|---|---|
| GET | `/health` | — | `{data:{status:"ok", version:"V.0.0", lan_only:true}}` (auth required) |
| GET | `/wallets` | — | `{data:[{id,name,balance_paise,balance_inr}]}` |
| GET | `/summary` | — | `{data:{total_paise,total_inr,today:{income_paise,expense_paise}}}` |
| GET | `/transactions` | `page,per_page(≤100),type=income\|expense,wallet_id,q` | newest-first page + meta; `q` matches from_for + note + **category**; items include `category` |
| POST | `/transactions` | JSON body (see §5b) | `201 + Location: /api/v1/transactions/:id` + `{data:{...txn...}}` |
| GET | `/stats/daily` | `days=120` | `{data:[{date,expense_paise}]}` ascending |
| GET | `/stats/monthly` | `months=6` | `{data:[{month:"2026-10",income_paise,expense_paise}]}` |
| GET | `/stats/share` | — | `{data:{by_wallet:[{wallet,expense_paise}],income_paise,expense_paise}}` |
| GET | `/export.csv` | — | CSV download (`finance_export_*.csv` columns per PRD + `category` LAST) |
| GET | `/export.json` | — | backup JSON (`schema_version: 2`, transactions include `category`) |
| OPTIONS | any `/api/v1/*` | preflight (no auth) | `204` + CORS headers (see §7) |
| GET | `/debts` | `direction=owe\|lent, status=open\|settled` | `{data:[{id,person,amount_paise,remaining_paise,direction,note,date,status}]}` |
| POST | `/debts` | `{person required, amount_paise\|amount_inr >0, direction owe\|lent, note?, date?}` | `201 + Location` (422 `missing_person`/`invalid_amount`/`invalid_direction`) |
| POST | `/debts/:id/payments` | `{amount_paise\|amount_inr >0, note?}` | `201` (422 `overpay` + `remaining_paise`; 404 `unknown_debt`) |

Rate limit: 60 req/min per IP → `429 + Retry-After`. Writes count toward the same bucket.

### 5b. POST /transactions (v2, contract-additive)

Request (JSON object, all keys snake_case):

```json
{
  "type": "income | expense (required)",
  "wallet_id": 1,
  "wallet": "Cash (alt: wallet name, case-insensitive; wallet_id wins if both)",
  "amount_paise": 1250,
  "amount_inr": "12.50 (alt: paise wins if both)",
  "from_for": "Salary / Chai (required, non-empty)",
  "note": "optional one-liner (v3: rule removed by owner — missing/blank stored as null)",
  "category": "optional; expense list [Food, Travel, Fuel, Shopping, Bills, Mobile Recharge, Health, Entertainment, Education, Rent, Subscriptions, Miscellaneous] or income list [Salary, Refund, Gift, Bonus, Other] matched to type; omitted/blank → Miscellaneous (expense) / Other (income)"
}
```

- Writes reuse `txn_repo.addIncome` / `addExpense` — identical validation and balance semantics as the app UI (expense blocked on overspend, single-DB-transaction writes).
- After a successful write the app refreshes Home/History/Stats via `refreshAfterMutation`.
- Success: `201 Created`, `Location: /api/v1/transactions/<id>`, body `{data:{id,wallet_id,wallet,type,amount_paise,amount_inr,from_for,note,category,date,created_at}}` (same txn shape as `GET /transactions` items).
- Errors:
  - `400 malformed_json` — body is not a JSON object; `400 invalid_wallet` — `wallet_id` is not an int.
  - `422 invalid_type` — `type` missing or not `income`/`expense`; `422 missing_wallet` — neither `wallet_id` nor `wallet` given; `422 invalid_amount` — no positive amount (`amount_paise > 0` int, or `amount_inr` like `"12.50"`); `422 missing_from_for` — `from_for` empty; `422 invalid_category` — unknown category for the type (v3); `422 invalid_input` — other repo validation.
  - `422 insufficient_balance` — expense exceeds wallet balance; the error object ALSO carries `available_paise` (int): `{error:{code:"insufficient_balance", message:"…", available_paise:7200}}`.
  - `404 unknown_wallet` — `wallet_id` / `wallet` name matches nothing.

## 6. LAN Guard (exact)

1. Bind `InternetAddress wifiIp` (from WiFi interface) port 8080 via `bindSecure`; never `0.0.0.0`... (bind IS the wifi IP — loopback tests use 127.0.0.1 with guard bypass flag for tests only).
2. Per request: client IP must be private (`10/8`, `172.16/12`, `192.168/16`) AND share server's /24 (`ip & 255.255.255.0` equal). Else 403. Pure function `isSameLan(serverIp, clientIp)` — unit-tested.
3. Token compare constant-time-ish (`==` on 6-char is fine; document).
4. Background serving (since v3): allowed until Stop/kill via foreground service — owner explicitly accepted the wider-open-port tradeoff (token + subnet + TLS + rate limit unchanged). Screen-visible-only rule retired.

## 7. CORS (minimal, LAN — v2)

- `OPTIONS` preflights (no auth): `204` with `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: GET, POST, OPTIONS`, `Access-Control-Allow-Headers: Authorization, Content-Type`, `Access-Control-Max-Age: 86400`.
- `GET`/`POST` responses also carry `Access-Control-Allow-Origin: *`.
- Token is still mandatory on every real call — origin `*` is safe here (LAN-only URL + token + subnet guard; no cookies/sessions to hijack).

## 8. QR connect (v2)

- The LAN screen shows a QR encoding the JSON payload `{"url":"https://<ip>:8080/api/v1","token":"XXXXXX"}` (~200px, dark tile, beside/below the copy buttons) so a second device joins without typing.
- Payload builder is the pure function `buildQrPayload(url, token)` — unit-tested; screen only renders it.

## 9. Non-goals v3

No PUT/DELETE (POST-only write), no mDNS auto-discovery (type the URL or scan the QR). Background serving runs until Stop/kill (owner-accepted).

---
*Future: edit/delete over LAN need fresh contract + user confirm — not in v2.*

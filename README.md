# NEB:Expense Tracker

Offline personal finance tracker (Flutter, Android APK, sideload — no Play Store, no cloud, no accounts).

## Features

- Wallets (Cash, UPI, Bank) + total balance (paise-int math, Indian grouping)
- Add income / Subtract expense (2 taps, overspend blocked, last-wallet default, categories, optional note)
- Debt tracker tab (You owe / Owed to you, partial payments, settle — memo only, never touches balances)
- Monthly items (tap-to-add recurring: Spotify, YouTube…)
- Cart wishlist (Total + Current + If-bought preview, one-txn Buy)
- Stats: 120-day heatmap, monthly income-vs-expense bars, wallet-share + income/expense + category donuts
- Export CSV + backup/restore JSON, import with Replace-confirm (reset wipes everything incl. PIN; reinstalls start fresh — no cloud backup, so export monthly)
- Instant lock (fingerprint + 4-digit PIN) on launch/background
- Splash sting, version label V.0.0.1
- LAN API (Settings → LAN API): HTTPS read endpoints + `POST /transactions` + debts routes, token auth, QR connect, runs in background until Stop/kill

## Repo map

- `finance_tracker/` — the Flutter app (lib/, test/, android/)
- `docs/` — PRD, Architecture, API contract (`docs/API.md`), Rules, Memory, Phases, Design
- `Logos/` — logo concepts + showcase
- `required-docs.md` — owner brief (if present)

## Build APK

Needs Flutter 3.47 + Android SDK 36.

```sh
cd finance_tracker
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

APK lands at `finance_tracker/build/app/outputs/flutter-apk/app-release.apk`.

## Install / sideload

1. Copy the APK to your phone, tap it, allow "Install unknown apps" once.
2. Open the app, set your PIN (offered on first lock).
3. Back up early: Settings → Export JSON, keep the file somewhere safe.
4. Reminder: uninstalling the app wipes its local DB — re-import your JSON backup after reinstall.

## LAN API usage

Same WiFi on phone + PC. Phone: Settings → LAN API → if WiFi is off you get a
"Connect to WiFi first" popup; otherwise the server starts and shows:

- URL like `https://192.168.1.5:8080/api/v1` (always `https`, port 8080)
- a 6-char token (regenerates every start) + a QR encoding both

First visit: the browser warns (self-signed cert) → Advanced → Proceed.
Safe: your own phone, LAN only, token still required on every call.

```sh
# health (token via header or ?token=)
curl -k -H "Authorization: Bearer ABC123" https://192.168.1.5:8080/api/v1/health

# read
curl -k -H "Authorization: Bearer ABC123" https://192.168.1.5:8080/api/v1/wallets
curl -k -H "Authorization: Bearer ABC123" "https://192.168.1.5:8080/api/v1/transactions?per_page=5"

# write (income or expense; wallet_id or wallet name; paise wins over amount_inr)
curl -k -H "Authorization: Bearer ABC123" -H "Content-Type: application/json" \
  -d '{"type":"expense","wallet":"Cash","amount_inr":"12.50","from_for":"Chai"}' \
  https://192.168.1.5:8080/api/v1/transactions
# → 201 Created + Location: /api/v1/transactions/<id>
# → 422 insufficient_balance (with available_paise) if the wallet is short
```

Scan the on-screen QR instead of typing: it holds
`{"url":"https://<ip>:8080/api/v1","token":"XXXXXX"}`.

Full contract (endpoints, codes, CORS, QR): [`docs/API.md`](docs/API.md).

## Security notes

- Offline-first: data lives in the app DB only; nothing leaves the phone except when YOU tap Export or start the LAN server.
- Instant lock: backgrounding or locking the phone locks the app AND stops the LAN server immediately.
- No background serving — intentional, not a backlog item. The LAN server runs only while its screen is visible, so a forgotten server can never sit open on your network.

## Tests

106/106 pass (`flutter test`), `flutter analyze` clean. LAN suite covers guard matrix,
token rotation, HTTPS enforcement, all read endpoints, POST happy/overspend/error paths,
CORS preflight, QR payload, and rate limits. Run before every claim of done:

```sh
cd finance_tracker
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test
```

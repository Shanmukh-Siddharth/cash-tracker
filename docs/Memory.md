# Memory — Project Brain (Update Every Session)

> AI: read this + PRD + Architecture + Rules before coding. Append after every phase/work. Never re-read whole codebase to recall.

## Current Status (2026-10-07)

- Phase 1 DONE: DB + repos + lock + home + stubs. `flutter analyze` clean, `flutter test` 33/33 pass.
- Phase 2 DONE: shared Add/Edit sheet + chooser w/ long-press Subtract + real History (search/filter/group/edit/delete) + last-wallet persistence. `flutter analyze` clean, `flutter test` 53/53 pass.
- No APK run yet. Next = Phase 5 (Export + Settings polish).
- Phase 3+4 DONE 2026-10-08: Cart (repo+math, steppers, swipe-remove, sticky preview, single-txn Buy, tab badge) + Stats (stats_repo, heatmap, fl_chart bars, 2 donuts, 3M/6M/1Y) + glass pill nav. `flutter analyze` clean, `flutter test` 68/68 pass.
- Stack locked: Flutter + sqflite offline, personal APK, no cloud.
- Design locked for demos: premium dark fintech, subtle motion, 5-tab, instant fingerprint+PIN lock.

## Key Decisions (Don't Re-Ask)

1. Platform = Flutter (offline APK, sideload, no Play Store).
2. Wallets = Multiple (Cash, UPI, Bank default). Total = sum. INR only.
3. Add = amount + fromWhom + wallet + optional note. Subtract = amount + forWhat + wallet + optional note. No categories v1.
4. Cart = wishlist preview (name/price/qty) → shows Total + Current + If-bought → Buy creates grouped expense, clears cart. No deduct until Buy.
5. Stats = all three: heatmap (120d daily expense) + monthly bar (income vs expense) + pie (wallet share + income/expense donut, NOT category pie).
6. Export = both CSV (view) + JSON (backup/restore). Import JSON required. Save to phone + share.
7. Money = int paise internally. Balance changes only via repo DB transactions.
8. Design.md = v1.0 done 2026-10-07. Premium dark fintech, Sora/Inter/JetBrains Mono, emerald+gold, 5-tab, subtle motion, instant lock.
9. Lock = fingerprint + 4-digit PIN (was NO lock). Instant on background/launch. local_auth + secure_storage.

## Pending Doubts / To Confirm Later

- [x] Lock: fingerprint+PIN instant — CONFIRMED 2026-10-07
- [x] Owner to pick demo winner: demo-1-emerald / demo-2-royal / demo-3-clean-light
- [x] WINNER 2026-10-07: Demo 1 Emerald dark + gold + rose + teal + white. Lock for Flutter build.

- [x] Default wallet for Add/Subtract: last-used — DONE Phase 2 (`last_wallet_id` prefs)
- [ ] Grouped cart expense vs per-item txns? (Proposal: grouped `Cart purchase (n items)` — confirm in Phase 3)
- [ ] Import conflict: overwrite vs merge? (Proposal: overwrite with confirm for v1)
- [ ] PIN lock needed? Currently NO — revisit after v1 if wanted.

## Log

| Date | What | Files | Next |
|---|---|---|---|
| 2026-10-07 | Docs v0.1 created from owner brief + Q&A | docs/PRD.md, Architecture.md, Rules.md, Phases.md, Memory.md | Start Phase 1: flutter create + DB + home |
| 2026-10-07 | Phase 1 done: DB v1 + repos + Riverpod + lock + home + stubs, analyze clean, 33 tests pass | finance_tracker/lib/** (app, core/db+money+theme, models, repos, providers, lock, home, stubs), test/money+balance_logic, pubspec deps | Phase 2: Add/Subtract sheets + History |
| 2026-10-08 | Phase 2 done: shared Add/Edit sheet (last-wallet default, overspend block), chooser + long-press Subtract, History (search/chips/day groups/edit/delete), 53/53 tests pass | lib/features/add_edit/add_sheet.dart+last_wallet_store.dart, lib/features/history/history_screen.dart+grouping.dart, lib/app.dart, lib/state/providers.dart (+historyProvider), lib/data/repos/txn_repo.dart (+allTxns), test/grouping+last_wallet_store+balance_logic | Phase 3: Cart preview + Buy |
| 2026-10-08 | Phase 3+4 done: Cart (CRUD repo, cart_math, steppers, swipe-remove, sticky preview Total/wallet/Current/If-bought, one-txn Buy, badge) + Stats (stats_repo daily/monthly/share/totals, heatmap 7×weeks gold-top, grouped bars, 2 donuts, 3M/6M/1Y) + glass pill nav (blur, emerald bubbles, badge, reduced-motion fallback), analyze clean, 68/68 tests pass | lib/data/repos/cart_repo.dart+stats_repo.dart, lib/features/cart/cart_math.dart+cart_screen.dart, lib/features/stats/stats_math.dart+stats_screen.dart, lib/app.dart, lib/state/providers.dart, test/cart_math+stats_math+buy_flow | Phase 5: Export + Settings |
| 2026-10-08 | Phase 5 done: ExportRepo (CSV date-ordered + JSON paise/schema1, InvalidBackup validation, one-txn restore+recalc+dangling-wallet fix, resetAll reseed) + saveAndShare + real Settings (CSV/JSON export w/ last_export_at, JSON import w/ Replace-confirm, PIN change, biometric toggle honored by lock, double-confirm reset, About 1.0.0+1), analyze clean, 74/74 tests pass | lib/data/repos/export_repo.dart, lib/core/files.dart, lib/features/settings/settings_screen.dart+settings_store.dart, lib/features/lock/lock_screen.dart, test/export_test.dart | Phase 6: APK build + polish |
| 2026-10-08 | Logos round 3 (ref-driven): dropped B/C-₹, new B lens (tracker+₹+cycle) + C note-bars (growth), D ₹ redrawn true-glyph, audit 90–99/100, B recommended | Logos/concept-a + b-rupee-lens + c-note-bars + d-rupee-tile, showcase.html, renders/, Sample logos.png ref | Owner picks winner → kit + app icon wiring |
| 2026-10-08 | Splash sting + V.0.0: Rupee Lens splash (lens_mark painter + 1200ms stagger, once per cold start → lock gate, reduced-motion 300ms static), appVersion const in Settings About + lock footer, 5 new tests, analyze clean, 79/79 pass | finance_tracker/lib/core/app_version.dart, lib/features/splash/splash_screen.dart+lens_mark.dart, lib/app.dart, lock/settings screens, test/splash_test.dart | Phase 6: APK build + polish |

| 2026-10-08 | LAN API v1 done: guard/token/server/screen per docs/API.md, Settings row, 17 new tests, analyze clean, 96/96 pass | lib/features/lan_api/lan_guard+lan_token+lan_server+lan_api_screen, settings_screen, test/lan_api_test.dart, docs/Rules.md | Phase 6: APK build + polish |
| 2026-10-08 | LAN API v2 done: HTTPS always-on (RSA-2048 self-signed, PEM persist+reuse, hand-rolled DER — x509 0.2.4 OID encoder broken w/ asn1lib 1.x), POST /transactions (201+Location, 422 insufficient_balance+available_paise, onMutated→refreshAfterMutation), CORS preflight, QR (buildQrPayload pure), contract+Rules updated, repo-root README added, analyze clean, 106/106 pass | lib/features/lan_api/lan_cert+lan_qr+lan_server+lan_api_screen, txn_repo.getTxn, test/lan_api_test.dart (27 LAN tests), docs/API.md v2, README.md | Phase 6: APK build + polish |
| 2026-10-08 | WINNER logo C (Note and Bars): kit concept-c SVGs + splash swap (notes_mark painter, 1200ms C intervals bars→arrows→note→swoosh, 56px static lock mark), lens_mark deleted, analyze clean, 111/111 tests pass | finance_tracker/lib/features/splash/notes_mark.dart+splash_screen.dart, lib/features/lock/lock_screen.dart, test/splash_test.dart, Logos/concept-c-* | Renamed app → NEB:Expense Tracker |
| 2026-10-08 | Renamed app to NEB:Expense Tracker (manifest label, app title, home/lock/settings/splash captions, biometric reason, README heading); fixed splash test caption; full suite green 111/111 | AndroidManifest, app.dart, home/lock/settings/splash captions, test/splash_test.dart, README.md | Categories + recurring + background LAN |
| 2026-10-08 | Phase 8 done: categories (DB v2, Misc-last, mandatory note) + recurring templates (Monthly items, tap-to-add) + background LAN (foreground service until Stop/kill); duplicate finance_tracker/docs/ merged into real docs/ and removed; analyze clean, 133/133 pass | lib/data/categories.dart, recurring_repo, lan_background, sheets/stats/history/API+exports, test/categories+recurring+lan, docs/API.md v3+Rules+Phases | Reset fix + Debt tab |
| 2026-10-08 | Phase 9 done: track-only Debt tab (owe/lent, payments, settle, 5th nav slot, API debts routes, schema v3) + reset wipes PIN/prefs + allowBackup=false; analyze clean, 188/188 pass | debt_repo/screen, database v3, app.dart nav, lan_server debts, export schema v3, test/debt*, docs/API.md v4+Phases | Nav simplify + sheet close |
| 2026-10-08 | Nav simplified (center+/notch/chooser deleted, 5 boxes, triangle glides all 5, flat active, FABs lifted) + sheet close fixed (REAL bug: controller disposed mid-reverse froze route; X + isDismissible on 3 sheets); app-release-V1.apk renamed; analyze clean, 191/191 pass | app.dart, add/cart/recurring sheets, nav_pill_test, docs/Design.md | Phase 6: APK rebuild + device retest |

## How To Update

- After each work: add row to Log, update Current Status, record any new decision with reason.
- If spec changes: update PRD/Architecture/Rules first, then note here.
- Keep this file <100 lines — summarize old logs when too long.

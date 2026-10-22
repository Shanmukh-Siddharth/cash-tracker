# Phases — Build Plan (AI Can't Build Everything At Once)

**Stack:** Flutter offline APK. **Order matters.** Finish + verify each phase, update Memory.md, then next.

## Phase 0 — Docs & Setup (DONE 2026-10-07)

- [x] `docs/` created as memory
- [x] PRD.md, Architecture.md, Rules.md, Phases.md written
- [x] Design.md v1.0 done (premium dark fintech, lock spec, tokens)
- [x] 3 HTML demos in docs/demos/ — owner picks winner
- [ ] Next: `flutter create finance_tracker` + run on emulator (owner confirms)

## Phase 1 — Foundation: DB + Wallets + Home + Lock skeleton (DONE 2026-10-07)

- [x] Flutter 3.47.6 SDK installed (C:\src\flutter\bin, on User PATH — reopen terminal to pick up), Android 36 + licenses accepted, `finance_tracker` scaffolded (com.personal)
- [x] DB (wallets/txns/cart_items, paise, seed Cash/UPI/Bank 0, recalculate), repos with overspend-block + revert-apply, Riverpod state
- [x] Lock skeleton: cold-start locked, instant background lock, biometric-first + 4-digit salted-hash PIN + 30s cooldown
- [x] Home in Demo-1 emerald + floating-pill nav (raised bubble per Nav bar design.png), recent-5, stubs labeled for later phases
- [x] Verify: `flutter analyze` clean, `flutter test` 33/33 pass (verified by owner-agent run)

## Phase 2 — Add / Subtract + History (DONE 2026-10-08)

- [x] Shared add/edit sheet (mono amount, from/for, last-used wallet default, note, overspend block), center chooser + long-press Subtract
- [x] History: search, All/In/Out + wallet filters, day groups, tap-edit (revert-apply), swipe/icon delete with confirm, empty states
- [x] Pure helpers tested (groupByDay, search/filter, LastWalletStore) — no widget tests
- [x] Verify: `flutter analyze` clean, `flutter test` 53/53 pass (verified by owner-agent run)

## Phase 3 — Cart / Wishlist Preview + Buy (DONE 2026-10-08)

- [x] Cart CRUD + qty steppers + Clear-all, sticky Total + wallet + If-bought pill, Buy All → one grouped expense in single DB txn
- [x] Glassmorphic floating-pill nav (image shape, Demo-1 colors, blur, raised bubbles, cart badge)
- [x] Verify: `flutter analyze` clean, tests 68/68 (verified by owner-agent run)

## Phase 4 — Stats: Heatmap + Graphs (DONE 2026-10-08)

- [x] 120-day GitHub-style heatmap (emerald scale, gold top, tap-day totals), monthly income/expense bars, wallet-share + income/expense donuts, 3M/6M/1Y chips, empty states
- [x] Verify: covered in 68/68 run above

## Phase 4 — Stats: Heatmap + Graphs

Goal: Insights render with real data, graceful empty states.
- `stats_repo`: daily totals (120d), monthly income/expense (12m), wallet share
- Heatmap grid (GitHub-style) + tap-day detail
- Monthly bar (income vs expense) via fl_chart
- Pie/donut: wallet-wise expense + income-vs-expense
- Verify with seeded dummy data + empty DB

## Phase 5 — Export / Import + Settings (DONE 2026-10-08)

- [x] Export CSV + JSON (save + share sheet, last-export stamp), Import JSON (validate → confirm → wipe+restore+recalculate, invalid = no wipe), Change PIN, biometric toggle (lock honors it), double-confirm reset, About
- [x] Verify: `flutter analyze` clean, `flutter test` 74/74 pass (verified by owner-agent run; CSV quoting + restore-rebuild covered)

## Phase 6 — Polish, APK & Handover

Goal: Owner uses it daily on phone.
- App icon, name "Finance Tracker", basic Material theme (design pass later)
- `flutter build apk --release`, sideload + smoke test (add/sub/cart/stats/export offline)
- README how-to-install + backup reminder
- Update Memory.md: known issues, future ideas (categories, PIN, budgets, recurring, multi-currency)

## Phase 7 — LAN-Only Read API (DONE 2026-10-08)

- [x] Contract `docs/API.md` (8 GET endpoints, envelopes, /24 + token rules); phone-hosted shelf server, Settings toggle with WiFi-off popup, token per start, auto-stop on background/lock, 60/min rate limit
- [x] Verify: `flutter analyze` clean, `flutter test` 96/96 pass (verified by owner-agent run; no device run per owner)

## Phase 8 — Categories + Recurring + Background LAN (DONE 2026-10-08)

- [x] Categories (DB v2, expense×12 Misc-last + income×5 Other-last, last-used default), note REQUIRED on Add/Edit, history tag + search, category donut, LAN/exports carry category, POST: `422 note_required` / `422 invalid_category`
- [x] Recurring templates (user-tapped monthly, no scheduler): Settings → Monthly items, per-row Add + Add-all-due (30-day rule, skip report)
- [x] Background LAN: foreground service until Stop/kill (owner-accepted), re-attach screen, manifest perms
- [x] Verify: `flutter analyze` clean, `flutter test` 133/133 (verified by owner-agent run; device-only background check excluded)

## Phase 9 — Debt Tracker + Reset Fix (DONE 2026-10-08)

- [x] Track-only Debts (DB v3, owe/lent + payments + settle, never touches balances), 5th nav tab (Debt+Cart+Stats right of notch, triangle glides to all), gold open-count badge, LAN debts endpoints, export schema v3
- [x] Reset wipes PIN+prefs (fresh PIN setup), `allowBackup=false` (true fresh install)
- [x] Verify: `flutter analyze` clean, `flutter test` 188/188 (verified by owner-agent run; PIN-secure-storage + fresh-install device-only)

## Future (NOT v1 — Do Not Build Now)

- Categories/tags + category pie, budgets/limits, recurring transactions
- App PIN lock, multi-currency, cloud backup toggle (only if owner asks)
- Design.md full theme (colors/fonts) — next design session

---
*How to use: AI picks ONE phase at a time. Mark [x] + date in Memory.md when done.*

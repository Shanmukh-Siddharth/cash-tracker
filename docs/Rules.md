# Rules — AI Boundaries for Finance Tracker

**Purpose:** Keep builds simple, offline, and safe. AI must follow these unless owner overrides.

## 1. Libraries — Use / Avoid

**Use (v1 approved):**
- `sqflite`, `path`, `path_provider` — storage
- `flutter_riverpod` (or `provider`) — state
- `fl_chart`, `intl`, `csv`, `share_plus`, `file_picker`
- `local_auth`, `flutter_secure_storage` — fingerprint + PIN lock (NEW 2026-10-07)
- `shelf`, `shelf_router`, `connectivity_plus` — LAN read-only API only, no runtime internet (NEW 2026-10-08; no `network_info_plus`, no `http`/`dio`)
- `cryptography`, `x509`, `qr_flutter` — LAN API v2 only: self-signed TLS identity + QR connect (NEW 2026-10-08; still no runtime internet — LAN radio only)
- `flutter_foreground_task` — LAN API v3 only: keep server alive minimized until Stop/kill (NEW 2026-10-08; owner-accepted tradeoff)

**Avoid (do NOT add without asking):**
- No Firebase / Supabase / any cloud / auth / analytics / crashlytics
- No ads SDK, no `http`/`dio` network calls (app must work with internet OFF)
- No heavy state (Bloc boilerplate), no ORM overkill (drift/floor) for v1
- No new chart lib if `fl_chart` + custom grid works

If a task needs a new package → stop, propose in chat, update this file after approval.

## 2. Money & Balance Safety

- Store money as **int paise** internally. Display as ₹ with 2 decimals. Never use raw `double` for balance math.
- Every balance change MUST go through `wallet_repo`/`txn_repo` DB transaction. No direct `UPDATE wallets SET balance` from UI.
- Expense must check `amount <= wallet.balance` before write. Block + message if not.
- Edit/delete must revert-then-apply. Provide `recalculateBalances()` and use after import.
- Amount parsing: strip ₹, commas, spaces. Reject 0, negative, >2 decimals, empty from/for.

## 3. Offline-First & Privacy

- No `INTERNET` permission unless a package forces it — justify in PR.
- All data stays in app DB (`/data/data/.../databases`). Export only when user taps Export.
- No tracking, no logs with real amounts in git/commits. Use synthetic values in tests/docs.
- Reset-data requires double confirm (`Type DELETE` or two dialogs).

## 4. Simplicity (Owner Wants Simple Sweet)

- Max 2 taps to Add/Subtract. Bottom sheets, big buttons, large amount field with numeric keyboard.
- From-whom / For-what = single required text field. Note = optional, one line. No categories in v1.
- Cart preview must ALWAYS show: Total, Current balance, If-bought balance. Never deduct before Buy.
- Empty states for Home/History/Cart/Stats — no blank screens, no crashes on zero data.

## 5. What AI Should / Shouldn't Do

**Should:**
- Keep `docs/` updated: after each phase, update `Memory.md` (what done, what next, decisions).
- Follow `Phases.md` order. Don't jump to Stats before Home+DB works.
- Write small, focused files per Architecture.md. Ask before restructuring.
- Validate with `flutter analyze` + relevant `flutter test` before claiming done.

**Shouldn't:**
- Don't build Design.md styling now (deferred). Use default Material theme, focus on logic.
- Don't invent categories, budgets, PIN, multi-currency, sync — mark as Future, don't code.
- Don't commit secrets, keystores, or real export CSVs. Don't output full DB dumps in chat.
- Don't claim "tested on phone" unless owner confirms APK install.

## 6. Error Handling Pattern

- UI validation → inline red text, disable Save until valid.
- DB/file failure → Snackbar + safe rollback, never half-deduct.
- Import → validate JSON keys first; on fail show "Invalid backup file" and abort without wiping.

## 7. Docs Memory Rule

- `docs/` is memory. Before coding, read PRD + Architecture + Memory. After coding, append to Memory.md: date, phase, files changed, decisions, pending doubts.
- If a user answer contradicts these rules (e.g. asks for cloud), pause and confirm — update Rules.md only after explicit yes.

---
*Last updated: 2026-10-07. Design rules to be added later in Design.md.*

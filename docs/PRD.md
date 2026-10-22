# PRD — Personal Finance Tracker App

**Version:** 0.2 (2026-10-07)
**Status:** Draft — Design.md v1.0 done, awaiting demo pick
**Owner:** Personal use (single user, no Play Store, no cloud)

## 1. What Are We Building?

A simple, sweet, offline-first personal finance tracker for Android (sideloaded APK, no Play Store).

Core idea:
- See total balance at a glance.
- Two big actions: **Add (+)** and **Subtract (−)**.
- Extra section: **Cart / Wishlist** — add items you plan to buy, see total cost + what balance will be *if* you buy them, then Buy to deduct.
- Extra insight: **Heatmap + Graphs** for spending patterns.
- **Export data** to CSV or JSON stored on phone storage.
- **App lock** — fingerprint + PIN, instant lock on background/launch.

No login, no cloud, no sync. Everything stays on the phone.

## 2. Who Is It For?

Single user (owner). Personal expense tracking.
- No multi-user, no roles, no onboarding funnel.
- Must work fully offline, open fast, 2-tap entry.

Success = owner opens app daily, adds entries in <10 seconds, checks cart before buying, exports backup monthly.

## 3. Tech Choice (Confirmed)

- **Flutter (Dart)** — one codebase, easy offline APK for personal use.
- Local storage on phone: SQLite via `sqflite` (structured) + file export via `path_provider`.
- No Firebase, no Supabase, no internet required.

## 4. Features

### 4.1 Wallets (Confirmed: Multiple Wallets)

User chose multiple wallets instead of single wallet.

- Default wallets on first run: `Cash`, `UPI`, `Bank`. User can add/rename/delete (cannot delete if balance != 0 or has transactions — must transfer first).
- Each wallet has its own balance. **Total balance = sum of all wallets.**
- Home shows: Total balance (big) + per-wallet breakdown (small cards/list).
- Every Add/Subtract must pick a wallet.
- Currency: INR (₹) only for v1. No multi-currency.

Acceptance:
- Create wallet, starting balance defaults to 0.
- Deleting wallet with transactions is blocked with message.

### 4.2 Add Money (+) — "From Whom?"

Flow: Tap `+ Add` → dialog/bottom-sheet asks:
1. How much? (numeric, >0, max 2 decimals)
2. From whom? (text, required — e.g. "Mom", "Salary", "Friend refund")
3. Wallet? (dropdown, defaults to last used)
4. Note? (optional single line)
5. Date = auto now (editable in history if needed, v1 allows edit).

On save: wallet balance increases, transaction saved as `type=income`.

### 4.3 Subtract Money (−) — "For What?"

Flow: Tap `− Subtract` → asks:
1. How much? (numeric, >0, cannot exceed selected wallet balance — block overspend with warning)
2. For what? (text, required — e.g. "Chai", "Petrol", "Recharge")
3. Wallet? (dropdown)
4. Note? (optional)
5. Date = auto now.

On save: wallet balance decreases, transaction saved as `type=expense`.

Validation:
- Amount must be >0.
- Expense > wallet balance → show error "Not enough in [wallet]. Available: ₹X".
- From/For field cannot be empty.

### 4.4 Transaction History

- List grouped by date (Today / Yesterday / date), newest first.
- Each row: icon (+ green / − red), From/For text, wallet tag, amount, note (if any).
- Actions: edit (amount, from/for, note, wallet — auto-adjusts balances), delete (reverts balance with confirm).
- Search by From/For/note. Filter by wallet + type (income/expense) + date range.
- Pull-to-refresh not needed (local), but list updates instantly.

### 4.5 Cart / Wishlist Preview + Buy (Confirmed)

This is NOT the main balance. It's a "what-if" calculator.

- Separate tab/section: `Cart`.
- Add item: name (required), price (required, >0), qty (default 1).
- Cart shows:
  - Item list with qty stepper, remove, clear-all.
  - `Total cost = sum(price * qty)`
  - `Wallet selector` (which wallet would you pay from?)
  - `Current balance (selected wallet): ₹X`
  - `Balance if bought: ₹X − Total = ₹Y` (red if negative, green if safe).
  - Total overall balance-if-bought too.
- `Buy All` button:
  - If sufficient balance → creates one expense transaction per item (or one grouped transaction "Cart purchase (n items)" — decision: one grouped expense with item breakdown in note for simplicity) in selected wallet, clears cart, shows success.
  - If insufficient → block with "Not enough balance" message.
- Cart persists locally (even if app closed) until bought or cleared. Cart does NOT affect balance until Buy.

Open question resolved: Qty support = yes. Buy = yes (grouped expense).

### 4.6 Heatmap + Graphs (Confirmed: All Three)

Located in `Stats` tab.

1. **Heatmap (GitHub-style):** daily expense intensity for last ~120 days / current year. Darker = spent more. Tap day → shows that day's total + transactions.
2. **Monthly bar chart:** income vs expense per month (last 6–12 months). Bars grouped or stacked.
3. **Pie / breakdown:** Since user chose "Simple, no categories", v1 pie = **wallet-wise expense share + income vs expense donut**. No category pie in v1. If user wants categories later, add optional tag field — noted as future.

Empty states: "No data yet — add your first entry".

### 4.7 Export Data (Confirmed: Both CSV and JSON)

- `Export` button in Settings / Home overflow.
- Options: `Export CSV`, `Export JSON`.
- CSV: one file `finance_export_YYYYMMDD_HHMMSS.csv` with columns: `id, date, type, amount, from_for, wallet, note, created_at`.
- JSON: one file `finance_backup_YYYYMMDD_HHMMSS.json` with `{ wallets: [...], transactions: [...], cart: [...], exported_at }`.
- Saved to phone storage (Documents / Download via Storage Access Framework) + Share sheet (WhatsApp to self, Drive, etc.).
- **Import JSON restore** included in v1 (needed for phone change). CSV is export-only.
- Toast + path shown after export.

### 4.8 Settings / Misc

- INR symbol fixed.
- Reset-all-data (with double confirm) — for testing.
- About + version.

### 4.9 App Lock (NEW 2026-10-07 — Fingerprint + PIN)

- First run: forced PIN setup (4-digit) + offer biometric enroll.
- Every launch + immediately on background → Lock screen. Biometric first via `local_auth`, fallback PIN. 5 wrong PIN → 30s cooldown.
- PIN hash in `flutter_secure_storage`, balances hidden until unlock. See Design.md §3.1.

## 5. Non-Goals (v1 Out of Scope)

- No cloud sync, no login, no Play Store release.
- No multi-currency, no budgets/limits, no recurring auto-transactions.
- No category system (deferred — using free-text For/From).
- No Design.md styling yet — functionality first, design later per owner.
- No iOS build (Android APK only for v1).

## 6. Data Model (Summary)

```
Wallet(id, name, balance, created_at)
Transaction(id, wallet_id, type[income|expense], amount, from_for, note?, date, created_at)
CartItem(id, name, price, qty, added_at)
```

Balance is stored on Wallet and updated transactionally on add/edit/delete/buy. Never compute from scratch on every render (but provide recalculate function for repair).

## 7. Acceptance Checklist (v1 Done When...)

- [ ] Add increases wallet + total, Subtract decreases, overspend blocked.
- [ ] Cart total + if-bought balance correct, Buy deducts once and clears cart.
- [ ] Heatmap + bar + pie render with real data, empty state otherwise.
- [ ] CSV + JSON export saves to phone and opens share sheet, JSON re-import restores.
- [ ] Edit/delete transaction fixes balances correctly.
- [ ] Fully offline, no internet permission needed (except share).
- [ ] Lock: cold start locked, background instantly locks, PIN fallback works.
- [ ] APK installs and runs on owner's phone.

---
*Design.md v1.0 done (premium dark). Demos in docs/demos/ — owner picks winner.*

# Architecture — Personal Finance Tracker

**Stack:** Flutter (Dart) + SQLite (sqflite) — 100% offline, no cloud.
**Target:** Personal Android APK (sideload). No Play Store.
**Docs memory:** `docs/` is source of truth. Update Memory.md every phase.

## 1. App Flow (User Journey)

```
Launch → Lock (biometric/PIN) → Home (Total + Wallets + Recent)
  ├─ [+ Add] → Sheet(amount, fromWhom, wallet, note) → save → Home updates
  ├─ [− Subtract] → Sheet(amount, forWhat, wallet, note) → validate balance → save
  ├─ [History] → search/filter → edit/delete (balance auto-fix)
  ├─ [Cart] → add items → preview Total + If-Bought → [Buy All] → expense + clear
  ├─ [Stats] → heatmap + monthly bars + wallet pie
  └─ [Settings/Export] → CSV / JSON → save to phone + share → Import JSON
```

Simple sweet: max 2 taps to Add/Subtract. No login splash. Home is root.

## 2. Technical Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Flutter 3.x (Dart) | Single codebase, fast APK, good offline |
| Local DB | `sqflite` + `path` + `path_provider` | Structured, survives reboot, easy backup |
| State | `Riverpod` (or Provider if simpler) | Predictable, testable. No Bloc overhead for v1 |
| Charts | `fl_chart` | Bar + pie, offline, lightweight |
| Heatmap | Custom GridView (GitHub-style) | No heavy dep needed, 120-day grid |
| Export | `csv` + `dart:convert` (JSON) + `share_plus` + `file_picker` | CSV gen, share sheet, import picker |
| Lock | `local_auth` + `flutter_secure_storage` | Biometric + PIN hash, instant lifecycle lock |
| Money | `int` paise internally OR `double` 2-decimals | Recommend int paise to avoid float errors; display ₹ with 2 decimals |
| Date | `intl` | Formatting, month grouping |

**Forbidden:** firebase_core, firebase_auth, cloud_firestore, supabase, any network analytics, ads SDK.

**Permissions Android:** `WRITE_EXTERNAL_STORAGE` (legacy) / Media + `READ` only for export dir via SAF. No `INTERNET` needed — omit if possible (share_plus may need none).

## 3. File & Folder Structure

```
finance_tracker/
  lib/
    main.dart                  → app entry, providers, theme (basic), nav
    app.dart                   → MaterialApp + bottom nav (Home, Cart, Stats, History/Settings)
    core/
      database.dart            → sqflite open, migrations, recalculateBalances()
      money.dart               → paise <-> ₹ format, parse/validate
      files.dart               → export/import paths, SAF save
      validators.dart          → amount>0, required from/for, overspend check
    data/
      models/
        wallet.dart
        transaction.dart       → type enum income/expense, from_for, note
        cart_item.dart
      repos/
        wallet_repo.dart       → CRUD + adjustBalance() in transaction
        txn_repo.dart          → insert/delete/update with balance fix
        cart_repo.dart         → CRUD (no balance effect until buy)
        stats_repo.dart        → daily totals, monthly income/expense, wallet share
        export_repo.dart       → toCSV(), toJSON(), importJSON()
    features/
      home/      → home_screen, widgets(total_card, wallet_list, quick_add_buttons, recent_list)
      add_edit/  → add_sheet (shared for Add/Subtract + edit txn)
      history/   → history_screen, filter bar
      cart/      → cart_screen, add_item_sheet, preview_bar (total + if-bought)
      stats/     → stats_screen, heatmap_grid, monthly_bar, wallet_pie
      settings/  → settings_screen (export/import buttons, reset, about)
    widgets/
      amount_input.dart
      empty_state.dart
      confirm_dialog.dart
  test/
    money_test.dart
    balance_logic_test.dart
    export_test.dart
  docs/ (repo root, NOT in lib — this folder, project memory)
  android/app/... (minSdk 21+, applicationId personal, version 1.0.0+1)
  pubspec.yaml
```

## 4. Data Flow & Key Logic

### 4.1 Balance integrity (most important)

- Never trust UI math. All balance changes go through repo in a DB transaction:
  - `addIncome(walletId, amount)` → INSERT txn + UPDATE wallet.balance += amount
  - `addExpense` → CHECK balance >= amount → INSERT + UPDATE balance -= amount
  - `editTxn` → revert old effect, apply new effect (handle wallet change too)
  - `deleteTxn` → revert effect
  - `buyCart(walletId)` → CHECK total <= balance → INSERT one grouped expense + UPDATE balance, CLEAR cart in same txn
- `recalculateBalances()` rebuilds wallet.balance from txns — used after import/reset.

### 4.2 Cart preview (no side effects)

- `cartTotal = Σ price*qty`
- `ifBought = wallet.balance − cartTotal`
- UI only reads; Buy is the only writer. Cart table has no trigger on wallets.

### 4.3 Stats queries

- Heatmap: `SELECT date(date), SUM(amount) WHERE type=expense GROUP BY day` last 120 days → intensity buckets (0, 1-25%, 25-50%, 50-75%, 75%+ of max).
- Monthly bars: `SELECT strftime('%Y-%m'), SUM(CASE income), SUM(CASE expense)) GROUP BY month` last 6–12.
- Pie: expense share per wallet; donut income vs expense.

### 4.4 Export / Import

- Export CSV: query all txns joined wallets ordered by date → `csv` package → write `finance_export_*.csv` to Documents → `Share.shareXFiles`.
- Export JSON: `{ wallets, transactions, cart, exported_at }` → `finance_backup_*.json` same flow.
- Import JSON: file_picker → parse → validate schema → in DB txn: wipe + insert + recalculate → toast.

## 5. Navigation (v1)

BottomNav 4 tabs: **Home | Cart (badge count) | Stats | More (History + Settings/Export)** — or 5 tabs if screen fits. Keep simple: Home, History, Cart, Stats, Settings.

## 6. Error Handling

- Validation at sheet level (empty, zero, overspend) with inline error text, not crash.
- DB errors → Snackbar "Something went wrong, try again" + log. Never lose balance: rollback on failure.
- Import errors → "Invalid backup file" message, no wipe until valid.

## 7. Testing & Build

- Unit: money format/parse, balance add/edit/delete/buy, cart total/if-bought, CSV header.
- Manual: install release APK on phone, airplane-mode test, export file opens in Sheets.
- Build: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` sideload.

---
*Design system (colors/fonts) deferred to Design.md later.*

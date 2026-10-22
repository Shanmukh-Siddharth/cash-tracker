# Design.md — Personal Finance Tracker (Full Spec)

**Version:** 1.0 (2026-10-07)
**Mode:** Operate (daily-use tool, per impeccable) — scanability > expression.
**Direction:** Premium dark fintech. Subtle smooth motion. 5-tab bottom bar.
**Demos:** `docs/demos/demo-1-emerald.html` WINNER (locked 2026-10-07: emerald + gold + rose + teal + white), others archived as alternatives.
**Skills applied:** ui-ux-pro-max (design, design-system, ui-styling), taste (design-taste-frontend dials 6/4/4), impeccable Operate, frontend-design-direction, 60fps + accessible motion.

> Reading this as: personal finance tool for one owner, premium-dark fintech language, leaning toward Material 3 dark + custom tokens + restrained motion.

## 1. Design Tokens (Single Source of Truth)

### 1.1 Primitive (raw)

```css
--emerald-400: #34D399; --emerald-500: #10B981; --emerald-600: #059669;
--gold-400: #F5C044; --gold-500: #E8A90C;
--ink-950: #0B0F0E; --ink-900: #111715; --ink-800: #1A221F; --ink-700: #24312C;
--mist-100: #EDF2EF; --mist-300: #B9C6BF; --mist-500: #7D8B84;
--red-400: #F87171; --red-500: #EF4444;
--radius-sm: 10px; --radius-md: 16px; --radius-lg: 24px;
--font-display: "Sora", "Outfit", system-ui, sans-serif;
--font-body: "Inter", system-ui, sans-serif;
--font-mono: "JetBrains Mono", ui-monospace, monospace;
```

No AI-purple. No pure #000/#fff. One accent per theme (emerald), gold reserved for total-balance + heatmap-hot.

### 1.2 Semantic (purpose)

| Token | Value | Use |
|---|---|---|
| `--bg` | `var(--ink-950)` | App bg |
| `--surface` | `var(--ink-900)` | Cards |
| `--surface-2` | `var(--ink-800)` | Sheets, dialogs |
| `--text` | `var(--mist-100)` | Primary text |
| `--text-2` | `var(--mist-300)` | Secondary |
| `--text-3` | `var(--mist-500)` | Hints |
| `--primary` | `var(--emerald-500)` | CTA, Add, Buy-safe, tab active |
| `--danger` | `var(--red-400)` | Subtract, delete, overspend |
| `--warn` | `var(--gold-400)` | If-bought negative, heatmap hot |
| `--line` | `rgba(237,242,239,0.10)` | Dividers, card borders 1px |
| `--shadow-card` | `0 8px 30px rgba(0,0,0,0.35)` | Cards only, tinted to bg |

Light variant (Demo 3 only): bg `#F6F7F6`, surface `#FFFFFF`, text `#101613`, primary same emerald-600.

### 1.3 Shape / Spacing / Type Lock

- Shape rule: cards `16px`, sheets `24px top`, buttons `full-pill`, inputs `12px`. No mixing.
- Spacing: page `16px`, card padding `16px`, gaps `12px`. Section stack `py-20` equivalent (dense tool, not landing).
- Type: Display total `32-36px / 700 / -0.02em` mono-tabular; H2 `18px/700`; body `14px/400`; label `11px uppercase 0.12em` — max 1 eyebrow per 3 sections. Numbers always `font-mono`, tabular-nums.
- Contrast: text on primary = ink-950 (not white) for AA. Danger text on dark = red-400.

## 2. App Structure (Floating Pill Nav — per `Nav bar design.png`, simplified 2026-10-08)

```
╭─ floating pill ───────────────────────────╮
│ Home  History  Debt  Cart(badge)  Stats    │  + Settings via top gear
╰───────────────────────────────────────────╯
```

- Floating pill: SHAPE from reference image, COLORS from Demo 1 (NOT reference blue/white). Glassmorphism: translucent surface `rgba(17,23,21,0.72)` + blur 16px (Flutter `BackdropFilter`), 1px border `rgba(237,242,239,0.14)` + subtle top inner highlight, card shadow. 20px radius, 12px side margins, floats 8-12px above bottom; content scrolls behind it.
- 5 equal rounded boxes (16px radius); NO center button, NO notch (removed — Home's +Add/−Subtract pills are the sole entry). Sliding triangle glides above the active tab (200ms, transform-only); flat emerald active box, no glow.
- Inactive = mist icons + 10px labels. One icon family, 24px. Reduced-transparency/motion: solid surface fallback, static triangle.
- Top app bar (Home only): "Finance" + total eye-toggle + gear. Other tabs: title + contextual action (History=filter, Cart=clear, Stats=range, Settings=none).

## 3. Screens (Operate — First Viewport = Job Done)

### 3.1 Lock Screen (NEW — fingerprint + PIN)

- Full-screen, bg blur of home behind (no data leak — balances hidden until unlock).
- Content: shield icon, "Unlock Finance", biometric button (big, 64px circle), "Use PIN" link.
- PIN pad: 4-digit, custom dots, numeric only, no OS keyboard. 5 wrong → 30s cooldown. PIN hash in `flutter_secure_storage`, never plain.
- Behavior (confirmed): lock **immediately** on cold start + on backgrounded >0s (AppLifecycle inactive). Biometric first (`local_auth` biometricOnly), fallback PIN. Cancel biometric → PIN. No "skip".
- Fail states: no biometrics enrolled → PIN setup forced on first run; biometric error → inline "Try PIN" (never crash).
- A11y: semantic labels, 48px targets, haptics on error.

### 3.2 Home

- Hero card (surface, 16px, no nested cards): eyebrow "TOTAL BALANCE", amount `₹12,450.00` mono 34px, gold tint for amount? No — text primary, small "↑ ₹2,000 in / ↓ ₹550 out today" row, wallet chips below (Cash ₹X · UPI ₹Y · Bank ₹Z).
- Quick actions: two pill buttons `[+ Add]` primary dark-text, `[− Subtract]` red-outline. 2 taps max.
- Recent 5 list: icon circle (+ green tint / − red tint), from/for 14px, wallet tag 11px, amount mono right, divider lines (no cards-in-cards).
- Empty: illustration slot + "Add your first entry".

### 3.3 Add / Subtract Sheet (shared)

- Bottom sheet surface-2, 24px top radius, drag handle.
- Amount field: huge 32px mono, `₹` prefix, numeric keyboard, auto-focus. Inline error red.
- Segmented wallet picker (Cash|UPI|Bank) + From-whom / For-what text field (label above, helper optional, error below — never placeholder-as-label).
- Note (optional, 1 line), Save button full-width primary (Add) / danger (Subtract). Disabled until valid.
- Overspend: "Not enough in UPI. Available ₹X" blocks save.

### 3.4 Cart

- Header stats strip: Total `₹250` mono + `Balance ₹500 → If-bought ₹250` pill (green if ≥0, red + warn icon if <0).
- Items: rows with qty stepper (− qty +), price mono, swipe-to-remove. Clear-all text button.
- Add item sheet: name + price + qty stepper.
- Sticky bottom: wallet selector + `[Buy All • ₹250]` primary. Insufficient → disabled + message.
- Badge on tab = item count.

### 3.5 Stats

- Range chips: 3M / 6M / 1Y (default 6M).
- Heatmap: 7×~17 grid, 12px cells 4px gap, emerald scale 5 steps (0 = line color, max = emerald-400, top 5% = gold). Tap → tooltip day total. Legend Less→More.
- Monthly bar (fl_chart): grouped income (emerald) vs expense (red-400), rounded 6px, mono axis, touch tooltip.
- Donut: wallet share + center total; second donut income vs expense. No category pie (no categories v1).
- Empty: "No data yet".

### 3.6 History + Settings/Export

- History: search bar, filter chips (All/In/Out + wallet), grouped headers (Today/Yesterday/date), edit on tap, delete swipe with confirm.
- Settings: Profile-free. Rows: Export CSV, Export JSON, Import JSON, Change PIN, Biometric toggle, Reset-all (double confirm, red), About. Show last-export time.

## 4. Motion (Subtle Smooth, 60fps, Accessible)

Dials: VARIANCE 6 / MOTION 4 / DENSITY 4. Claim = shown, minimal.

- Sheet: slide-up 220ms `cubic-bezier(0.16,1,0.3,1)` + scrim fade. Tab switch: fade 150ms, no slide. Button press: `scale 0.98`.
- Numbers: total count-up 400ms on change only (not on every build). Charts grow 500ms once. Heatmap stagger 6ms/cell max 20 cells.
- Animate ONLY transform/opacity. No layout thrash. Grain overlay fixed pointer-events-none only (no scroll container filters).
- `prefers-reduced-motion` / Flutter `disableAnimations`: all → instant, no count-up, no stagger. Respect OS reduce-motion + in-app toggle in Settings (future).

## 5. Accessibility + Performance Guards

- Targets ≥48px, labels above inputs, errors below, focus ring visible, screen-reader names on all icon buttons.
- Dark+light token parity, AA 4.5:1 body, 3:1 large. Test both modes (Demo 1/2 dark, Demo 3 light).
- LCP: first paint Home with cached total <1s offline; charts lazy. No network calls.
- No emojis in UI (icons only), no duplicate CTA labels, no wrapped pill CTAs (short labels: Add, Subtract, Buy All).

## 6. Flutter Mapping (for build, not demo)

- Material 3 `ColorScheme.fromSeed(seedColor: emerald)` + custom `extensions`. Fonts via Google Fonts package cached offline (Sora/Inter/JetBrains Mono) — fallback system-ui if offline build.
- Packages add: `local_auth`, `flutter_secure_storage` (lock). Already approved: sqflite, riverpod, fl_chart, csv, share_plus, file_picker, intl.
- Files: `features/lock/lock_screen.dart`, `lock_service.dart` (lifecycle observer), `pin_store.dart`.

## 7. What Changed (vs v0.1)

- Added lock (was NO lock) per owner 2026-10-07: fingerprint + 4-digit PIN, instant lock.
- Added this Design.md (was deferred). PRD/Architecture/Rules/Phases to be patched for lock.
- Demos = HTML phone frames only (not Flutter), 3 options for owner pick.

---
*Next: owner picks demo winner → lock tokens into build → Phase 1.*

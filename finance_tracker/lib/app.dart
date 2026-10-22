/// App shell: dark emerald MaterialApp, lock gate, and the 5-tab floating
/// glass pill bottom bar (Home, History, Debt, Cart, Stats).
///
/// The pill is a plain rounded rectangle with 5 equal [Expanded] tab slots.
/// The sliding triangle above the pill is the single active-tab marker
/// (transform-only 200ms glide). Active tab = flat emerald rounded box, no
/// glow. Home's +Add/−Subtract pills are the sole entry points for recording
/// money.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/cart/cart_screen.dart';
import 'features/debt/debt_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/lock/lock_screen.dart';
import 'features/lock/lock_service.dart';
import 'features/lock/pin_store.dart';
import 'features/splash/splash_screen.dart';
import 'features/stats/stats_screen.dart';
import 'state/providers.dart';

class FinanceApp extends ConsumerStatefulWidget {
  final LockService lockService;

  const FinanceApp({super.key, required this.lockService});

  @override
  ConsumerState<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends ConsumerState<FinanceApp> {
  /// Cold-start sting, shown once per launch. It never bypasses lock:
  /// [lockService] still boots locked, so dismissing the splash lands on
  /// the lock gate (identical lock behavior, incl. instant background lock).
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final lockGate = ValueListenableBuilder<bool>(
      valueListenable: widget.lockService.locked,
      builder: (context, locked, _) {
        if (locked) {
          return LockScreen(
            lockService: widget.lockService,
            pinStore: const PinStore(),
          );
        }
        return const MainNav();
      },
    );
    return MaterialApp(
      title: 'NEB:Expense Tracker',
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: _splashDone
          ? lockGate
          : SplashScreen(onDone: () => setState(() => _splashDone = true)),
    );
  }
}

/// Bottom nav: Home(0) | History(1) | Debt(2) | Cart(3) | Stats(4).
/// Home's +Add/−Subtract pills are the sole entry points for recording
/// money — there is no center button and no chooser sheet.
class MainNav extends ConsumerStatefulWidget {
  const MainNav({super.key});

  @override
  ConsumerState<MainNav> createState() => _MainNavState();
}

class _MainNavState extends ConsumerState<MainNav> {
  int _index = 0;

  void _onTap(int i) {
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // tab content scrolls behind the floating pill
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onOpenHistory: () => setState(() => _index = 1)),
          const HistoryScreen(),
          const DebtScreen(),
          const CartScreen(),
          const StatsScreen(),
        ],
      ),
      bottomNavigationBar: _PillNavBar(
        index: _index,
        onTap: _onTap,
      ),
    );
  }
}

/// Floating pill nav geometry (5 equal tab slots).
const double _kNavSideMargin = 12;
const double _kNavBottomInset = 10;
const double _kPillHeight = 60;
const double _kPillRadius = 20;

/// Tab buttons: 44px rounded square inside a >=48px tap target.
const double _kTabSize = 48;
const double _kTabRadius = 16;
const double _kTabIconSize = 24;
const double _kTabLift = 6;

/// Sliding triangle indicator above the pill.
const double _kTriangleWidth = 14;
const double _kTriangleHeight = 8;

/// The nav Stack: triangle strip above + pill below.
const double _kNavHeight = _kPillHeight + _kTriangleHeight; // 68

/// Plain rounded pill path (no notch).
Path _pillPath(Size size) {
  return Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(_kPillRadius),
      ),
    );
}

/// Glass (blur + translucency) or solid fallback for the plain pill.
class _PillPainter extends CustomPainter {
  final bool solid;
  const _PillPainter({required this.solid});

  @override
  void paint(Canvas canvas, Size size) {
    final path = _pillPath(size);
    if (!solid) {
      canvas.save();
      canvas.translate(0, 8);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black38
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
      );
      canvas.restore();
    }
    canvas.drawPath(
      path,
      Paint()..color = solid ? AppColors.surface2 : const Color(0xB8111715),
    );
    if (!solid) {
      // Subtle top inner highlight.
      canvas.save();
      canvas.translate(0, 1);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x14EDF2EF),
      );
      canvas.restore();
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = solid ? AppColors.line : const Color(0x24EDF2EF),
    );
  }

  @override
  bool shouldRepaint(_PillPainter old) => old.solid != solid;
}

/// Sliding triangle marker that glides above the pill to the active tab.
///
/// 5 slots: Home(0) History(1) Debt(2) Cart(3) Stats(4).
/// Motion is transform-only (AnimatedContainer matrix lerp, 200ms) so there
/// is no layout jank; static (no animation) when reduced motion is requested;
/// hidden from semantics (tabs already expose selection).
class _NavTriangle extends StatelessWidget {
  final int index;
  final bool reduceMotion;
  const _NavTriangle({
    required this.index,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final slot = index.clamp(0, 4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final targetX =
            w * (slot + 0.5) / 5 - _kTriangleWidth / 2;
        return AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion ? 0 : 200),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(targetX, 0, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ExcludeSemantics(
              child: SizedBox(
                key: const Key('nav_triangle'),
                width: _kTriangleWidth,
                height: _kTriangleHeight,
                child: CustomPaint(painter: _TrianglePainter()),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small down-pointing emerald triangle (the single active-tab marker).
class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final tri = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(tri, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => false;
}

/// Floating glassmorphic pill with 5 equal tab slots.
///
/// Layer 1 is the glass pill (`ClipRRect` + `BackdropFilter`). Layer 2 is a
/// sibling row holding the 5 tab buttons. Active tab = flat emerald rounded
/// square with an ink icon (deliberately no glow); inactive = transparent
/// with a mist icon. Reduced motion/transparency: solid surface, no blur,
/// no lift animation, triangle static.
class _PillNavBar extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _PillNavBar({
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Solid fallback when the OS requests reduced motion/transparency.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final cartCount = ref.watch(cartCountProvider).maybeWhen(
          data: (n) => n,
          orElse: () => 0,
        );
    final debtCount = ref.watch(debtOpenCountProvider).maybeWhen(
          data: (n) => n,
          orElse: () => 0,
        );

    final glass = CustomPaint(
      painter: _PillPainter(solid: reduceMotion),
      child: const SizedBox.expand(),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _kNavSideMargin,
          0,
          _kNavSideMargin,
          _kNavBottomInset,
        ),
        child: SizedBox(
          height: _kNavHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // --- Layer 0: sliding triangle above the pill ---------------
              Positioned(
                left: 0,
                right: 0,
                bottom: _kPillHeight,
                height: _kTriangleHeight,
                child: _NavTriangle(
                  index: index,
                  reduceMotion: reduceMotion,
                ),
              ),
              // --- Layer 1: plain glass pill -------------------------------
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _kPillHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kPillRadius),
                  child: reduceMotion
                      ? glass
                      : BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: glass,
                        ),
                ),
              ),
              // --- Layer 2: 5 equal tab buttons ---------------------------
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _kPillHeight,
                child: Row(
                  children: [
                    _tab(0, Icons.home_outlined, Icons.home, 'Home',
                        reduceMotion, null),
                    _tab(1, Icons.receipt_long_outlined, Icons.receipt_long,
                        'History', reduceMotion, null),
                    _tab(2, Icons.handshake_outlined, Icons.handshake, 'Debts',
                        reduceMotion, debtCount),
                    _tab(3, Icons.shopping_cart_outlined, Icons.shopping_cart,
                        'Cart', reduceMotion, cartCount),
                    _tab(4, Icons.bar_chart_outlined, Icons.bar_chart, 'Stats',
                        reduceMotion, null),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(
    int i,
    IconData icon,
    IconData activeIcon,
    String label,
    bool reduceMotion,
    int? badgeCount,
  ) {
    final active = index == i;
    final showBadge = badgeCount != null && badgeCount > 0;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(i),
        child: Semantics(
          button: true,
          selected: active,
          label: showBadge ? '$label, $badgeCount items' : label,
          child: Center(
            child: AnimatedContainer(
              // Colour + transform only: no layout animation, no jank.
              duration: const Duration(milliseconds: 150),
              width: _kTabSize,
              height: _kTabSize,
              transform: (active && !reduceMotion)
                  ? Matrix4.translationValues(0, -_kTabLift, 0)
                  : null,
              decoration: BoxDecoration(
                // Flat emerald rounded box when active — deliberately NO
                // shadow/glow.
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(_kTabRadius),
                border: Border.all(color: AppColors.line),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    active ? activeIcon : icon,
                    size: _kTabIconSize,
                    color: active ? AppColors.inkOnPrimary : AppColors.text3,
                  ),
                  if (showBadge)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: _badge(badgeCount),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: const BoxDecoration(
        color: AppColors.gold,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.inkOnPrimary,
        ),
      ),
    );
  }
}

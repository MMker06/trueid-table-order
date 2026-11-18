import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/customer/menu_screen.dart';
import '../screens/customer/order_confirm_screen.dart';
import '../screens/customer/adult_verify_screen.dart';
import '../screens/customer/order_complete_screen.dart';
import '../screens/kitchen/kitchen_display_screen.dart';
import '../screens/merchant/merchant_login_screen.dart';
import '../screens/merchant/merchant_home_screen.dart';
import '../screens/merchant/menu_management_screen.dart';
import '../screens/setup/setup_screen.dart';
import '../store/auth_store.dart';
import '../store/table_config_store.dart';

// GoRouter는 한 번만 생성 — ChangeNotifier로 redirect만 재평가
class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
    _ref.listen<TableConfigState>(tableConfigProvider, (_, __) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final authState  = _ref.read(authProvider);
    final tableState = _ref.read(tableConfigProvider);

    // 초기화 중이면 대기
    if (authState.isInitializing || tableState.isLoading) return null;

    final path = state.uri.path;

    // 관리자 전용 라우트 — 인증 필요
    const merchantRoutes = ['/merchant/home', '/merchant/kitchen', '/merchant/menu'];
    if (merchantRoutes.contains(path) && !authState.isAuthenticated) {
      return '/merchant/login';
    }

    // 루트(/) → 설정 여부에 따라 분기
    if (path == '/') {
      if (tableState.isConfigured) {
        final c = tableState.config!;
        return '/menu?merchant_id=${c.merchantId}&table=${c.tableNumber}';
      }
      return '/setup';
    }

    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      // 스플래시 — redirect가 처리
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),

      // 초기 설정
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),

      // 고객 화면
      GoRoute(
        path: '/menu',
        builder: (ctx, state) {
          final merchantId = state.uri.queryParameters['merchant_id'] ?? '';
          final table      = state.uri.queryParameters['table'] ?? '1';
          return MenuScreen(merchantId: merchantId, tableNumber: table);
        },
      ),
      GoRoute(
        path: '/order-confirm',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return OrderConfirmScreen(
            merchantId:  extra['merchantId']  as String? ?? '',
            tableNumber: extra['tableNumber'] as String? ?? '1',
          );
        },
      ),
      GoRoute(
        path: '/adult-verify',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return AdultVerifyScreen(
            orderId:       extra['orderId']       as String? ?? '',
            requiredCount: extra['requiredCount'] as int?    ?? 1,
            merchantId:    extra['merchantId']    as String? ?? '',
            tableNumber:   extra['tableNumber']   as String? ?? '1',
            verifyMode:    extra['verifyMode']    as String? ?? 'mobile',
          );
        },
      ),
      GoRoute(
        path: '/order-complete',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return OrderCompleteScreen(
            orderId:     extra['orderId']     as String? ?? '',
            merchantId:  extra['merchantId']  as String? ?? '',
            tableNumber: extra['tableNumber'] as String? ?? '1',
          );
        },
      ),

      // 관리자 화면
      GoRoute(path: '/merchant/login',   builder: (_, __) => const MerchantLoginScreen()),
      GoRoute(path: '/merchant/home',    builder: (_, __) => const MerchantHomeScreen()),
      GoRoute(path: '/merchant/kitchen', builder: (_, __) => const KitchenDisplayScreen()),
      GoRoute(path: '/merchant/menu',    builder: (_, __) => const MenuManagementScreen()),
    ],
    errorBuilder: (ctx, state) => const SetupScreen(),
  );
});

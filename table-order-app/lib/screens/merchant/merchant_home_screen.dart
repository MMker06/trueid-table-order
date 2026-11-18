import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../store/auth_store.dart';
import '../../store/table_config_store.dart';

class MerchantHomeScreen extends ConsumerWidget {
  const MerchantHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState  = ref.watch(authProvider);
    final tableState = ref.watch(tableConfigProvider);

    final tableRoute = tableState.isConfigured
        ? '/menu?merchant_id=${tableState.config!.merchantId}&table=${tableState.config!.tableNumber}'
        : '/menu?merchant_id=${authState.merchantId ?? ''}&table=1';

    final tiles = [
      _Tile('주방 디스플레이', Icons.restaurant_menu_rounded, const Color(0xFF2563EB), '/merchant/kitchen'),
      _Tile('메뉴 관리', Icons.menu_book_rounded, const Color(0xFF059669), '/merchant/menu'),
      _Tile('고객 화면으로', Icons.tablet_android_rounded, const Color(0xFF7C3AED), tableRoute),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('패스체크 관리', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF94A3B8)),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              // 테이블 설정이 있으면 고객 화면으로, 없으면 로그인 화면으로
              context.go(tableState.isConfigured
                  ? '/menu?merchant_id=${tableState.config!.merchantId}&table=${tableState.config!.tableNumber}'
                  : '/merchant/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('안녕하세요,\n${authState.merchantName ?? '사장님'} 👋',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF111827), height: 1.4)),
          const Gap(28),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1,
              children: tiles.map((t) => _TileCard(tile: t)).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Tile {
  final String label;
  final IconData icon;
  final Color color;
  final String route;
  const _Tile(this.label, this.icon, this.color, this.route);
}

class _TileCard extends StatelessWidget {
  final _Tile tile;
  const _TileCard({super.key, required this.tile});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(tile.route),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: tile.color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(tile.icon, color: tile.color, size: 28),
          ),
          const Gap(12),
          Text(tile.label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1.4)),
        ]),
      ),
    );
  }
}

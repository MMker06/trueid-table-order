import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../store/auth_store.dart';
import '../../store/cart_store.dart';

final _menuProvider = FutureProvider.family<List<dynamic>, String>((ref, id) async {
  return ref.read(apiClientProvider).getPublicMenu(id);
});

class MenuScreen extends ConsumerStatefulWidget {
  final String merchantId;
  final String tableNumber;
  const MenuScreen({super.key, required this.merchantId, required this.tableNumber});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> with SingleTickerProviderStateMixin {
  TabController? _tabCtrl;
  int _tabLen = 0;

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(_menuProvider(widget.merchantId));
    final cartNotifier = ref.read(cartProvider.notifier);

    return menuAsync.when(
      loading: () => const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('메뉴 로드 실패: $e'))),
      data: (cats) {
        if (_tabLen != cats.length) {
          _tabCtrl?.dispose();
          _tabCtrl = TabController(length: cats.length, vsync: this);
          _tabLen = cats.length;
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF2F4F8),
          body: Column(children: [
            _AppHeader(tableNumber: widget.tableNumber),

            // 탭바
            Container(
              color: Colors.white,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
              ),
              child: TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFF2563EB),
                unselectedLabelColor: const Color(0xFFBDC1C9),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                indicator: const UnderlineTabIndicator(
                  borderSide: BorderSide(color: Color(0xFF2563EB), width: 3),
                  insets: EdgeInsets.symmetric(horizontal: 4),
                ),
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tabs: cats.map<Tab>((c) => Tab(
                  height: 44,
                  child: Text(c['name'] as String),
                )).toList(),
              ),
            ),

            // 메뉴 목록
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: cats.map<Widget>((cat) {
                  final items = cat['items'] as List<dynamic>;
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Gap(10),
                    itemBuilder: (_, i) => _ItemCard(item: items[i] as Map<String, dynamic>),
                  );
                }).toList(),
              ),
            ),
          ]),
          bottomNavigationBar: Consumer(
            builder: (ctx, ref, _) {
              final cart = ref.watch(cartProvider);
              if (cart.isEmpty) return const SizedBox.shrink();
              return _CartBar(
                count: cartNotifier.itemCount,
                total: cartNotifier.totalAmount,
                onTap: () => context.push('/order-confirm', extra: {
                  'merchantId': widget.merchantId,
                  'tableNumber': widget.tableNumber,
                }),
              );
            },
          ),
        );
      },
    );
  }
}

// 앱바
class _AppHeader extends ConsumerWidget {
  final String tableNumber;
  const _AppHeader({required this.tableNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20, topPad + 14, 8, 12),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('메뉴 주문', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
          Text('$tableNumber번 테이블', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ])),
        IconButton(
          icon: const Icon(Icons.settings_rounded, size: 18, color: Color(0xFFD1D5DB)),
          tooltip: '관리자',
          onPressed: () => showDialog(context: context, builder: (_) => const _AdminLoginDialog()),
        ),
      ]),
    );
  }
}

// 관리자 로그인 다이얼로그
class _AdminLoginDialog extends ConsumerStatefulWidget {
  const _AdminLoginDialog();

  @override
  ConsumerState<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends ConsumerState<_AdminLoginDialog> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(
        _phoneCtrl.text.trim(), _passCtrl.text,
      );
      if (mounted) {
        // router 참조를 팝 전에 가져와야 context가 유효
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.go('/merchant/home');
      }
    } catch (e) {
      setState(() {
        _error = '로그인 실패: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF2563EB), size: 22),
        Gap(8),
        Text('관리자 로그인', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: '전화번호',
              hintText: '01012341234',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const Gap(12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: '비밀번호',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _loading ? null : _login(),
          ),
          if (_error != null) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소', style: TextStyle(color: Color(0xFF6B7280))),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('로그인'),
        ),
      ],
    );
  }
}

// ── 메뉴 아이템 카드 ────────────────────────────────────────
class _ItemCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final qty = cart
        .where((e) => e.menuItemId == item['id'])
        .fold(0, (s, e) => s + e.quantity);
    final isAdult = item['is_adult_only'] as bool? ?? false;
    final imageUrl = item['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final price = (item['price'] as num).toInt();
    final desc = item['description'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isAdult
            ? Border.all(color: const Color(0xFFFBBF24), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── 텍스트 영역 ──────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // 성인 배지
                if (isAdult) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.local_bar_rounded,
                          size: 10, color: Color(0xFFD97706)),
                      Gap(3),
                      Text('성인 전용',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD97706))),
                    ]),
                  ),
                ],
                // 이름
                Text(item['name'] as String,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        height: 1.3)),
                // 설명
                if (desc.isNotEmpty) ...[
                  const Gap(4),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                          height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const Spacer(),
                const Gap(10),
                // 가격 + 수량 버튼
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('${_fmt(price)}원',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827))),
                      qty == 0
                          ? GestureDetector(
                              onTap: () =>
                                  ref.read(cartProvider.notifier).add(CartItem(
                                        menuItemId: item['id'] as String,
                                        name: item['name'] as String,
                                        price: price,
                                        isAdultOnly: isAdult,
                                      )),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_rounded,
                                          size: 15, color: Colors.white),
                                      Gap(3),
                                      Text('담기',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ]),
                              ),
                            )
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              _QtyBtn(
                                  icon: Icons.remove_rounded,
                                  onTap: () => ref
                                      .read(cartProvider.notifier)
                                      .remove(item['id'] as String)),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                child: Text('$qty',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2563EB))),
                              ),
                              _QtyBtn(
                                  icon: Icons.add_rounded,
                                  filled: true,
                                  onTap: () =>
                                      ref.read(cartProvider.notifier).add(
                                            CartItem(
                                              menuItemId: item['id'] as String,
                                              name: item['name'] as String,
                                              price: price,
                                              isAdultOnly: isAdult,
                                            ),
                                          )),
                            ]),
                    ]),
              ]),
            ),
          ),

          // ── 이미지 영역 (카드 전체 높이) ───────────────
          if (hasImage)
            SizedBox(
              width: 120,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFF3F4F6),
                  child: const Icon(Icons.restaurant_rounded,
                      size: 32, color: Color(0xFFD1D5DB)),
                ),
              ),
            )
          else
            // 이미지 없을 때 플레이스홀더
            Container(
              width: 80,
              color: const Color(0xFFF9FAFB),
              child: const Icon(Icons.restaurant_menu_rounded,
                  size: 32, color: Color(0xFFE5E7EB)),
            ),
        ]),
      ),
    );
  }

  String _fmt(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _QtyBtn({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
        color: filled ? const Color(0xFF2563EB) : null,
        border: filled ? null : Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: filled ? Colors.white : const Color(0xFF6B7280)),
    ),
  );
}

class _CartBar extends StatelessWidget {
  final int count;
  final int total;
  final VoidCallback onTap;
  const _CartBar({required this.count, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Color(0x18000000), blurRadius: 20, offset: Offset(0, -6))],
    ),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF4338CA)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Center(child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
          const Text('주문하기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          Text('${_fmt(total)}원', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
    ),
  );

  String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../store/auth_store.dart';

final _merchantStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    return await api.getMerchantStats();
  } catch (_) {
    return {'total_id_checks': 0, 'genuine_count': 0, 'forged_count': 0, 'completed_verifications': 0};
  }
});

class MerchantManagementScreen extends ConsumerStatefulWidget {
  const MerchantManagementScreen({super.key});

  @override
  ConsumerState<MerchantManagementScreen> createState() => _MerchantManagementScreenState();
}

class _MerchantManagementScreenState extends ConsumerState<MerchantManagementScreen> {
  int _navIndex = 2;

  final _menuCategories = ['전체 메뉴', '음료', '디저트', '식사'];
  int _selectedCat = 0;

  final _menus = [
    {'name': '아이스 아메리카노', 'price': '4,500', 'available': true},
    {'name': '카페 라떼', 'price': '5,000', 'available': true},
    {'name': '바나나 라떼', 'price': '5,500', 'available': false},
    {'name': '마드리드 라테', 'price': '5,500', 'available': true},
    {'name': '바닐라 라떼', 'price': '5,500', 'available': true},
  ];

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final stats = ref.watch(_merchantStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('매장 관리 페이지',
                style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 16)),
            Text('${auth.userName ?? ''}님, 매장 정보를 관리하세요',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Color(0xFF374151)),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF374151)),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 섹션 1: 매장 정보 설정
            _SectionCard(
              number: '1',
              title: '매장 정보 설정',
              subtitle: '매장 기본 정보 및 운영 정보를 설정하세요',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('매장 정보 수정',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                subtitle: const Text('영업시간, 위치, 연락처 등',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
                onTap: () {},
              ),
            ),
            const Gap(12),
            // 섹션 2: 메뉴판 관리
            _SectionCard(
              number: '2',
              title: '메뉴판 관리',
              subtitle: '카테고리, 메뉴를 수정하고 관리하세요',
              child: Column(
                children: [
                  // 카테고리 필터
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _menuCategories.length,
                      separatorBuilder: (_, __) => const Gap(8),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => setState(() => _selectedCat = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _selectedCat == i ? const Color(0xFF2563EB) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(_menuCategories[i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _selectedCat == i ? Colors.white : const Color(0xFF6B7280),
                              )),
                        ),
                      ),
                    ),
                  ),
                  const Gap(12),
                  // 메뉴 목록
                  ..._menus.map((menu) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(menu['name'] as String,
                              style: TextStyle(
                                fontSize: 14,
                                color: (menu['available'] as bool) ? const Color(0xFF374151) : const Color(0xFF9CA3AF),
                              )),
                        ),
                        Text(menu['price'] as String,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                        const Gap(12),
                        Switch(
                          value: menu['available'] as bool,
                          onChanged: (_) {},
                          activeColor: const Color(0xFF2563EB),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  )),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add, size: 16, color: Color(0xFF2563EB)),
                    label: const Text('메뉴 추가', style: TextStyle(color: Color(0xFF2563EB), fontSize: 13)),
                  ),
                ],
              ),
            ),
            const Gap(12),
            // 섹션 3: 인증 현황
            _SectionCard(
              number: '3',
              title: '인증 현황',
              subtitle: '오늘 손님들의 인증 현황을 확인하세요',
              child: stats.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('오류: $e', style: const TextStyle(color: Colors.red)),
                data: (data) => Column(
                  children: [
                    Row(
                      children: [
                        _StatChip(label: '오늘', value: '${data['total_id_checks']}건', color: const Color(0xFF2563EB)),
                        const Gap(8),
                        _StatChip(label: 'QR 코드', value: '${data['forged_count'] ?? 3}개', color: const Color(0xFF7C3AED)),
                        const Gap(8),
                        _StatChip(label: '방문객', value: '${data['completed_verifications']}명', color: const Color(0xFF059669)),
                      ],
                    ),
                    const Gap(12),
                    // 미니 차트 (더미)
                    Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [0.3, 0.5, 0.4, 0.8, 0.6, 0.9, 1.0].map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 8),
                          child: Container(
                            width: 20,
                            height: 44 * h,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withOpacity(0.2 + h * 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                    const Gap(12),
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('인증 내역 상세보기',
                          style: TextStyle(fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(80),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) {
          setState(() => _navIndex = i);
          if (i == 4) context.push('/settings');
        },
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF2563EB).withOpacity(0.1),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '홈'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: '주문 관리'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: '매장 관리'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: '고객 통계'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '설정'),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
              child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
            ),
            const Gap(10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ]),
          const Gap(16),
          const Divider(color: Color(0xFFF3F4F6)),
          const Gap(8),
          child,
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          const Gap(2),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ]),
      ),
    );
  }
}

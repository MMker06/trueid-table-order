import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

final _statsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // 실제로는 api_client에서 가져옴 — 여기선 더미 데이터
  await Future.delayed(const Duration(milliseconds: 600));
  return {
    'total_id_checks': 342,
    'genuine_count': 335,
    'forged_count': 7,
    'completed_verifications': 328,
  };
});

class MerchantDashboardScreen extends ConsumerWidget {
  const MerchantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(_statsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
        title: const Text('매장 관리', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.exit_to_app, color: Colors.white54),
            label: const Text('닫기', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('오늘의 인증 현황', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white, fontWeight: FontWeight.w700,
            )),
            const Gap(24),
            stats.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e', style: const TextStyle(color: Colors.red)),
              data: (data) => _StatsGrid(data: data),
            ),
            const Gap(40),
            Text('최근 인증 이력', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white, fontWeight: FontWeight.w700,
            )),
            const Gap(16),
            Expanded(child: _RecentLogTable()),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StatsGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(label: '전체 신분증 검사', value: '${data['total_id_checks']}건', icon: Icons.badge, color: const Color(0xFF1A73E8)),
      _StatCard(label: '정품 신분증', value: '${data['genuine_count']}건', icon: Icons.check_circle_outline, color: const Color(0xFF2EA84A)),
      _StatCard(label: '위변조 의심', value: '${data['forged_count']}건', icon: Icons.warning_amber_rounded, color: const Color(0xFFE53935)),
      _StatCard(label: '인증 완료', value: '${data['completed_verifications']}건', icon: Icons.verified_user, color: const Color(0xFF8B5CF6)),
    ];

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 2.0,
      children: cards,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const Gap(16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentLogTable extends StatelessWidget {
  final _dummyLogs = const [
    {'time': '14:32', 'type': '주민등록증', 'result': true, 'method': '얼굴'},
    {'time': '14:18', 'type': '운전면허증', 'result': true, 'method': '지문'},
    {'time': '13:55', 'type': '주민등록증', 'result': false, 'method': '-'},
    {'time': '13:42', 'type': '주민등록증', 'result': true, 'method': '얼굴'},
    {'time': '13:30', 'type': '운전면허증', 'result': true, 'method': '지문'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1C2130),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 1, child: Text('시간', style: TextStyle(color: Colors.white54, fontSize: 13))),
                Expanded(flex: 2, child: Text('신분증 종류', style: TextStyle(color: Colors.white54, fontSize: 13))),
                Expanded(flex: 2, child: Text('신분증 판별', style: TextStyle(color: Colors.white54, fontSize: 13))),
                Expanded(flex: 2, child: Text('생체 인증', style: TextStyle(color: Colors.white54, fontSize: 13))),
              ],
            ),
          ),
          // 행
          Expanded(
            child: ListView.separated(
              itemCount: _dummyLogs.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF21262D), height: 1),
              itemBuilder: (_, i) {
                final log = _dummyLogs[i];
                final ok = log['result'] as bool;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: Text(log['time'] as String, style: const TextStyle(color: Colors.white70))),
                      Expanded(flex: 2, child: Text(log['type'] as String, style: const TextStyle(color: Colors.white70))),
                      Expanded(
                        flex: 2,
                        child: Row(children: [
                          Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? const Color(0xFF2EA84A) : const Color(0xFFE53935), size: 16),
                          const Gap(6),
                          Text(ok ? '정품' : '위변조 의심', style: TextStyle(color: ok ? const Color(0xFF2EA84A) : const Color(0xFFE53935))),
                        ]),
                      ),
                      Expanded(flex: 2, child: Text(log['method'] as String, style: const TextStyle(color: Colors.white70))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

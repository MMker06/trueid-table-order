import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../services/api_client.dart';
import '../../store/auth_store.dart';

final _kitchenOrdersProvider = FutureProvider.autoDispose.family<List<dynamic>, String>((ref, merchantId) async {
  return ref.read(apiClientProvider).getKitchenOrders(merchantId);
});

class KitchenDisplayScreen extends ConsumerStatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  ConsumerState<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends ConsumerState<KitchenDisplayScreen> {
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => setState(() => _tick++));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _statusColor(String status) => switch (status) {
    'confirmed' => const Color(0xFF2563EB),
    'preparing' => const Color(0xFFD97706),
    'ready' => const Color(0xFF059669),
    _ => const Color(0xFF6B7280),
  };

  String _statusLabel(String status) => switch (status) {
    'confirmed' => '접수됨',
    'preparing' => '준비 중',
    'ready' => '서빙 대기',
    'done' => '완료',
    _ => status,
  };

  String _nextStatus(String status) => switch (status) {
    'confirmed' => 'preparing',
    'preparing' => 'ready',
    'ready' => 'done',
    _ => status,
  };

  String _nextLabel(String status) => switch (status) {
    'confirmed' => '준비 시작',
    'preparing' => '서빙 준비',
    'ready' => '서빙 완료',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final merchantId = authState.merchantId;

    if (merchantId == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    final orders = ref.watch(_kitchenOrdersProvider(merchantId + _tick.toString()));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(children: [
          const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 20),
          const Gap(10),
          Text(authState.merchantName ?? '주방 디스플레이',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          const Spacer(),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
          const Gap(6),
          const Text('실시간', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        ]),
      ),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('불러오기 실패: $e')),
        data: (list) {
          final active = list.where((o) => o['status'] != 'done' && o['status'] != 'cancelled').toList();
          if (active.isEmpty) {
            return const Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_outline_rounded, size: 72, color: Color(0xFF94A3B8)),
                Gap(16),
                Text('현재 주문이 없습니다', style: TextStyle(color: Color(0xFF6B7280), fontSize: 16)),
              ]),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: active.length,
            itemBuilder: (ctx, i) {
              final o = active[i] as Map<String, dynamic>;
              final status = o['status'] as String;
              final items = o['items'] as List? ?? [];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: _statusColor(status).withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(status),
                            style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const Spacer(),
                      Text('테이블 ${o['table_number']}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                    ]),
                    const Divider(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, j) {
                          final item = items[j] as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              if (item['is_adult_only'] == true)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('성인', style: TextStyle(fontSize: 9, color: Color(0xFFD97706), fontWeight: FontWeight.w700)),
                                ),
                              Expanded(child: Text(item['name'] as String,
                                  style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
                              Text('×${item['quantity']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            ]),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 8),
                    if (status != 'done')
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            await ref.read(apiClientProvider).updateOrderStatus(o['id'] as String, _nextStatus(status));
                            setState(() => _tick++);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _statusColor(status),
                            minimumSize: const Size(double.infinity, 40),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(_nextLabel(status), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

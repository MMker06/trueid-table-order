import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/web_camera.dart';
import '../../store/cart_store.dart';

enum _FaceState { idle, scanning, freePass, noPass, failed }

class OrderConfirmScreen extends ConsumerStatefulWidget {
  final String merchantId;
  final String tableNumber;
  const OrderConfirmScreen(
      {super.key, required this.merchantId, required this.tableNumber});

  @override
  ConsumerState<OrderConfirmScreen> createState() =>
      _OrderConfirmScreenState();
}

class _OrderConfirmScreenState extends ConsumerState<OrderConfirmScreen> {
  bool _submitting = false;
  _FaceState _faceState = _FaceState.idle;
  int? _estimatedAge;
  String? _aiLabel;
  String? _aiReason;

  static const _faceAiEnabled = true;

  @override
  void initState() {
    super.initState();
    if (_faceAiEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(cartProvider.notifier).hasAdultItems) {
          _runFaceScan();
        }
      });
    } else {
      _faceState = _FaceState.noPass;
    }
  }

  Future<void> _runFaceScan() async {
    setState(() => _faceState = _FaceState.scanning);
    try {
      final cam = WebCamera(label: '카메라를 얼굴에 맞춰주세요');
      final bytes = await cam.captureOnce();
      if (!mounted) return;

      final result = await ref
          .read(apiClientProvider)
          .estimateAge(bytes)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      final age = result['age'] as int?;
      final freePass = result['free_pass'] == true;
      final label = result['class'] as String?;
      final reason = result['reason'] as String?;
      setState(() {
        _estimatedAge = age;
        _aiLabel = label;
        _aiReason = reason;
        _faceState = freePass ? _FaceState.freePass : _FaceState.noPass;
      });
    } catch (e, st) {
      print('[FaceScan ERROR] $e\n$st');
      if (!mounted) return;
      setState(() => _faceState = _FaceState.failed);
    }
  }

  bool get _canOrder {
    final hasAdult = ref.read(cartProvider.notifier).hasAdultItems;
    if (!hasAdult) return true;
    // 프리패스이면 바로 주문 가능
    if (_faceState == _FaceState.freePass) return true;
    // 스캔 중엔 비활성
    if (_faceState == _FaceState.scanning) return false;
    // 나머지(noPass/failed/idle)는 방식 선택 후 주문 가능
    return true;
  }

  Future<void> _submitOrder() async {
    setState(() => _submitting = true);
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final freePass = _faceState == _FaceState.freePass;

    try {
      final result = await ref.read(apiClientProvider).createOrder({
        'merchant_id': widget.merchantId,
        'table_number': widget.tableNumber,
        'adult_count': cartNotifier.hasAdultItems ? 1 : 0,
        'ai_adult_verified': freePass,
        'items': cart
            .map((e) => {
                  'menu_item_id': e.menuItemId,
                  'name': e.name,
                  'price': e.price,
                  'quantity': e.quantity,
                  'is_adult_only': e.isAdultOnly,
                })
            .toList(),
      });
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;

      if (result['requires_adult_verify'] == true) {
        context.go('/adult-verify', extra: {
          'orderId': result['id'],
          'requiredCount': result['adult_verify_count'],
          'merchantId': widget.merchantId,
          'tableNumber': widget.tableNumber,
          'verifyMode': 'mobile',
        });
      } else {
        context.go('/order-complete', extra: {
          'orderId': result['id'],
          'merchantId': widget.merchantId,
          'tableNumber': widget.tableNumber,
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('주문 실패: $e')));
    }
  }

  String _fmt(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final hasAdult = cartNotifier.hasAdultItems;

    String btnLabel;
    if (!hasAdult) {
      btnLabel = '주문하기';
    } else if (_faceState == _FaceState.scanning) {
      btnLabel = 'AI 확인 중...';
    } else if (_faceState == _FaceState.freePass) {
      btnLabel = '주문하기';
    } else {
      btnLabel = '주문 후 모바일 인증';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF111827)),
          onPressed: () => context.pop(),
        ),
        title: const Text('주문 확인',
            style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        centerTitle: true,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // ── 성인 인증 섹션 ────────────────────────────────
        if (hasAdult) ...[
          _buildAdultSection(),
          const Gap(16),
        ],

        // ── 주문 목록 ────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04), blurRadius: 10)
            ],
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 16, color: Color(0xFF6B7280)),
              const Gap(6),
              const Text('주문 내역',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151))),
            ]),
            const Gap(14),
            ...cart.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    if (item.isAdultOnly)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('성인',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFD97706))),
                      ),
                    Expanded(
                        child: Text('${item.name}  ×${item.quantity}',
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF374151)))),
                    Text('${_fmt(item.total)}원',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                )),
            const Divider(height: 8),
            const Gap(8),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('합계',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${_fmt(cartNotifier.totalAmount)}원',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2563EB))),
                ]),
          ]),
        ),
        const Gap(100),
      ]),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Color(0x12000000),
                blurRadius: 16,
                offset: Offset(0, -4))
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: (_submitting || !_canOrder) ? null : _submitOrder,
            style: FilledButton.styleFrom(
              backgroundColor: _canOrder
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFD1D5DB),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: _submitting
                ? const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5)
                : Text(btnLabel,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  Widget _buildAdultSection() {
    switch (_faceState) {
      // ── 스캔 중 ────────────────────────────────────────
      case _FaceState.scanning:
      case _FaceState.idle:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFBFDBFE)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04), blurRadius: 10)
            ],
          ),
          child: Row(children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Color(0xFF2563EB)),
            ),
            const Gap(14),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('AI 나이 확인 중...',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A8A))),
                  Gap(2),
                  Text('카메라로 얼굴을 인식하고 있습니다',
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ])),
          ]),
        );

      // ── 프리패스 ────────────────────────────────────────
      case _FaceState.freePass:
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                  color: Color(0xFF10B981), shape: BoxShape.circle),
              child: const Icon(Icons.face_rounded,
                  color: Colors.white, size: 26),
            ),
            const Gap(14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('성인 인증 면제',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF065F46))),
                  Text(
                      _aiReason ?? 'AI 분석 완료 — 신분증 없이 주문 가능',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF059669))),
                ])),
            TextButton(
              onPressed: _runFaceScan,
              child: const Text('재확인',
                  style: TextStyle(fontSize: 12, color: Color(0xFF059669))),
            ),
          ]),
        );

      // ── 실패 / 나이 미달 → 방식 선택 ─────────────────────
      case _FaceState.noPass:
      case _FaceState.failed:
        return _MethodSelector(
          age: _estimatedAge,
          aiReason: _aiReason,
          scanFailed: _faceState == _FaceState.failed,
          onRescan: _runFaceScan,
        );
    }
  }
}

// ── 방식 선택 카드 ─────────────────────────────────────────────
class _MethodSelector extends StatelessWidget {
  final int? age;
  final String? aiReason;
  final bool scanFailed;
  final VoidCallback onRescan;

  const _MethodSelector({
    required this.age,
    required this.scanFailed,
    required this.onRescan,
    this.aiReason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFBBF24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            const Icon(Icons.badge_rounded,
                color: Color(0xFFD97706), size: 20),
            const Gap(8),
            Expanded(
              child: Text(
                scanFailed
                    ? '얼굴 인식 실패 — 신분증으로 인증하세요'
                    : (aiReason ?? '성인 신분증 확인 필요'),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827)),
              ),
            ),
            TextButton(
              onPressed: onRescan,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('재인식',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ),
          ]),
        ),

        const Gap(10),
        const Divider(height: 1),
        const Gap(10),

        // 안내 문구
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '주문 후 스마트폰 QR 인증으로 모바일 신분증을 확인합니다.',
                style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5),
              ),
              const Gap(8),
              Wrap(spacing: 6, children: [
                _Chip(
                    icon: Icons.verified_user_rounded,
                    label: '카카오',
                    color: const Color(0xFF0064D2)),
                _Chip(
                    icon: Icons.smartphone_rounded,
                    label: '정부24',
                    color: const Color(0xFF00B050)),
                _Chip(
                    icon: Icons.security_rounded,
                    label: 'PASS',
                    color: const Color(0xFFE60012)),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _Tab(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 4)
                    ]
                  : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon,
                  size: 14,
                  color: active
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF9CA3AF)),
              const Gap(5),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF9CA3AF),
                  )),
            ]),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const Gap(4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      );
}

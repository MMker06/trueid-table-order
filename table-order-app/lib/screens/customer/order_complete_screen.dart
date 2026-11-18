import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class OrderCompleteScreen extends StatelessWidget {
  final String orderId;
  final String merchantId;
  final String tableNumber;

  const OrderCompleteScreen({
    super.key,
    required this.orderId,
    required this.merchantId,
    required this.tableNumber,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 100, height: 100,
                decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 56, color: Colors.white),
              ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
              const Gap(32),
              const Text('주문 완료!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827)))
                  .animate().fadeIn(delay: 300.ms),
              const Gap(12),
              const Text('주문이 접수되었습니다.\n잠시 후 음식이 나옵니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF6B7280), height: 1.6))
                  .animate().fadeIn(delay: 400.ms),
              const Gap(48),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go(
                    '/menu?merchant_id=$merchantId&table=$tableNumber',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('추가 주문하기',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ).animate().fadeIn(delay: 500.ms),
            ]),
          ),
        ),
      ),
    );
  }
}

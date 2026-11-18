import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../store/auth_store.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Gap(60),
              // 로고
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.verified_user_rounded, size: 44, color: Color(0xFF2563EB)),
              ),
              const Gap(20),
              const Text(
                '패스체크',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -0.5),
              ),
              const Gap(8),
              const Text(
                '신분 확인, 더 쉽고 안전하게',
                style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
              ),
              const Gap(56),
              // 손님 버튼
              _EntryCard(
                icon: Icons.person_outline_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
                title: '손님으로 시작하기',
                subtitle: '간편하게 신분 인증을 하고\n매장을 이용하세요.',
                onTap: () {
                  if (auth.isAuthenticated && auth.userRole == 'customer') {
                    context.push('/id-scan');
                  } else {
                    context.push('/login-customer');
                  }
                },
              ),
              const Gap(16),
              // 매장 버튼
              _EntryCard(
                icon: Icons.storefront_outlined,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
                title: '매장으로 시작하기',
                subtitle: '매장 인증을 관리하여\n손님을 안전하게 맞이하세요.',
                onTap: () {
                  if (auth.isAuthenticated && auth.userRole == 'merchant') {
                    context.push('/merchant');
                  } else {
                    context.push('/login-merchant');
                  }
                },
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 14, color: Color(0xFF9CA3AF)),
                  const Gap(6),
                  const Text(
                    '안전한 인증, 신뢰하는 공간  패스체크가 함께합니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
              const Gap(24),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                  const Gap(4),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF), size: 24),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../store/auth_store.dart';

class MyPageScreen extends ConsumerWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF111827)),
          onPressed: () => context.pop(),
        ),
        title: const Text('설정', style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 헤더 프로필
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, size: 28, color: Color(0xFF2563EB)),
                  ),
                  const Gap(16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.userName ?? '사용자', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                        const Gap(2),
                        Text(auth.userRole == 'merchant' ? '매장 운영자' : '손님',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: auth.userRole == 'merchant'
                          ? const Color(0xFFF0FDF4)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      auth.userRole == 'merchant' ? '매장 운영자' : '손님',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: auth.userRole == 'merchant' ? const Color(0xFF059669) : const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(8),
            // 설정 그룹 안내
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('계정과 보안을 관리하세요',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ),
            ),
            // 메뉴 그룹 1
            _MenuGroup(items: [
              _MenuItem(
                icon: Icons.person_outline_rounded,
                iconColor: const Color(0xFF2563EB),
                label: '내 정보 수정',
                subtitle: '이름, 연락처, 이미지 등',
                onTap: () => _showBiometricConfirm(context),
              ),
              _MenuItem(
                icon: Icons.lock_outline_rounded,
                iconColor: const Color(0xFF7C3AED),
                label: '비밀번호 변경',
                onTap: () {},
              ),
            ]),
            const Gap(8),
            _MenuGroup(items: [
              _MenuItem(
                icon: Icons.notifications_outlined,
                iconColor: const Color(0xFFF59E0B),
                label: '알림 설정',
                onTap: () {},
              ),
              _MenuItem(
                icon: Icons.security_outlined,
                iconColor: const Color(0xFF059669),
                label: '보안 설정',
                onTap: () {},
              ),
            ]),
            const Gap(8),
            _MenuGroup(items: [
              _MenuItem(
                icon: Icons.headset_mic_outlined,
                iconColor: const Color(0xFF6B7280),
                label: '고객센터',
                onTap: () {},
              ),
              _MenuItem(
                icon: Icons.info_outline_rounded,
                iconColor: const Color(0xFF6B7280),
                label: '앱 정보',
                subtitle: 'v1.0.0',
                onTap: () {},
              ),
            ]),
            const Gap(8),
            _MenuGroup(items: [
              _MenuItem(
                icon: Icons.logout_rounded,
                iconColor: const Color(0xFFEF4444),
                label: '로그아웃',
                labelColor: const Color(0xFFEF4444),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('로그아웃'),
                      content: const Text('로그아웃 하시겠습니까?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        TextButton(onPressed: () => Navigator.pop(context, true),
                            child: const Text('로그아웃', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await ref.read(authProvider.notifier).logout();
                    context.go('/');
                  }
                },
              ),
            ]),
            const Gap(32),
          ],
        ),
      ),
    );
  }

  void _showBiometricConfirm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const Gap(20),
            const Text('생체 인증', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Gap(8),
            const Text('정보 수정을 위해 본인 인증이 필요합니다.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
            const Gap(28),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _BiometricOption(icon: Icons.face_retouching_natural_rounded, label: '얼굴 인증'),
              Container(width: 1, height: 60, color: const Color(0xFFE5E7EB)),
              _BiometricOption(icon: Icons.fingerprint_rounded, label: '지문 인증'),
            ]),
            const Gap(20),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('취소', style: TextStyle(color: Color(0xFF374151))),
            ),
          ],
        ),
      ),
    );
  }
}

class _BiometricOption extends StatelessWidget {
  final IconData icon;
  final String label;
  const _BiometricOption({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: const Color(0xFF2563EB), size: 30),
        ),
        const Gap(8),
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
      ]),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: items.map((item) {
          final isLast = item == items.last;
          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: item.iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(item.icon, color: item.iconColor, size: 18),
                ),
                title: Text(item.label,
                    style: TextStyle(fontSize: 15, color: item.labelColor ?? const Color(0xFF111827), fontWeight: FontWeight.w500)),
                subtitle: item.subtitle != null
                    ? Text(item.subtitle!, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))
                    : null,
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFD1D5DB), size: 20),
                onTap: item.onTap,
              ),
              if (!isLast)
                const Divider(height: 1, indent: 72, endIndent: 20, color: Color(0xFFF3F4F6)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final String? subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
    this.subtitle,
    required this.onTap,
  });
}

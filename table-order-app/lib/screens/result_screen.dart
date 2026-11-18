import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class ResultScreen extends StatefulWidget {
  final bool success;
  const ResultScreen({super.key, required this.success});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Timer? _autoReturn;

  @override
  void initState() {
    super.initState();
    if (widget.success) {
      _autoReturn = Timer(const Duration(seconds: 5), () {
        if (mounted) context.go('/');
      });
    }
  }

  @override
  void dispose() {
    _autoReturn?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: widget.success ? _SuccessView() : _FailureView(),
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 64, color: Color(0xFF16A34A)),
        ).animate().scale(begin: const Offset(0.5, 0.5), duration: 500.ms, curve: Curves.elasticOut).fadeIn(duration: 300.ms),
        const Gap(28),
        const Text('성인 인증 완료',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF111827)))
            .animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),
        const Gap(10),
        const Text('성인 인증이 확인되었습니다\n이용해 주셔서 감사합니다',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 15, height: 1.6))
            .animate(delay: 300.ms).fadeIn(),
        const Gap(40),
        _AutoReturnTimer().animate(delay: 400.ms).fadeIn(),
        const Gap(20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.go('/'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            child: const Text('확인'),
          ),
        ).animate(delay: 500.ms).fadeIn(),
      ],
    );
  }
}

class _AutoReturnTimer extends StatefulWidget {
  @override
  State<_AutoReturnTimer> createState() => _AutoReturnTimerState();
}

class _AutoReturnTimerState extends State<_AutoReturnTimer> {
  int _count = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_count <= 1) { t.cancel(); return; }
      setState(() => _count--);
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) =>
      Text('${_count}초 후 자동으로 돌아갑니다',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13));
}

class _FailureView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120, height: 120,
          decoration: const BoxDecoration(color: Color(0xFFFEE2E2), shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 64, color: Color(0xFFDC2626)),
        ).animate()
            .scale(begin: const Offset(0.5, 0.5), duration: 500.ms, curve: Curves.elasticOut)
            .shake(hz: 3, offset: const Offset(4, 0))
            .fadeIn(duration: 300.ms),
        const Gap(28),
        const Text('인증 실패',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF111827)))
            .animate(delay: 200.ms).fadeIn(),
        const Gap(10),
        const Text('인증에 실패했습니다\n신분증 또는 생체 정보를 다시 확인해주세요',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 15, height: 1.6))
            .animate(delay: 300.ms).fadeIn(),
        const Gap(40),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.go('/'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  foregroundColor: const Color(0xFF374151),
                ),
                child: const Text('처음으로'),
              ),
            ),
            const Gap(12),
            Expanded(
              child: FilledButton(
                onPressed: () => context.go('/id-scan'),
                child: const Text('다시 시도'),
              ),
            ),
          ],
        ).animate(delay: 400.ms).fadeIn(),
      ],
    );
  }
}

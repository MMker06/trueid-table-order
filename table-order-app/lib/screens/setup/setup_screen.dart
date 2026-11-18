import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../store/auth_store.dart';
import '../../store/table_config_store.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _tableCtrl = TextEditingController(text: '1');

  int _step = 0; // 0: 로그인, 1: 테이블 번호 설정
  bool _loading = false;
  String? _error;
  String? _merchantId;
  String? _merchantName;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _tableCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ref.read(authProvider.notifier).loginRaw(
        _phoneCtrl.text.trim(), _passCtrl.text,
      );
      _merchantId   = r['merchantId'] as String;
      _merchantName = r['merchantName'] as String;
      setState(() { _step = 1; _loading = false; });
    } catch (e) {
      setState(() {
        _error = '로그인 실패: $e';
        _loading = false;
      });
    }
  }

  Future<void> _complete() async {
    final table = _tableCtrl.text.trim();
    if (table.isEmpty) {
      setState(() => _error = '테이블 번호를 입력해 주세요.');
      return;
    }
    await ref.read(tableConfigProvider.notifier).save(
      _merchantId!,
      table,
      _merchantName!,
    );
    await ref.read(authProvider.notifier).logout();
    if (mounted) {
      context.go('/menu?merchant_id=$_merchantId&table=$table');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.tablet_android_rounded, color: Colors.white, size: 38),
              ),
              const Gap(16),
              const Text('패스체크', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
              const Text('테이블 오더 초기 설정', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const Gap(40),

              // 단계 표시
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _StepDot(active: _step == 0, done: _step > 0, label: '1'),
                Container(width: 40, height: 2,
                    color: _step > 0 ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB)),
                _StepDot(active: _step == 1, done: false, label: '2'),
              ]),
              const Gap(8),
              Text(
                _step == 0 ? '관리자 로그인' : '테이블 번호 설정',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
              ),
              const Gap(28),

              if (_step == 0) ...[
                _field('전화번호', _phoneCtrl, TextInputType.phone, '01012341234'),
                const Gap(12),
                _field('비밀번호', _passCtrl, TextInputType.text, '비밀번호', obscure: true),
                const Gap(24),
                if (_error != null) _errorBox(_error!),
                _btn('다음', _loading ? null : _login),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.store_rounded, size: 18, color: Color(0xFF2563EB)),
                      const Gap(8),
                      Text(_merchantName ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    const Gap(16),
                    const Text('이 기기의 테이블 번호',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                    const Gap(8),
                    TextField(
                      controller: _tableCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        suffixText: '번 테이블',
                        suffixStyle: const TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                        filled: true, fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
                      ),
                    ),
                  ]),
                ),
                const Gap(12),
                const Text('다른 기기에는 다른 번호를 설정하세요',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                const Gap(20),
                if (_error != null) _errorBox(_error!),
                _btn('설정 완료 — 주문 시작', _loading ? null : _complete),
                const Gap(12),
                TextButton(
                  onPressed: () => setState(() { _step = 0; _error = null; }),
                  child: const Text('← 다시 로그인', style: TextStyle(color: Color(0xFF6B7280))),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, TextInputType type, String hint, {bool obscure = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
        const Gap(6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          obscureText: obscure,
          inputFormatters: type == TextInputType.phone ? [FilteringTextInputFormatter.digitsOnly] : [],
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
            filled: true, fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
          ),
        ),
      ]);

  Widget _errorBox(String msg) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
    child: Text(msg, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
  );

  Widget _btn(String label, VoidCallback? onTap) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: const Color(0xFF2563EB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _loading
          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
          : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    ),
  );
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;
  const _StepDot({required this.active, required this.done, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = (active || done) ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB);
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: done
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : Text(label, style: TextStyle(color: (active || done) ? Colors.white : const Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.w700))),
    );
  }
}

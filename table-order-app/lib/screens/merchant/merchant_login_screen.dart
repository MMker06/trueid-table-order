import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../store/auth_store.dart';

class MerchantLoginScreen extends ConsumerStatefulWidget {
  const MerchantLoginScreen({super.key});

  @override
  ConsumerState<MerchantLoginScreen> createState() => _MerchantLoginScreenState();
}

class _MerchantLoginScreenState extends ConsumerState<MerchantLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSignup = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose(); _passCtrl.dispose(); _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      final notifier = ref.read(authProvider.notifier);
      if (_isSignup) {
        await notifier.signup(_phoneCtrl.text.trim(), _nameCtrl.text.trim(), _passCtrl.text);
      } else {
        await notifier.login(_phoneCtrl.text.trim(), _passCtrl.text);
      }
      if (!mounted) return;
      context.go('/merchant/home');
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
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
              // 로고
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 38),
              ),
              const Gap(20),
              const Text('패스체크', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
              const Text('사장님 전용 관리 시스템', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const Gap(40),

              // 탭
              Container(
                decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(4),
                child: Row(children: [
                  _tab('로그인', !_isSignup, () => setState(() => _isSignup = false)),
                  _tab('회원가입', _isSignup, () => setState(() => _isSignup = true)),
                ]),
              ),
              const Gap(28),

              // 입력 필드
              if (_isSignup) ...[
                _field('이름', _nameCtrl, TextInputType.name, '홍길동'),
                const Gap(12),
              ],
              _field('전화번호', _phoneCtrl, TextInputType.phone, '01012341234'),
              const Gap(12),
              _field('비밀번호', _passCtrl, TextInputType.text, '비밀번호', obscure: true),
              const Gap(24),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                ),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                      : Text(_isSignup ? '회원가입' : '로그인', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))] : [],
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? const Color(0xFF111827) : const Color(0xFF9CA3AF), fontSize: 14)),
      ),
    ),
  );

  Widget _field(String label, TextEditingController ctrl, TextInputType type, String hint, {bool obscure = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
    ],
  );
}

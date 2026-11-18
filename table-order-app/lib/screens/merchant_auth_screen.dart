import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../store/auth_store.dart';

class MerchantAuthScreen extends ConsumerStatefulWidget {
  const MerchantAuthScreen({super.key});

  @override
  ConsumerState<MerchantAuthScreen> createState() => _MerchantAuthScreenState();
}

enum _Step { login, register }

class _MerchantAuthScreenState extends ConsumerState<MerchantAuthScreen> {
  _Step _step = _Step.login;
  bool _loading = false;
  bool _obscure = true;

  // 로그인
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // 회원가입
  final _regNameCtrl = TextEditingController();
  final _regPhoneCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  int _signupStep = 1; // 1:계정생성 2:매장등록

  // 매장등록
  final _bizNameCtrl = TextEditingController();
  final _bizNumCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [_phoneCtrl, _passCtrl, _regNameCtrl, _regPhoneCtrl, _regPassCtrl, _bizNameCtrl, _bizNumCtrl, _addressCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.login(_phoneCtrl.text.trim(), _passCtrl.text);
      final me = await api.getMe();
      if (me['role'] != 'merchant') {
        _showError('매장 운영자 계정이 아닙니다. 손님 로그인을 이용하세요.');
        return;
      }
      final merchant = await api.getMyMerchant();
      await ref.read(authProvider.notifier).saveUserSession(
        userName: me['name'] as String,
        userRole: 'merchant',
        merchantId: merchant['id'] as String,
      );
      if (context.mounted) context.go('/merchant');
    } on DioException catch (e) {
      _showError(e.response?.data?['detail']?.toString() ?? '로그인에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAccount() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.signup(_regPhoneCtrl.text.trim(), _regNameCtrl.text.trim(), _regPassCtrl.text);
      if (mounted) setState(() => _signupStep = 2);
    } on DioException catch (e) {
      _showError(e.response?.data?['detail']?.toString() ?? '계정 생성에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerMerchant() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final merchant = await api.registerMerchant(
        businessName: _bizNameCtrl.text.trim(),
        businessNumber: _bizNumCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
      );
      final me = await api.getMe();
      await ref.read(authProvider.notifier).saveUserSession(
        userName: me['name'] as String,
        userRole: 'merchant',
        merchantId: merchant['id'] as String,
      );
      if (context.mounted) context.go('/merchant');
    } on DioException catch (e) {
      _showError(e.response?.data?['detail']?.toString() ?? '매장 등록에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[600]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF111827)),
          onPressed: () => _step == _Step.register
              ? setState(() { _step = _Step.login; _signupStep = 1; })
              : context.pop(),
        ),
        title: Text(_step == _Step.login ? '매장 로그인' : '매장 회원가입',
            style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _step == _Step.login ? _buildLogin() : _buildRegister(),
      ),
    );
  }

  Widget _buildLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Gap(4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8)),
          child: const Row(children: [
            Icon(Icons.storefront_outlined, size: 14, color: Color(0xFF059669)),
            Gap(6),
            Text('매장 운영자를 위한 전용 로그인', style: TextStyle(fontSize: 12, color: Color(0xFF059669))),
          ]),
        ),
        const Gap(28),
        _field('아이디 (전화번호)', _phoneCtrl, '전화번호를 입력하세요', type: TextInputType.phone,
            prefix: const Icon(Icons.person_outline, size: 18, color: Color(0xFF9CA3AF))),
        const Gap(14),
        _field('비밀번호', _passCtrl, '비밀번호를 입력하세요',
            obscure: _obscure,
            prefix: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF9CA3AF)),
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18, color: const Color(0xFF9CA3AF)),
              onPressed: () => setState(() => _obscure = !_obscure),
            )),
        const Gap(28),
        FilledButton(
          onPressed: _loading ? null : _login,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('로그인'),
        ),
        const Gap(32),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('아직 회원이 아닌가요?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
              const Gap(12),
              // 3단계 안내
              const Row(
                children: [
                  _SignupStep(num: '1', label: '계정 생성'),
                  Expanded(child: Divider(color: Color(0xFFE5E7EB), indent: 4, endIndent: 4)),
                  _SignupStep(num: '2', label: '매장 정보\n등록'),
                  Expanded(child: Divider(color: Color(0xFFE5E7EB), indent: 4, endIndent: 4)),
                  _SignupStep(num: '3', label: '가입 완료'),
                ],
              ),
              const Gap(16),
              OutlinedButton(
                onPressed: () => setState(() => _step = _Step.register),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(color: Color(0xFF059669)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('회원가입 시작하기', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                    Gap(4),
                    Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF059669)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegister() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _RegStep(num: 1, label: '매장 정보\n입력', active: _signupStep >= 1, done: _signupStep > 1),
          const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
          _RegStep(num: 2, label: '메뉴판 등록', active: _signupStep >= 2, done: _signupStep > 2),
          const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
          _RegStep(num: 3, label: '가입 완료', active: _signupStep >= 3, done: false),
        ]),
        const Gap(28),
        if (_signupStep == 1) ...[
          _field('이름', _regNameCtrl, '이름을 입력하세요'),
          const Gap(14),
          _field('전화번호 (아이디)', _regPhoneCtrl, '01012345678', type: TextInputType.phone),
          const Gap(14),
          _field('비밀번호', _regPassCtrl, '8자 이상 입력하세요', obscure: true),
          const Gap(28),
          FilledButton(
            onPressed: _loading ? null : _createAccount,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('다음'),
          ),
        ] else ...[
          _field('상호명', _bizNameCtrl, '매장 이름을 입력하세요'),
          const Gap(14),
          _field('사업자번호', _bizNumCtrl, '000-00-00000', type: TextInputType.number),
          const Gap(14),
          _field('주소', _addressCtrl, '매장 주소를 입력하세요'),
          const Gap(28),
          FilledButton(
            onPressed: _loading ? null : _registerMerchant,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('매장 등록 완료'),
          ),
        ],
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint,
      {bool obscure = false, TextInputType type = TextInputType.text, Widget? prefix, Widget? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
        const Gap(6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: type,
          style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
          decoration: InputDecoration(hintText: hint, prefixIcon: prefix, suffixIcon: suffix),
        ),
      ],
    );
  }
}

class _SignupStep extends StatelessWidget {
  final String num;
  final String label;
  const _SignupStep({required this.num, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 28, height: 28,
        decoration: const BoxDecoration(color: Color(0xFFF0FDF4), shape: BoxShape.circle),
        child: Center(child: Text(num, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF059669)))),
      ),
      const Gap(4),
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
    ]);
  }
}

class _RegStep extends StatelessWidget {
  final int num;
  final String label;
  final bool active;
  final bool done;
  const _RegStep({required this.num, required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final color = done ? const Color(0xFF059669) : (active ? const Color(0xFF059669) : const Color(0xFFE5E7EB));
    return Column(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color.withOpacity(done || active ? 1.0 : 0.3), shape: BoxShape.circle),
        child: Center(child: done
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : Text('$num', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : const Color(0xFF9CA3AF)))),
      ),
      const Gap(4),
      Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: active ? const Color(0xFF059669) : const Color(0xFF9CA3AF))),
    ]);
  }
}

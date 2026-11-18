import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../store/auth_store.dart';

class CustomerAuthScreen extends ConsumerStatefulWidget {
  const CustomerAuthScreen({super.key});

  @override
  ConsumerState<CustomerAuthScreen> createState() => _CustomerAuthScreenState();
}

class _CustomerAuthScreenState extends ConsumerState<CustomerAuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _signupPhoneCtrl = TextEditingController();
  final _signupPasswordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscureLogin = true;
  bool _obscureSignup = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final c in [_phoneCtrl, _passwordCtrl, _nameCtrl, _signupPhoneCtrl, _signupPasswordCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.login(_phoneCtrl.text.trim(), _passwordCtrl.text);
      final me = await api.getMe();
      await ref.read(authProvider.notifier).saveUserSession(
        userName: me['name'] as String,
        userRole: me['role'] as String,
      );
      if (context.mounted) {
        context.go('/id-scan');
      }
    } on DioException catch (e) {
      _showError(e.response?.data?['detail']?.toString() ?? '로그인에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signup() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.signup(_signupPhoneCtrl.text.trim(), _nameCtrl.text.trim(), _signupPasswordCtrl.text);
      final me = await api.getMe();
      await ref.read(authProvider.notifier).saveUserSession(
        userName: me['name'] as String,
        userRole: me['role'] as String,
      );
      if (context.mounted) {
        context.go('/id-scan');
      }
    } on DioException catch (e) {
      _showError(e.response?.data?['detail']?.toString() ?? '회원가입에 실패했습니다.');
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
          onPressed: () => context.pop(),
        ),
        title: const Text('손님 로그인 / 회원가입',
            style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 16),
            child: Text('본 서비스는 손님(고객) 전용입니다.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          ),
          TabBar(
            controller: _tab,
            labelColor: const Color(0xFF2563EB),
            unselectedLabelColor: const Color(0xFF9CA3AF),
            indicatorColor: const Color(0xFF2563EB),
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            tabs: const [Tab(text: '로그인'), Tab(text: '회원가입')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_buildLogin(), _buildSignup()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Gap(8),
          _inputField('전화번호', _phoneCtrl, '01012345678', type: TextInputType.phone),
          const Gap(14),
          _inputField('비밀번호', _passwordCtrl, '비밀번호를 입력하세요',
              obscure: _obscureLogin,
              suffix: IconButton(
                icon: Icon(_obscureLogin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20, color: const Color(0xFF9CA3AF)),
                onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
              )),
          const Gap(24),
          FilledButton(
            onPressed: _loading ? null : _login,
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('로그인'),
          ),
          const Gap(32),
          const Row(children: [
            Expanded(child: Divider(color: Color(0xFFE5E7EB))),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('또는', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13))),
            Expanded(child: Divider(color: Color(0xFFE5E7EB))),
          ]),
          const Gap(20),
          OutlinedButton(
            onPressed: () => _tab.animateTo(1),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('회원가입', style: TextStyle(color: Color(0xFF374151), fontWeight: FontWeight.w600)),
          ),
          const Gap(24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF2563EB)),
                Gap(8),
                Expanded(
                  child: Text(
                    '회원가입 시 성인 인증(신분증 + 생체 인증)이 진행됩니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(8),
          // 회원가입 단계 안내
          Row(
            children: [
              _StepBadge(step: 1, label: '성인 인증', active: true),
              const Expanded(child: Divider(color: Color(0xFFE5E7EB), indent: 4, endIndent: 4)),
              _StepBadge(step: 2, label: '정보 입력', active: false),
            ],
          ),
          const Gap(24),
          _inputField('이름', _nameCtrl, '홍길동'),
          const Gap(14),
          _inputField('전화번호', _signupPhoneCtrl, '01012345678', type: TextInputType.phone),
          const Gap(14),
          _inputField('비밀번호', _signupPasswordCtrl, '8자 이상 입력하세요',
              obscure: _obscureSignup,
              suffix: IconButton(
                icon: Icon(_obscureSignup ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20, color: const Color(0xFF9CA3AF)),
                onPressed: () => setState(() => _obscureSignup = !_obscureSignup),
              )),
          const Gap(24),
          FilledButton(
            onPressed: _loading ? null : _signup,
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('회원가입 시작하기'),
          ),
          const Gap(16),
          const Text(
            '가입 후 신분증 인증 및 생체 인증을 통해 성인 인증이 완료됩니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, String hint,
      {bool obscure = false, TextInputType type = TextInputType.text, Widget? suffix}) {
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
          decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  final int step;
  final String label;
  final bool active;
  const _StepBadge({required this.step, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2563EB) : const Color(0xFFF3F4F6),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('$step',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : const Color(0xFF9CA3AF))),
          ),
        ),
        const Gap(4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: active ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF),
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ],
    );
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../services/api_client.dart';
import '../store/auth_store.dart';

enum _SetupMode { login, signup }

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _SetupMode _mode = _SetupMode.login;
  bool _needsMerchantReg = false;
  bool _loading = false;

  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _bizNameCtrl = TextEditingController();
  final _bizNumCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [_phoneCtrl, _nameCtrl, _passwordCtrl, _bizNameCtrl, _bizNumCtrl, _addressCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleLoginOrSignup() async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    try {
      if (_mode == _SetupMode.signup) {
        await api.signup(_phoneCtrl.text.trim(), _nameCtrl.text.trim(), _passwordCtrl.text);
      } else {
        await api.login(_phoneCtrl.text.trim(), _passwordCtrl.text);
      }

      // 매장 정보 조회
      try {
        final merchant = await api.getMyMerchant();
        await ref.read(authProvider.notifier).saveMerchantId(merchant['id'] as String);
        // auth state 변경 → router redirect → HomeScreen 자동 이동
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // 매장 미등록 → 매장 등록 단계로
          if (mounted) setState(() { _needsMerchantReg = true; _loading = false; });
          return;
        }
        rethrow;
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? '로그인에 실패했습니다.';
      if (mounted) _showError(msg.toString());
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleMerchantRegister() async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    try {
      final merchant = await api.registerMerchant(
        businessName: _bizNameCtrl.text.trim(),
        businessNumber: _bizNumCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
      );
      await ref.read(authProvider.notifier).saveMerchantId(merchant['id'] as String);
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? '매장 등록에 실패했습니다.';
      if (mounted) _showError(msg.toString());
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(48),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(24),
          ),
          child: _needsMerchantReg ? _buildMerchantForm() : _buildAuthForm(),
        ),
      ),
    );
  }

  Widget _buildAuthForm() {
    final isSignup = _mode == _SetupMode.signup;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: const Color(0xFF1A73E8), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.verified_user, color: Colors.white, size: 22),
          ),
          const Gap(12),
          const Text('TrueID 매장 설정', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        ]),
        const Gap(8),
        const Text('매장 운영자 계정으로 로그인하세요', style: TextStyle(color: Colors.white38, fontSize: 13)),
        const Gap(32),
        if (isSignup) ...[
          _Field(label: '이름', controller: _nameCtrl, hint: '홍길동'),
          const Gap(16),
        ],
        _Field(label: '전화번호', controller: _phoneCtrl, hint: '01012345678', type: TextInputType.phone),
        const Gap(16),
        _Field(label: '비밀번호', controller: _passwordCtrl, hint: '••••••••', obscure: true),
        const Gap(28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _loading ? null : _handleLoginOrSignup,
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(isSignup ? '계정 만들기' : '로그인'),
          ),
        ),
        const Gap(16),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _mode = isSignup ? _SetupMode.login : _SetupMode.signup),
            child: Text(
              isSignup ? '이미 계정이 있으신가요? 로그인' : '계정이 없으신가요? 신규 등록',
              style: const TextStyle(color: Color(0xFF1A73E8), fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMerchantForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('매장 정보 등록', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const Gap(8),
        const Text('TrueID를 사용할 매장 정보를 입력해주세요', style: TextStyle(color: Colors.white38, fontSize: 13)),
        const Gap(28),
        _Field(label: '상호명', controller: _bizNameCtrl, hint: '홍길동 편의점'),
        const Gap(16),
        _Field(label: '사업자번호', controller: _bizNumCtrl, hint: '000-00-00000', type: TextInputType.number),
        const Gap(16),
        _Field(label: '주소', controller: _addressCtrl, hint: '서울시 강남구 ...'),
        const Gap(28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _loading ? null : _handleMerchantRegister,
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('매장 등록 완료'),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType type;

  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.type = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
        const Gap(6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: type,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF30363D)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF30363D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../store/session_store.dart';
import 'package:dio/dio.dart';

class OTPScreen extends ConsumerStatefulWidget {
  final String phone;
  const OTPScreen({super.key, required this.phone});

  @override
  ConsumerState<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends ConsumerState<OTPScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  int _resendCountdown = 180;
  Timer? _timer;
  bool _verifying = false;
  bool _otpSent = false;
  String? _devOtpHint;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  Future<void> _sendOtp() async {
    setState(() { _otpSent = false; _resendCountdown = 180; });
    await ref.read(sessionProvider.notifier).sendOtp(widget.phone);
    if (mounted) {
      setState(() => _otpSent = true);
      _startCountdown();
      // 개발 환경: 서버가 반환한 OTP를 자동으로 입력 후 검증
      final devOtp = ref.read(sessionProvider).devOtp;
      if (devOtp != null && devOtp.length == 6) {
        setState(() => _devOtpHint = devOtp);
        for (int i = 0; i < 6; i++) {
          _controllers[i].text = devOtp[i];
        }
        // onChanged가 프로그래밍 방식 입력에 호출 안 되므로 직접 verify 트리거
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _verify();
      }
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCountdown <= 0) { t.cancel(); return; }
      setState(() => _resendCountdown--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  String get _otpValue => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otpValue.length < 6 || _verifying) return;
    setState(() => _verifying = true);

    try {
      final sessionId = ref.read(sessionProvider).sessionId;
      if (sessionId == null) throw Exception('세션이 없습니다.');
      final api = ref.read(apiClientProvider);
      await api.verifyOtp(sessionId, _otpValue);
      if (context.mounted) context.push('/biometric');
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? 'OTP 인증에 실패했습니다.';
      if (mounted) _showError(msg.toString());
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  void _onDigitInput(int index, String value) {
    if (value.length == 1 && index < 5) _focusNodes[index + 1].requestFocus();
    else if (value.isEmpty && index > 0) _focusNodes[index - 1].requestFocus();
    if (_otpValue.length == 6) _verify();
  }

  String get _countdownText {
    final m = _resendCountdown ~/ 60;
    final s = _resendCountdown % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
        title: const Text('휴대폰 인증',
            style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Gap(8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.phone_android_rounded, color: Color(0xFF2563EB), size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    _otpSent
                        ? (widget.phone.isEmpty
                            ? '등록된 번호로 인증번호가 발송되었습니다'
                            : '${widget.phone}으로 인증번호가 발송되었습니다')
                        : 'OTP 발송 중...',
                    style: const TextStyle(color: Color(0xFF1D4ED8), fontSize: 14),
                  ),
                ),
              ]),
            ),
            // 개발 환경 OTP 힌트 배너
            if (_devOtpHint != null) ...[
              const Gap(12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF9C3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE047)),
                ),
                child: Row(children: [
                  const Icon(Icons.developer_mode_rounded, size: 16, color: Color(0xFFCA8A04)),
                  const Gap(8),
                  Text('개발모드 코드: $_devOtpHint',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF92400E), letterSpacing: 2)),
                ]),
              ),
            ],
            const Gap(32),
            const Text('인증번호 6자리 입력',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            const Gap(6),
            Text(_otpSent ? '문자로 받은 6자리 숫자를 입력하세요' : '잠시 기다려 주세요...',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            const Gap(24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) => _OTPBox(
                controller: _controllers[i],
                focusNode: _focusNodes[i],
                onChanged: (v) => _onDigitInput(i, v),
              )),
            ),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_countdownText,
                    style: const TextStyle(color: Color(0xFF2563EB), fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: _resendCountdown <= 0 ? _sendOtp : null,
                  child: const Text('재발송'),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _otpValue.length == 6 && !_verifying ? _verify : null,
                child: _verifying
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('확인'),
              ),
            ),
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: const Text('취소'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OTPBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  const _OTPBox({required this.controller, required this.focusNode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 58,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        maxLength: 1,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Color(0xFF111827), fontSize: 22, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          counterText: '',
          fillColor: const Color(0xFFF3F4F6),
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
          ),
        ),
      ),
    );
  }
}

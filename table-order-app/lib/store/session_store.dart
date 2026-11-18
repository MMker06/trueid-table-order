import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import 'auth_store.dart';

enum VerificationStep {
  idle,
  scanning,
  idChecking,
  idFailed,
  otpSending,
  otpWaiting,
  biometricCheck,
  completed,
  error,
}

class SessionState {
  final VerificationStep step;
  final String? sessionId;
  final IDCheckResult? idResult;
  final BiometricVerifyResult? biometricResult;
  final String? errorMessage;
  final String? devOtp; // 개발 환경에서 서버가 반환하는 OTP 코드

  const SessionState({
    this.step = VerificationStep.idle,
    this.sessionId,
    this.idResult,
    this.biometricResult,
    this.errorMessage,
    this.devOtp,
  });

  SessionState copyWith({
    VerificationStep? step,
    String? sessionId,
    IDCheckResult? idResult,
    BiometricVerifyResult? biometricResult,
    String? errorMessage,
    String? devOtp,
  }) =>
      SessionState(
        step: step ?? this.step,
        sessionId: sessionId ?? this.sessionId,
        idResult: idResult ?? this.idResult,
        biometricResult: biometricResult ?? this.biometricResult,
        errorMessage: errorMessage ?? this.errorMessage,
        devOtp: devOtp ?? this.devOtp,
      );

  bool get isLoading => step == VerificationStep.scanning ||
      step == VerificationStep.idChecking ||
      step == VerificationStep.otpSending ||
      step == VerificationStep.biometricCheck;
}

class SessionNotifier extends StateNotifier<SessionState> {
  final ApiClient _api;
  final String merchantId;

  SessionNotifier(this._api, this.merchantId) : super(const SessionState());

  Future<void> startSession() async {
    state = const SessionState(step: VerificationStep.scanning); // 이전 세션 완전 초기화
    try {
      final session = await _api.createSession(merchantId);
      state = state.copyWith(sessionId: session.id);
    } catch (e) {
      state = state.copyWith(step: VerificationStep.error, errorMessage: '세션 생성 실패: $e');
    }
  }

  Future<void> submitIdImage(List<int> imageBytes) async {
    if (state.sessionId == null) return;
    state = state.copyWith(step: VerificationStep.idChecking);
    try {
      final result = await _api.checkIdCard(state.sessionId!, imageBytes);
      state = state.copyWith(
        idResult: result,
        step: result.isGenuine ? VerificationStep.otpSending : VerificationStep.idFailed,
      );
    } catch (e) {
      state = state.copyWith(step: VerificationStep.error, errorMessage: '신분증 확인 중 오류: $e');
    }
  }

  Future<void> sendOtp(String phone) async {
    if (state.sessionId == null) return;
    state = state.copyWith(step: VerificationStep.otpSending);
    try {
      final res = await _api.sendOtp(state.sessionId!, phone);
      state = state.copyWith(
        step: VerificationStep.otpWaiting,
        devOtp: res['dev_otp'] as String?,
      );
    } catch (e) {
      state = state.copyWith(step: VerificationStep.error, errorMessage: 'OTP 발송 실패: $e');
    }
  }

  Future<void> verifyFace(List<int> imageBytes) async {
    if (state.sessionId == null) return;
    state = state.copyWith(step: VerificationStep.biometricCheck);
    try {
      final result = await _api.verifyFace(state.sessionId!, imageBytes);
      state = state.copyWith(
        biometricResult: result,
        step: result.matched ? VerificationStep.completed : VerificationStep.error,
        errorMessage: result.matched ? null : '얼굴 인증에 실패했습니다.',
      );
    } catch (e) {
      state = state.copyWith(step: VerificationStep.error, errorMessage: '얼굴 인증 오류: $e');
    }
  }

  Future<void> verifyFingerprint({int? sdkScore, List<int>? imageBytes}) async {
    if (state.sessionId == null) return;
    state = state.copyWith(step: VerificationStep.biometricCheck);
    try {
      final result = await _api.verifyFingerprint(state.sessionId!, sdkScore: sdkScore, imageBytes: imageBytes);
      state = state.copyWith(
        biometricResult: result,
        step: result.matched ? VerificationStep.completed : VerificationStep.error,
        errorMessage: result.matched ? null : '지문 인증에 실패했습니다.',
      );
    } catch (e) {
      state = state.copyWith(step: VerificationStep.error, errorMessage: '지문 인증 오류: $e');
    }
  }

  void reset() => state = const SessionState();
}

final merchantIdProvider = Provider<String>((ref) {
  // merchantId가 없으면 빈 문자열 (standalone 인증 - merchant 없이도 세션 생성 가능)
  return ref.watch(authProvider).merchantId ?? '';
});

// autoDispose 제거: 화면 전환 중 sessionId 소실 방지
final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  final api = ref.watch(apiClientProvider);
  final merchantId = ref.watch(merchantIdProvider);
  return SessionNotifier(api, merchantId);
});

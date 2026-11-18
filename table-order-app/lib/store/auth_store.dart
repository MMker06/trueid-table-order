import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_client.dart';

const _storage = FlutterSecureStorage();

class AuthState {
  final String? accessToken;
  final String? merchantId;
  final String? merchantName;
  final bool isInitializing;

  const AuthState({this.accessToken, this.merchantId, this.merchantName, this.isInitializing = true});
  bool get isAuthenticated => accessToken != null;

  AuthState copyWith({String? accessToken, String? merchantId, String? merchantName, bool? isInitializing}) =>
      AuthState(
        accessToken: accessToken ?? this.accessToken,
        merchantId: merchantId ?? this.merchantId,
        merchantName: merchantName ?? this.merchantName,
        isInitializing: isInitializing ?? this.isInitializing,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api = ApiClient();

  AuthNotifier() : super(const AuthState()) { _init(); }

  Future<void> login(String phone, String password) async {
    final r = await _api.login(phone, password);
    final token = r['access_token'] as String;
    final merchant = await _api.getMyMerchant();
    await saveSession(token: token, merchantId: merchant['id'] as String, merchantName: merchant['business_name'] as String);
  }

  // 세션 저장 없이 merchant 정보만 반환 (초기 설정용)
  Future<Map<String, String>> loginRaw(String phone, String password) async {
    final r = await _api.login(phone, password);  // 토큰은 api_client가 storage에 저장
    final merchant = await _api.getMyMerchant();
    // 상태 변경 없이 반환 — setup 완료 후 logout()이 토큰 정리
    return {
      'merchantId': merchant['id'] as String,
      'merchantName': merchant['business_name'] as String,
    };
  }

  Future<void> signup(String phone, String name, String password) async {
    await _api.signup(phone, name, password);
    // After signup, user registers merchant separately — just log in
    final r = await _api.login(phone, password);
    await _storage.write(key: 'access_token', value: r['access_token']);
    state = AuthState(accessToken: r['access_token'], isInitializing: false);
  }

  Future<void> _init() async {
    final token = await _storage.read(key: 'access_token');
    final merchantId = await _storage.read(key: 'merchant_id');
    final merchantName = await _storage.read(key: 'merchant_name');
    state = AuthState(accessToken: token, merchantId: merchantId, merchantName: merchantName, isInitializing: false);
  }

  Future<void> saveSession({required String token, required String merchantId, required String merchantName}) async {
    await _storage.write(key: 'access_token', value: token);
    await _storage.write(key: 'merchant_id', value: merchantId);
    await _storage.write(key: 'merchant_name', value: merchantName);
    state = AuthState(accessToken: token, merchantId: merchantId, merchantName: merchantName, isInitializing: false);
  }

  Future<void> logout() async {
    // 테이블 설정 키(tbl_*)는 유지하고 인증 키만 삭제
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'merchant_id');
    await _storage.delete(key: 'merchant_name');
    state = const AuthState(isInitializing: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());

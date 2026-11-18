import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';

const _storage = FlutterSecureStorage();
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;

  static const _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_AuthInterceptor(_dio));
  }

  // ── 인증 ──
  Future<Map<String, dynamic>> signup(String phone, String name, String password) async {
    final r = await _dio.post('/auth/signup', data: {'phone': phone, 'name': name, 'password': password});
    await _saveTokens(r.data);
    return r.data;
  }

  Future<Map<String, dynamic>> login(String phone, String password) async {
    final r = await _dio.post('/auth/login', data: {'phone': phone, 'password': password});
    await _saveTokens(r.data);
    return r.data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final r = await _dio.get('/auth/me');
    return r.data;
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.write(key: 'access_token', value: data['access_token']);
    await _storage.write(key: 'refresh_token', value: data['refresh_token']);
  }

  // ── 매장 ──
  Future<Map<String, dynamic>> registerMerchant(Map<String, dynamic> data) async {
    final r = await _dio.post('/merchant/register', data: data);
    return r.data;
  }

  Future<Map<String, dynamic>> getMyMerchant() async {
    final r = await _dio.get('/merchant/me');
    return r.data;
  }

  // ── 메뉴 ──
  Future<List<dynamic>> getPublicMenu(String merchantId) async {
    final r = await _dio.get('/menu/public/$merchantId');
    return r.data;
  }

  Future<List<dynamic>> getMenuItems() async {
    final r = await _dio.get('/menu/items');
    return r.data;
  }

  Future<Map<String, dynamic>> createMenuItem(Map<String, dynamic> data) async {
    final r = await _dio.post('/menu/items', data: data);
    return r.data;
  }

  Future<Map<String, dynamic>> updateMenuItem(String id, Map<String, dynamic> data) async {
    final r = await _dio.patch('/menu/items/$id', data: data);
    return r.data;
  }

  Future<void> deleteMenuItem(String id) async {
    await _dio.delete('/menu/items/$id');
  }

  Future<List<dynamic>> getCategories() async {
    final r = await _dio.get('/menu/categories');
    return r.data;
  }

  Future<Map<String, dynamic>> createCategory(String name) async {
    final r = await _dio.post('/menu/categories', data: {'name': name, 'sort_order': 0});
    return r.data;
  }

  // ── 주문 ──
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> data) async {
    final r = await _dio.post('/orders', data: data);
    return r.data;
  }

  Future<Map<String, dynamic>> verifyQR(String orderId, String qrData) async {
    final r = await _dio.post('/orders/$orderId/verify-qr', data: {'qr_data': qrData});
    return r.data;
  }

  Future<List<dynamic>> getKitchenOrders(String merchantId) async {
    final r = await _dio.get('/orders/kitchen/$merchantId');
    return r.data;
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    await _dio.patch('/orders/$orderId/status', queryParameters: {'status': status});
  }

  // ── 모바일 성인 인증 QR ──
  Future<Map<String, dynamic>> verifyIdOcr(String orderId, List<int> imageBytes) async {
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes, filename: 'id.jpg',
          contentType: MediaType('image', 'jpeg')),
    });
    final r = await _dio.post('/orders/$orderId/verify-id-ocr', data: formData,
        options: Options(contentType: 'multipart/form-data',
            receiveTimeout: const Duration(seconds: 30)));
    return r.data;
  }

  Future<Map<String, dynamic>> verifyIdCardForm(String orderId, {
    required String name,
    required String juminFront,
    required String juminBack,
    required String issueDate,
  }) async {
    final r = await _dio.post('/orders/$orderId/verify-id-card', data: {
      'name': name,
      'jumin_front': juminFront,
      'jumin_back': juminBack,
      'issue_date': issueDate,
    });
    return r.data;
  }

  Future<Map<String, dynamic>> requestMobileVerify(String orderId) async {
    final r = await _dio.post('/orders/$orderId/mobile-verify/request',
        data: {'base_url': _baseUrl});
    return r.data;
  }

  Future<Map<String, dynamic>> getMobileVerifyStatus(String orderId) async {
    final r = await _dio.get('/orders/$orderId/verify-status');
    return r.data;
  }

  Future<Map<String, dynamic>> generateCertQR(String birthDate) async {
    final r = await _dio.get('/ai/cert-qr/generate', queryParameters: {'birth_date': birthDate});
    return r.data;
  }

  // ── AI ──
  Future<Map<String, dynamic>> estimateAge(List<int> imageBytes) async {
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes, filename: 'face.jpg',
          contentType: MediaType('image', 'jpeg')),
    });
    final r = await _dio.post('/ai/estimate-age', data: formData,
        options: Options(contentType: 'multipart/form-data',
            receiveTimeout: const Duration(seconds: 30)));
    return r.data;
  }

  Future<Map<String, dynamic>> verifyIdCard(List<int> imageBytes) async {
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes, filename: 'id.jpg',
          contentType: MediaType('image', 'jpeg')),
    });
    final r = await _dio.post('/ai/verify-id', data: formData,
        options: Options(contentType: 'multipart/form-data'));
    return r.data;
  }

  Future<Map<String, dynamic>> detectPeople(List<int> imageBytes) async {
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes, filename: 'frame.jpg',
          contentType: MediaType('image', 'jpeg')),
    });
    final r = await _dio.post('/ai/detect-people', data: formData,
        options: Options(contentType: 'multipart/form-data'));
    return r.data;
  }
}

class _AuthInterceptor extends Interceptor {
  final Dio dio;
  _AuthInterceptor(this.dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh != null) {
        try {
          final r = await dio.post('/auth/refresh', data: {'refresh_token': refresh});
          final newToken = r.data['access_token'] as String;
          await _storage.write(key: 'access_token', value: newToken);
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          return handler.resolve(await dio.fetch(err.requestOptions));
        } catch (_) {}
      }
    }
    handler.next(err);
  }
}

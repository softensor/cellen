import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_exception.dart';

// ---------------------------------------------------------------------------
// IMPORTANT: Change kBaseUrl to your host machine IP when running from a VM.
// Example: 'http://192.168.1.100:8000/api/v1'
// ---------------------------------------------------------------------------
const String kBaseUrl = 'https://167.235.158.77.nip.io/api/v1';

// The media root (for photo URLs) — derived from kBaseUrl so it uses the same host
final String kMediaBase = Uri.parse(kBaseUrl).origin;

// Storage keys shared with AuthService
const String kAccessTokenKey = 'access_token';
const String kRefreshTokenKey = 'refresh_token';

// ---------------------------------------------------------------------------
// AuthInterceptor
// ---------------------------------------------------------------------------
class AuthInterceptor extends Interceptor {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  // Prevent recursive refresh loops
  bool _isRefreshing = false;

  AuthInterceptor(this._dio, this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: kAccessTokenKey);
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await _storage.read(key: kRefreshTokenKey);
        if (refreshToken == null || refreshToken.isEmpty) {
          await _clearTokens();
          _isRefreshing = false;
          handler.next(err);
          return;
        }

        // Attempt to refresh
        final refreshDio = Dio(BaseOptions(baseUrl: kBaseUrl));
        final refreshResponse = await refreshDio.post(
          '/auth/refresh',
          data: {'refresh_token': refreshToken},
        );

        final newAccess = refreshResponse.data['access_token'] as String?;
        if (newAccess == null || newAccess.isEmpty) {
          await _clearTokens();
          _isRefreshing = false;
          handler.next(err);
          return;
        }

        await _storage.write(key: kAccessTokenKey, value: newAccess);

        // Check if a new refresh token is also returned
        final newRefresh = refreshResponse.data['refresh_token'] as String?;
        if (newRefresh != null && newRefresh.isNotEmpty) {
          await _storage.write(key: kRefreshTokenKey, value: newRefresh);
        }

        _isRefreshing = false;

        // Retry original request with new token
        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retryResponse = await _dio.fetch(retryOptions);
        handler.resolve(retryResponse);
      } catch (_) {
        await _clearTokens();
        _isRefreshing = false;
        handler.next(err);
      }
    } else {
      handler.next(err);
    }
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: kAccessTokenKey);
    await _storage.delete(key: kRefreshTokenKey);
  }
}

// ---------------------------------------------------------------------------
// ApiClient
// ---------------------------------------------------------------------------
class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage;

  ApiClient(this._storage) {
    _dio = Dio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    _dio.interceptors.add(AuthInterceptor(_dio, _storage));
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
      );
      return response.data;
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data;
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  Future<dynamic> put(String path, {dynamic data}) async {
    try {
      final response = await _dio.put(path, data: data);
      return response.data;
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  Future<dynamic> patch(String path, {dynamic data}) async {
    try {
      final response = await _dio.patch(path, data: data);
      return response.data;
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final response = await _dio.delete(path);
      return response.data;
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  ApiException _mapException(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final data = e.response!.data;
      String message;
      if (data is Map) {
        message =
            data['detail']?.toString() ??
            data['message']?.toString() ??
            e.message ??
            'Unknown error';
      } else if (data is String && data.isNotEmpty) {
        message = data;
      } else {
        message = e.message ?? 'Unknown error';
      }
      return ApiException(statusCode: statusCode, message: message);
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const ApiException(message: 'Tempo de ligação esgotado. Verifique a sua conexão.');
    } else if (e.type == DioExceptionType.connectionError) {
      return const ApiException(message: 'Sem ligação ao servidor. Verifique o endereço e a rede.');
    } else {
      return ApiException(message: e.message ?? 'Erro desconhecido');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(const FlutterSecureStorage());
});

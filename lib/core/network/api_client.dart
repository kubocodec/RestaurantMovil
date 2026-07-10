import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../storage/auth_storage.dart';

class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;

  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  static ApiClient get instance => _instance ??= ApiClient._();

  Dio get dio => _dio;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await AuthStorage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      try {
        final refreshToken = await AuthStorage.getRefreshToken();
        if (refreshToken != null) {
          // Dio limpio: sin interceptores, para no inyectar el token vencido
          // ni re-entrar en este handler si el refresh también falla.
          final refreshDio = Dio(BaseOptions(
            baseUrl: ApiConstants.baseUrl,
            connectTimeout: ApiConstants.connectTimeout,
            receiveTimeout: ApiConstants.receiveTimeout,
            headers: {'Content-Type': 'application/json'},
          ));
          final response = await refreshDio.post(
            ApiConstants.refresh,
            data: {'refreshToken': refreshToken},
          );
          final data = response.data['data'];
          final newToken = data['accessToken'];
          await AuthStorage.updateAccessToken(newToken);
          if (data['refreshToken'] != null) {
            await AuthStorage.updateRefreshToken(data['refreshToken']);
          }
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          final retryResponse = await _dio.fetch(err.requestOptions);
          return handler.resolve(retryResponse);
        }
      } catch (_) {
        await AuthStorage.clear();
      }
    }
    handler.next(err);
  }

  static String parseError(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        return data['message'] ?? data['error'] ?? 'Error del servidor';
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Sin conexión con el servidor';
      }
      if (error.type == DioExceptionType.connectionError) {
        return 'No se puede conectar al servidor';
      }
      return 'Error del servidor';
    }
    // Show the actual exception message so errors are diagnosable in the UI
    final msg = error?.toString() ?? 'Error inesperado';
    return msg.startsWith('Exception: ') ? msg.substring(11) : msg;
  }
}

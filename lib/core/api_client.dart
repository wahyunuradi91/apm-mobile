import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

const _tokenKey = 'apm_token';

final secureStorageProvider = Provider((_) => const FlutterSecureStorage());

class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;
  String? _cached;

  Future<String?> read() async => _cached ??= await _storage.read(key: _tokenKey);

  Future<void> write(String token) async {
    _cached = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _tokenKey);
  }
}

final tokenStoreProvider = Provider((ref) => TokenStore(ref.watch(secureStorageProvider)));

/// Dipanggil saat server membalas 401 (token kadaluarsa/dicabut).
/// Di-set oleh AuthController supaya tidak ada import melingkar.
typedef UnauthorizedHandler = void Function();
UnauthorizedHandler? onUnauthorized;

final dioProvider = Provider<Dio>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await tokens.read();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
    onError: (error, handler) {
      final isLogin = error.requestOptions.path.endsWith('/auth/exchange');
      if (error.response?.statusCode == 401 && !isLogin) {
        onUnauthorized?.call();
      }
      handler.next(error);
    },
  ));

  return dio;
});

/// Ambil pesan error yang ramah dari response APM (`{message, data}`).
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map && body['message'] is String) return body['message'] as String;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Koneksi ke server timeout.';
      case DioExceptionType.connectionError:
        return 'Tidak bisa terhubung ke server APM.';
      default:
        return 'Terjadi kesalahan (${error.response?.statusCode ?? '-'}).';
    }
  }
  return error.toString().replaceFirst('Exception: ', '');
}

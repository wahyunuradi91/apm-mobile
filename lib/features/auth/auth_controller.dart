import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';

const _userKey = 'apm_user';

/// Bentuk mengikuti `App\Http\Resources\Mobile\MobileUserResource` di backend.
class AuthUser {
  AuthUser(this.raw);

  final Map<String, dynamic> raw;

  int get id => raw['id'] as int;
  String get name => raw['name']?.toString() ?? '-';
  String get nik => raw['nik']?.toString() ?? '-';
  String? get email => raw['email']?.toString();
  List<String> get roles => _strings(raw['roles']);
  List<String> get permissions => _strings(raw['permissions']);

  Map<String, dynamic> get employee =>
      raw['employee'] is Map ? Map<String, dynamic>.from(raw['employee'] as Map) : {};

  String? get factoryName => (employee['factory'] as Map?)?['name']?.toString();

  /// Deskripsi PIC user — web membandingkannya dgn kolom `pic` operation WO.
  String? get picDescription => (employee['pic'] as Map?)?['description']?.toString();

  bool can(String permission) => permissions.contains(permission);

  static List<String> _strings(Object? v) =>
      (v as List? ?? const []).map((e) => e.toString()).toList();
}

class LoginCancelled implements Exception {}

class AuthController extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async {
    onUnauthorized = () => _clearLocal();

    final token = await ref.read(tokenStoreProvider).read();
    final userJson = await ref.read(secureStorageProvider).read(key: _userKey);
    if (token == null || userJson == null) return null;

    final cached = AuthUser(Map<String, dynamic>.from(jsonDecode(userJson) as Map));
    // Segarkan profil/role di background; kalau sesi OneKey sudah berakhir → 401 → logout.
    Future.microtask(_refreshProfile);
    return cached;
  }

  /// Login OneKey — alur sama dengan web (halaman login Keycloak, client dari .env server):
  ///  1. buka {APM}/mobile/auth/keycloak/redirect?challenge=… di Custom Tab
  ///  2. server redirect balik ke apmmobile://auth?code=…
  ///  3. tukar code + verifier di POST /auth/exchange → token apm-mobile
  Future<void> login() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final verifier = _randomVerifier();
      final challenge = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');

      final String result;
      try {
        result = await FlutterWebAuth2.authenticate(
          url: '${AppConfig.loginUrl}?challenge=$challenge',
          callbackUrlScheme: AppConfig.callbackScheme,
        );
      } on PlatformException catch (e) {
        if (e.code == 'CANCELED') throw LoginCancelled();
        rethrow;
      }

      final params = Uri.parse(result).queryParameters;
      if (params['error'] != null) throw Exception(params['error']);
      final code = params['code'];
      if (code == null) throw Exception('Login OneKey tidak mengembalikan kode.');

      final res = await ref.read(dioProvider).post(
        '/auth/exchange',
        data: {'code': code, 'verifier': verifier},
      );
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      await ref.read(tokenStoreProvider).write(data['token'] as String);
      return _saveUser(Map<String, dynamic>.from(data['user'] as Map));
    });

    // Batal login bukan error yang perlu ditampilkan.
    if (state.error is LoginCancelled) state = const AsyncData(null);
  }

  /// Logout = akhiri sesi OneKey juga (server memanggil end-session Keycloak).
  Future<void> logout() async {
    try {
      await ref.read(dioProvider).post('/auth/logout');
    } catch (_) {
      // Token mungkin sudah tidak valid; tetap bersihkan lokal.
    }
    await _clearLocal();
  }

  Future<void> _refreshProfile() async {
    try {
      final res = await ref.read(dioProvider).get('/auth/me');
      final user = await _saveUser(Map<String, dynamic>.from(res.data['data'] as Map));
      if (state.value != null) state = AsyncData(user);
    } catch (_) {
      // Offline / server error: tetap pakai profil cache.
    }
  }

  Future<AuthUser> _saveUser(Map<String, dynamic> json) async {
    await ref.read(secureStorageProvider).write(key: _userKey, value: jsonEncode(json));
    return AuthUser(json);
  }

  Future<void> _clearLocal() async {
    await ref.read(tokenStoreProvider).clear();
    await ref.read(secureStorageProvider).delete(key: _userKey);
    state = const AsyncData(null);
  }

  static String _randomVerifier() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(64, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthUser?>(AuthController.new);

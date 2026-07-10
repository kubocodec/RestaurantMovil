import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';

class AuthStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyUser = 'current_user';
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';

  static Future<void> saveUser(UserModel user) async {
    await Future.wait([
      _storage.write(key: _keyUser, value: jsonEncode(user.toJson())),
      _storage.write(key: _keyAccessToken, value: user.accessToken),
      _storage.write(key: _keyRefreshToken, value: user.refreshToken),
    ]);
  }

  static Future<UserModel?> getUser() async {
    try {
      final raw = await _storage.read(key: _keyUser);
      if (raw == null) return null;
      return UserModel.fromJson(jsonDecode(raw));
    } catch (_) {
      // Storage corrupted or unavailable — clear and force re-login
      try { await clear(); } catch (_) {}
      return null;
    }
  }

  static Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);
  static Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);

  static Future<void> updateAccessToken(String token) =>
      _storage.write(key: _keyAccessToken, value: token);

  static Future<void> updateRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyUser),
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
    ]);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

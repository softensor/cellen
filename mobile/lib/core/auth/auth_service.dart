import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'auth_state.dart';

class AuthService {
  final ApiClient _api;
  final FlutterSecureStorage _storage;

  static const String _accessTokenKey = kAccessTokenKey;
  static const String _refreshTokenKey = kRefreshTokenKey;
  static const String _roleKey = 'user_role';
  static const String _userIdKey = 'user_id';
  static const String _schoolIdKey = 'school_id';
  static const String _usernameKey = 'username';
  static const String _employeeIdKey = 'employee_id';
  static const String _guardianIdKey = 'guardian_id';

  AuthService(this._api, this._storage);

  /// Login: POST /auth/login with {username, password, school_slug?}
  /// Stores tokens in FlutterSecureStorage.
  /// Decodes JWT to extract role, user_id, school_id, employee_id, guardian_id.
  Future<AuthState> login({
    required String username,
    required String password,
    String? schoolSlug,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'password': password,
    };
    if (schoolSlug != null && schoolSlug.isNotEmpty) {
      body['school_slug'] = schoolSlug;
    }

    final data = await _api.post('/auth/login', data: body);

    if (data == null || data is! Map) {
      throw const ApiException(message: 'Resposta inválida do servidor');
    }

    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;

    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(message: 'Token de acesso não recebido');
    }

    // Decode JWT payload to extract claims
    final payload = _decodeJwtPayload(accessToken);

    final role = AuthState.roleFromString(
      payload['role'] as String? ?? payload['user_role'] as String?,
    );
    final userId =
        payload['user_id']?.toString() ?? payload['sub']?.toString() ?? '';
    final schoolId = payload['school_id']?.toString() ?? '';
    final storedUsername = payload['username']?.toString() ?? username;
    final employeeId = payload['employee_id'] as String?;
    final guardianId = payload['guardian_id'] as String?;

    // Persist everything to secure storage
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await _storage.write(
        key: _roleKey, value: AuthState.roleToStorageString(role));
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _schoolIdKey, value: schoolId);
    await _storage.write(key: _usernameKey, value: storedUsername);
    if (employeeId != null && employeeId.isNotEmpty) {
      await _storage.write(key: _employeeIdKey, value: employeeId);
    } else {
      await _storage.delete(key: _employeeIdKey);
    }
    if (guardianId != null && guardianId.isNotEmpty) {
      await _storage.write(key: _guardianIdKey, value: guardianId);
    } else {
      await _storage.delete(key: _guardianIdKey);
    }

    return AuthState(
      isAuthenticated: true,
      isLoading: false,
      accessToken: accessToken,
      refreshToken: refreshToken,
      role: role,
      userId: userId,
      schoolId: schoolId.isNotEmpty ? schoolId : null,
      username: storedUsername,
      employeeId: employeeId?.isNotEmpty == true ? employeeId : null,
      guardianId: guardianId?.isNotEmpty == true ? guardianId : null,
    );
  }

  /// Logout: POST /auth/logout then clears all stored tokens.
  Future<void> logout() async {
    try {
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken != null) {
        await _api.post('/auth/logout', data: {'refresh': refreshToken});
      }
    } catch (_) {
      // Ignore logout API errors — always clear local tokens
    } finally {
      await _clearAll();
    }
  }

  /// Restore session from secure storage on app start.
  Future<AuthState> restoreSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) {
      return const AuthState.initial();
    }

    // Verify the token hasn't expired by decoding it
    try {
      final payload = _decodeJwtPayload(accessToken);
      final exp = payload['exp'] as int?;
      if (exp != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        if (DateTime.now().isAfter(expiry)) {
          // Access token expired — try to refresh
          return await _tryRefreshOnRestore();
        }
      }
    } catch (_) {
      return const AuthState.initial();
    }

    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final roleStr = await _storage.read(key: _roleKey);
    final userId = await _storage.read(key: _userIdKey);
    final schoolId = await _storage.read(key: _schoolIdKey);
    final username = await _storage.read(key: _usernameKey);
    final employeeId = await _storage.read(key: _employeeIdKey);
    final guardianId = await _storage.read(key: _guardianIdKey);

    return AuthState(
      isAuthenticated: true,
      isLoading: false,
      accessToken: accessToken,
      refreshToken: refreshToken,
      role: AuthState.roleFromString(roleStr),
      userId: userId,
      schoolId: schoolId?.isNotEmpty == true ? schoolId : null,
      username: username,
      employeeId: employeeId?.isNotEmpty == true ? employeeId : null,
      guardianId: guardianId?.isNotEmpty == true ? guardianId : null,
    );
  }

  Future<AuthState> _tryRefreshOnRestore() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearAll();
      return const AuthState.initial();
    }

    try {
      final data = await _api.post('/auth/refresh', data: {'refresh': refreshToken});
      final newAccess = data['access_token'] as String?;
      if (newAccess == null || newAccess.isEmpty) {
        await _clearAll();
        return const AuthState.initial();
      }

      final newRefresh = data['refresh_token'] as String? ?? refreshToken;
      await _storage.write(key: _accessTokenKey, value: newAccess);
      await _storage.write(key: _refreshTokenKey, value: newRefresh);

      final payload = _decodeJwtPayload(newAccess);
      final role = AuthState.roleFromString(
        payload['role'] as String? ?? payload['user_role'] as String?,
      );
      final userId = payload['user_id']?.toString() ?? '';
      final schoolId = payload['school_id']?.toString() ?? '';
      final username = payload['username']?.toString() ?? '';
      final employeeId = payload['employee_id'] as String?;
      final guardianId = payload['guardian_id'] as String?;

      await _storage.write(
          key: _roleKey, value: AuthState.roleToStorageString(role));
      await _storage.write(key: _userIdKey, value: userId);
      await _storage.write(key: _schoolIdKey, value: schoolId);
      await _storage.write(key: _usernameKey, value: username);
      if (employeeId != null && employeeId.isNotEmpty) {
        await _storage.write(key: _employeeIdKey, value: employeeId);
      } else {
        await _storage.delete(key: _employeeIdKey);
      }
      if (guardianId != null && guardianId.isNotEmpty) {
        await _storage.write(key: _guardianIdKey, value: guardianId);
      } else {
        await _storage.delete(key: _guardianIdKey);
      }

      return AuthState(
        isAuthenticated: true,
        isLoading: false,
        accessToken: newAccess,
        refreshToken: newRefresh,
        role: role,
        userId: userId.isNotEmpty ? userId : null,
        schoolId: schoolId.isNotEmpty ? schoolId : null,
        username: username.isNotEmpty ? username : null,
        employeeId: employeeId?.isNotEmpty == true ? employeeId : null,
        guardianId: guardianId?.isNotEmpty == true ? guardianId : null,
      );
    } catch (_) {
      await _clearAll();
      return const AuthState.initial();
    }
  }

  Future<void> _clearAll() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _schoolIdKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _employeeIdKey);
    await _storage.delete(key: _guardianIdKey);
  }

  /// Decodes the JWT payload without verifying the signature.
  Map<String, dynamic> _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('Invalid JWT');
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }
}

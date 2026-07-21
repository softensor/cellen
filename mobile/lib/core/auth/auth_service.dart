import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'auth_state.dart';

class AuthService {
  final ApiClient _api;
  final FlutterSecureStorage _storage;

  static const String _accessTokenKey  = kAccessTokenKey;
  static const String _refreshTokenKey = kRefreshTokenKey;
  static const String _rolesKey        = 'user_roles';   // JSON array of strings
  static const String _userIdKey       = 'user_id';
  static const String _schoolIdKey     = 'school_id';
  static const String _usernameKey     = 'username';
  static const String _employeeIdKey   = 'employee_id';
  static const String _guardianIdKey   = 'guardian_id';

  AuthService(this._api, this._storage);

  // ── Login ────────────────────────────────────────────────────────────────

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

    final accessToken  = data['access_token']  as String?;
    final refreshToken = data['refresh_token'] as String?;

    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(message: 'Token de acesso não recebido');
    }

    // Decode JWT payload
    final payload = _decodeJwtPayload(accessToken);

    final roles = _parseRoles(payload);
    final userId        = payload['user_id']?.toString() ?? payload['sub']?.toString() ?? '';
    final schoolId      = payload['school_id']?.toString() ?? '';
    final storedUsername = payload['username']?.toString() ?? username;
    final employeeId    = payload['employee_id'] as String?;
    final guardianId    = payload['guardian_id'] as String?;

    // Persist
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await _storage.write(
      key: _rolesKey,
      value: jsonEncode(roles.map(AuthState.roleToString).whereType<String>().toList()),
    );
    await _storage.write(key: _userIdKey,  value: userId);
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
      roles: roles,
      userId: userId,
      schoolId: schoolId.isNotEmpty ? schoolId : null,
      username: storedUsername,
      employeeId: employeeId?.isNotEmpty == true ? employeeId : null,
      guardianId: guardianId?.isNotEmpty == true ? guardianId : null,
    );
  }

  // ── Logout ───────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken != null) {
        await _api.post('/auth/logout', data: {'refresh_token': refreshToken});
      }
    } catch (_) {
      // Always clear local tokens regardless of API response
    } finally {
      await _clearAll();
    }
  }

  // ── Restore session ──────────────────────────────────────────────────────

  Future<AuthState> restoreSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) {
      return const AuthState.initial();
    }

    try {
      final payload = _decodeJwtPayload(accessToken);
      final exp = payload['exp'] as int?;
      if (exp != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        if (DateTime.now().isAfter(expiry)) {
          return await _tryRefreshOnRestore();
        }
      }
    } catch (_) {
      return const AuthState.initial();
    }

    final refreshToken  = await _storage.read(key: _refreshTokenKey);
    final rolesJson     = await _storage.read(key: _rolesKey);
    final userId        = await _storage.read(key: _userIdKey);
    final schoolId      = await _storage.read(key: _schoolIdKey);
    final username      = await _storage.read(key: _usernameKey);
    final employeeId    = await _storage.read(key: _employeeIdKey);
    final guardianId    = await _storage.read(key: _guardianIdKey);

    final roles = _rolesFromStorage(rolesJson);

    return AuthState(
      isAuthenticated: true,
      isLoading: false,
      accessToken: accessToken,
      refreshToken: refreshToken,
      roles: roles,
      userId: userId,
      schoolId: schoolId?.isNotEmpty == true ? schoolId : null,
      username: username,
      employeeId: employeeId?.isNotEmpty == true ? employeeId : null,
      guardianId: guardianId?.isNotEmpty == true ? guardianId : null,
    );
  }

  // ── Refresh ──────────────────────────────────────────────────────────────

  Future<AuthState> _tryRefreshOnRestore() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearAll();
      return const AuthState.initial();
    }

    try {
      final data = await _api.post('/auth/refresh', data: {'refresh_token': refreshToken});
      final newAccess   = data['access_token'] as String?;
      if (newAccess == null || newAccess.isEmpty) {
        await _clearAll();
        return const AuthState.initial();
      }

      final newRefresh   = data['refresh_token'] as String? ?? refreshToken;
      await _storage.write(key: _accessTokenKey,  value: newAccess);
      await _storage.write(key: _refreshTokenKey, value: newRefresh);

      final payload    = _decodeJwtPayload(newAccess);
      final roles      = _parseRoles(payload);
      final userId     = payload['user_id']?.toString() ?? '';
      final schoolId   = payload['school_id']?.toString() ?? '';
      final username   = payload['username']?.toString() ?? '';
      final employeeId = payload['employee_id'] as String?;
      final guardianId = payload['guardian_id'] as String?;

      await _storage.write(
        key: _rolesKey,
        value: jsonEncode(roles.map(AuthState.roleToString).whereType<String>().toList()),
      );
      await _storage.write(key: _userIdKey,   value: userId);
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
        roles: roles,
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Parse roles from JWT payload. Supports both new `roles: [...]` and old `role: str`.
  Set<UserRole> _parseRoles(Map<String, dynamic> payload) {
    final rolesRaw = payload['roles'];
    if (rolesRaw is List && rolesRaw.isNotEmpty) {
      return rolesRaw
          .map((r) => AuthState.roleFromString(r as String?))
          .whereType<UserRole>()
          .toSet();
    }
    // Fallback: old single-role token
    final single = AuthState.roleFromString(payload['role'] as String?);
    return {if (single != null) single};
  }

  /// Parse roles from secure storage JSON string.
  Set<UserRole> _rolesFromStorage(String? json) {
    if (json == null || json.isEmpty) return const {};
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((r) => AuthState.roleFromString(r as String?))
          .whereType<UserRole>()
          .toSet();
    } catch (_) {
      // Fallback: treat as single role string (old storage format)
      final single = AuthState.roleFromString(json);
      return {if (single != null) single};
    }
  }

  Future<void> _clearAll() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _rolesKey);
    await _storage.delete(key: 'user_role');   // cleanup old key if present
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _schoolIdKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _employeeIdKey);
    await _storage.delete(key: _guardianIdKey);
  }

  Map<String, dynamic> _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('Invalid JWT');
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }
}

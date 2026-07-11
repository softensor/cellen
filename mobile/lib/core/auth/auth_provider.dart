import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import 'auth_service.dart';
import 'auth_state.dart';

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _service;

  AuthNotifier(this._service) : super(const AuthState.initial()) {
    _init();
  }

  Future<void> _init() async {
    state = const AuthState.loading();
    try {
      state = await _service.restoreSession();
    } catch (_) {
      state = const AuthState.initial();
    }
  }

  Future<void> login({
    required String username,
    required String password,
    String? schoolSlug,
  }) async {
    state = const AuthState.loading();
    try {
      state = await _service.login(
        username: username,
        password: password,
        schoolSlug: schoolSlug,
      );
    } catch (e) {
      state = AuthState.error(e.toString());
    }
  }

  Future<void> logout() async {
    await _service.logout();
    state = const AuthState.initial();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    AuthService(
      ref.read(apiClientProvider),
      const FlutterSecureStorage(),
    ),
  );
});

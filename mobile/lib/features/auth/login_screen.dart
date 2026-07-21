import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _schoolSlugController = TextEditingController();
  bool _obscurePassword = true;
  bool _isPlatformLogin = false;

  // Biometric state
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage();
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return;

      final savedEmail = await _secureStorage.read(key: 'saved_email');
      final savedPassword = await _secureStorage.read(key: 'saved_password');

      if (savedEmail != null && savedPassword != null && mounted) {
        setState(() => _biometricAvailable = true);
      }
    } catch (_) {
      // Biometric check failed silently — button stays hidden
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _schoolSlugController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      ref.read(authProvider.notifier).login(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            schoolSlug:
                _isPlatformLogin ? null : _schoolSlugController.text.trim(),
          );
    }
  }

  Future<void> _saveCredentials(String email, String password) async {
    await _secureStorage.write(key: 'saved_email', value: email);
    await _secureStorage.write(key: 'saved_password', value: password);
  }

  Future<void> _loginWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Autentique-se para entrar no Cellen',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!authenticated) return;

      final savedEmail = await _secureStorage.read(key: 'saved_email');
      final savedPassword = await _secureStorage.read(key: 'saved_password');
      if (savedEmail == null || savedPassword == null) return;

      // Populate the form fields so the standard submit path is used
      _usernameController.text = savedEmail;
      _passwordController.text = savedPassword;

      ref.read(authProvider.notifier).login(
            username: savedEmail,
            password: savedPassword,
            schoolSlug: _isPlatformLogin
                ? null
                : _schoolSlugController.text.trim().isNotEmpty
                    ? _schoolSlugController.text.trim()
                    : null,
          );
    } catch (_) {
      // Biometric failed — fall back gracefully (user can type credentials)
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (prev, next) async {
      if (next.isAuthenticated) {
        // Persist credentials for future biometric logins
        final email = _usernameController.text.trim();
        final password = _passwordController.text;
        if (email.isNotEmpty && password.isNotEmpty) {
          await _saveCredentials(email, password);
        }

        if (!mounted) return;
        context.go(next.homeRoute);
      }
    });

    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Gradient hero ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.school_rounded,
                          color: Colors.white, size: 44),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Cellen',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestão de Creche',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Form panel ─────────────────────────────────────────
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 48),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Mode toggle
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            _ModeTab(
                              label: 'Escola',
                              selected: !_isPlatformLogin,
                              onTap: () =>
                                  setState(() => _isPlatformLogin = false),
                            ),
                            _ModeTab(
                              label: 'Plataforma',
                              selected: _isPlatformLogin,
                              onTap: () =>
                                  setState(() => _isPlatformLogin = true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // School slug
                      if (!_isPlatformLogin) ...[
                        TextFormField(
                          controller: _schoolSlugController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Código da Escola',
                            hintText: 'ex: jardim-infancia',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          validator: (v) =>
                              !_isPlatformLogin && (v == null || v.trim().isEmpty)
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Username
                      TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Utilizador',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Campo obrigatório'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Palavra-passe',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Campo obrigatório' : null,
                      ),

                      // Error banner
                      if (authState.error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: AppTheme.danger.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: AppTheme.danger, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(authState.error!,
                                    style: TextStyle(
                                        color: AppTheme.danger, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: authState.isLoading ? null : _submit,
                          child: authState.isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Text('Entrar',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),

                      // Biometric login button — only shown when available
                      if (_biometricAvailable) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: authState.isLoading
                              ? null
                              : _loginWithBiometric,
                          icon: const Icon(Icons.fingerprint, size: 22),
                          label: const Text(
                            'Entrar com biometria',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            side: BorderSide(
                              color: AppTheme.primary.withOpacity(0.5),
                            ),
                            foregroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

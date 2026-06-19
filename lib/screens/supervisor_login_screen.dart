import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/lot_cache.dart';

/// Supervisor login screen — email + password path alongside the existing PIN flow.
/// On success, writes:
///   - flutter_secure_storage  key='workerSurveyToken'  value=surveyToken
///   - SharedPreferences       sessionKind='supervisor'
///                             sessionRole=user.role
///                             fieldworkerId=worker.id
///                             tokenIssuedAt=epoch ms
///                             assignedLots=JSON-encoded array
/// Then routes to /home; the home screen reads sessionKind to gate supervisor UI.
class SupervisorLoginScreen extends StatefulWidget {
  const SupervisorLoginScreen({super.key});

  @override
  State<SupervisorLoginScreen> createState() => _SupervisorLoginScreenState();
}

class _SupervisorLoginScreenState extends State<SupervisorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  static const _secureStorage = FlutterSecureStorage();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // base64-encode the password as the Survey App expects
      final encodedPassword = base64Encode(utf8.encode(_passwordController.text.trim()));

      final result = await ApiService.supervisorLogin(
        email: _emailController.text.trim().toLowerCase(),
        password: encodedPassword,
      );

      final surveyToken = result['surveyToken'] as String;
      final worker = result['worker'] as Map<String, dynamic>;
      final assignedLots = result['assignedLots'] as List<dynamic>? ?? [];

      // ── Write token to flutter_secure_storage (same key as web app) ──────────
      await _secureStorage.write(key: 'workerSurveyToken', value: surveyToken);

      // ── Write session metadata to SharedPreferences ───────────────────────────
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sessionKind', 'supervisor');
      await prefs.setString('sessionRole', (worker['surveyAppRole'] ?? worker['role'] ?? 'supervisor') as String);
      await prefs.setInt('fieldworkerId', (worker['id'] as num).toInt());
      await prefs.setInt('tokenIssuedAt', DateTime.now().millisecondsSinceEpoch);
      await prefs.setString('assignedLots', jsonEncode(assignedLots));
      // D3/Fix2: Persist the Survey App userId so pickup_submission_screen can
      // use it as the payload's userId (not the worker email).
      final surveyAppUserId = (worker['userId'] ?? worker['_id'] ?? worker['id']?.toString() ?? '').toString();
      if (surveyAppUserId.isNotEmpty) {
        await prefs.setString('surveyAppUserId', surveyAppUserId);
      }

      // ── C1: Seed LotCache from login response ─────────────────────────────────
      await lotCache.seedFromLogin(assignedLots);

      // ── Also write the worker into AuthProvider so isLoggedIn becomes true ────
      if (mounted) {
        await context.read<AuthProvider>().loginAsSupervisor(worker);
        context.go('/home');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      // B2: surface role-gate rejection clearly
      final isRoleError = msg.toLowerCase().contains('does not have supervisor access') ||
          msg.toLowerCase().contains('eligible roles');
      setState(() {
        _error = isRoleError
            ? 'This account is not authorised for supervisor mode.'
            : msg;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(
          onPressed: () => context.go('/select-worker'),
        ),
        title: const Text(
          'Supervisor Mode',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.supervisor_account,
                        size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Sign in as Supervisor',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Use your Survey App credentials',
                    style: TextStyle(fontSize: 14, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 40),

                // ── Email ────────────────────────────────────────────────────────
                const Text('Email',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('your@email.com',
                      prefixIcon: Icons.email_outlined),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ── Password ─────────────────────────────────────────────────────
                const Text('Password',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('••••••••',
                      prefixIcon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white38,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      )),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Password is required';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // ── Error ────────────────────────────────────────────────────────
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Submit ───────────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint, {
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: const Color(0xFF1A2A3A),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: Colors.white38, size: 20)
            : null,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
      );
}

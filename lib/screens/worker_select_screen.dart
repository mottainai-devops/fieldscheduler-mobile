import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Phone + PIN login screen.
///
/// Replaces the old worker-list selection screen.
/// Flow:
///   1. User enters their phone number and taps Continue (or enters 4th PIN digit).
///   2. App resolves workerId via workerAuth.getByPhone.
///   3. App calls workerAuth.verifyPin(workerId, pin).
///   4. On success, AuthProvider.selectWorker() is called and the user is
///      routed to /home.
class WorkerSelectScreen extends StatefulWidget {
  const WorkerSelectScreen({super.key});

  @override
  State<WorkerSelectScreen> createState() => _WorkerSelectScreenState();
}

class _WorkerSelectScreenState extends State<WorkerSelectScreen> {
  final _phoneController = TextEditingController();
  final _phoneFocus = FocusNode();

  // Resolved worker (after phone lookup)
  Map<String, dynamic>? _worker;

  // UI state
  bool _lookingUp = false;
  bool _loggingIn = false;
  String? _phoneError;
  String? _pinError;
  String _pin = '';

  // Phase: 'phone' = entering phone, 'pin' = entering PIN
  String _phase = 'phone';

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  // ── Phone lookup ─────────────────────────────────────────────────────────────

  Future<void> _lookupPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _phoneError = 'Enter your phone number');
      return;
    }
    if (phone.length < 7) {
      setState(() => _phoneError = 'Phone number too short');
      return;
    }
    setState(() { _lookingUp = true; _phoneError = null; });
    try {
      final worker = await ApiService.getWorkerByPhone(phone);
      if (!mounted) return;
      if (worker == null) {
        setState(() {
          _phoneError = 'No account found for this number. Contact your administrator.';
          _lookingUp = false;
        });
        return;
      }
      setState(() {
        _worker = worker;
        _phase = 'pin';
        _lookingUp = false;
        _pinError = null;
        _pin = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phoneError = 'Could not connect. Check your internet and try again.';
        _lookingUp = false;
      });
    }
  }

  // ── PIN verification ─────────────────────────────────────────────────────────

  Future<void> _handlePin(String pin) async {
    if (pin.length < 4) return;
    final worker = _worker;
    if (worker == null) return;
    setState(() { _loggingIn = true; _pinError = null; });
    try {
      final workerId = worker['id'] as int;
      await ApiService.loginWithPin(workerId, pin);
      if (!mounted) return;
      await context.read<AuthProvider>().selectWorker(worker);
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pinError = 'Incorrect PIN. Please try again.';
        _loggingIn = false;
        _pin = '';
      });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _initials(String name) {
    final parts = name.trim().split(' ');
    return parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF1565C0),
      Color(0xFF00897B),
      Color(0xFF6A1B9A),
      Color(0xFF2E7D32),
      Color(0xFFAD1457),
    ];
    return name.isNotEmpty ? colors[name.codeUnitAt(0) % colors.length] : colors[0];
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 48),
                    // ── App icon ────────────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/icons/app_icon_1024.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Field Worker App',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _phase == 'phone'
                          ? 'Enter your phone number to continue'
                          : 'Enter your 4-digit PIN',
                      style: const TextStyle(fontSize: 15, color: Colors.white60),
                    ),
                    const SizedBox(height: 40),

                    // ── Phase: phone ────────────────────────────────────────
                    if (_phase == 'phone') ...[
                      _PhoneField(
                        controller: _phoneController,
                        focusNode: _phoneFocus,
                        error: _phoneError,
                        onSubmitted: (_) => _lookupPhone(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _lookingUp ? null : _lookupPhone,
                          child: _lookingUp
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],

                    // ── Phase: pin ──────────────────────────────────────────
                    if (_phase == 'pin' && _worker != null) ...[
                      // Worker avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _avatarColor(_worker!['name'] as String? ?? ''),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials(_worker!['name'] as String? ?? ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _worker!['name'] as String? ?? '',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _worker!['phone'] as String? ?? '',
                        style: const TextStyle(fontSize: 13, color: Colors.white54),
                      ),
                      const SizedBox(height: 32),
                      // PIN dots
                      PinCodeTextField(
                        appContext: context,
                        length: 4,
                        obscureText: true,
                        obscuringCharacter: '●',
                        animationType: AnimationType.fade,
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: _pin),
                        pinTheme: PinTheme(
                          shape: PinCodeFieldShape.circle,
                          fieldHeight: 56,
                          fieldWidth: 56,
                          activeFillColor: const Color(0xFF1A2A3A),
                          inactiveFillColor: const Color(0xFF1A2A3A),
                          selectedFillColor: const Color(0xFF243447),
                          activeColor: const Color(0xFF1565C0),
                          inactiveColor: Colors.white24,
                          selectedColor: const Color(0xFF42A5F5),
                        ),
                        enableActiveFill: true,
                        onChanged: (val) {
                          _pin = val;
                          if (_pinError != null) setState(() => _pinError = null);
                        },
                        onCompleted: _handlePin,
                      ),
                      if (_pinError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _pinError!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_loggingIn) ...[
                        const SizedBox(height: 16),
                        const CircularProgressIndicator(color: Colors.white),
                      ],
                      const SizedBox(height: 16),
                      // Back to phone entry
                      TextButton(
                        onPressed: () => setState(() {
                          _phase = 'phone';
                          _worker = null;
                          _pinError = null;
                          _pin = '';
                        }),
                        child: const Text(
                          '← Use a different number',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Text(
                      'Contact your administrator if you need help',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.35),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Supervisor Mode + footer ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: TextButton.icon(
                onPressed: () => context.go('/supervisor-login'),
                icon: const Icon(
                  Icons.supervisor_account,
                  color: Color(0xFF90CAF9),
                  size: 18,
                ),
                label: const Text(
                  'Supervisor Mode',
                  style: TextStyle(color: Color(0xFF90CAF9), fontSize: 14),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                '© 2025 Field Scheduler',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Extracted phone input widget ───────────────────────────────────────────────

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2A3A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: error != null ? Colors.redAccent : Colors.white12,
              width: 1.2,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s+\-()]'))],
            style: const TextStyle(color: Colors.white, fontSize: 17, letterSpacing: 1.2),
            decoration: const InputDecoration(
              hintText: 'e.g. 09065867097',
              hintStyle: TextStyle(color: Colors.white30, fontSize: 15),
              prefixIcon: Icon(Icons.phone_outlined, color: Colors.white38, size: 20),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onSubmitted: onSubmitted,
            textInputAction: TextInputAction.done,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

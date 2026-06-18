import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _worker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    _worker = extra?['worker'] as Map<String, dynamic>?;
  }

  Future<void> _handlePin(String pin) async {
    if (pin.length < 4) return;
    final worker = _worker;
    if (worker == null) {
      setState(() => _error = 'No worker selected. Go back and pick your profile.');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final workerId = worker['id'] as int;
      await ApiService.loginWithPin(workerId, pin);
      // PIN accepted — persist session
      if (!mounted) return;
      await context.read<AuthProvider>().selectWorker(worker);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _error = 'Incorrect PIN. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _worker?['name'] as String? ?? '';
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : 'FW';
    final colors = [
      const Color(0xFF1565C0),
      const Color(0xFF00897B),
      const Color(0xFF6A1B9A),
      const Color(0xFF2E7D32),
      const Color(0xFFAD1457),
    ];
    final avatarColor = name.isNotEmpty
        ? colors[name.codeUnitAt(0) % colors.length]
        : const Color(0xFF1565C0);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/select-worker'),
        ),
        title: const Text('Enter PIN', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Worker avatar
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (name.isNotEmpty) ...[
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                const Text(
                  'Enter your 4-digit PIN',
                  style: TextStyle(fontSize: 15, color: Colors.white60),
                ),
                const SizedBox(height: 40),
                // PIN dots
                PinCodeTextField(
                  appContext: context,
                  length: 4,
                  obscureText: true,
                  obscuringCharacter: '●',
                  animationType: AnimationType.fade,
                  keyboardType: TextInputType.number,
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
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onCompleted: _handlePin,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_isLoading) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: Colors.white),
                ],
                const SizedBox(height: 32),
                Text(
                  'Contact your administrator if you forgot your PIN',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

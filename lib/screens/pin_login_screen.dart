import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../services/api_service.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});
  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _handlePin(String pin) async {
    if (pin.length < 4) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final workers = await ApiService.getAllWorkers();
      if (workers.isEmpty) {
        setState(() { _error = 'No workers found. Contact your administrator.'; _isLoading = false; });
        return;
      }
      if (!mounted) return;
      context.go('/select-worker', extra: {'pin': pin, 'workers': workers});
    } catch (e) {
      setState(() { _error = 'Connection failed. Check your internet connection.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.work_outline, size: 80, color: Colors.white),
                const SizedBox(height: 16),
                const Text('FieldWorker',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Enter your PIN to continue',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      PinCodeTextField(
                        appContext: context,
                        length: 4,
                        obscureText: true,
                        animationType: AnimationType.fade,
                        keyboardType: TextInputType.number,
                        pinTheme: PinTheme(
                          shape: PinCodeFieldShape.box,
                          borderRadius: BorderRadius.circular(8),
                          fieldHeight: 56,
                          fieldWidth: 56,
                          activeFillColor: Colors.white,
                          inactiveFillColor: Colors.grey.shade100,
                          selectedFillColor: Colors.blue.shade50,
                          activeColor: const Color(0xFF1565C0),
                          inactiveColor: Colors.grey.shade300,
                          selectedColor: const Color(0xFF1565C0),
                        ),
                        enableActiveFill: true,
                        onChanged: (_) {},
                        onCompleted: _handlePin,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                            textAlign: TextAlign.center),
                      ],
                      if (_isLoading) ...[
                        const SizedBox(height: 16),
                        const CircularProgressIndicator(),
                      ],
                      const SizedBox(height: 16),
                      Text('Contact your administrator if you forgot your PIN',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

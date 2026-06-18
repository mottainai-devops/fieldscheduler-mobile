import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ReportViolationScreen extends StatefulWidget {
  final int customerId;
  final int routeId;
  final String? customerName;
  const ReportViolationScreen({super.key, required this.customerId, required this.routeId, this.customerName});
  @override
  State<ReportViolationScreen> createState() => _ReportViolationScreenState();
}

class _ReportViolationScreenState extends State<ReportViolationScreen> {
  List<dynamic> _violationTypes = [];
  int? _selectedTypeId;
  String _severity = 'medium';
  final _descController = TextEditingController();
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadViolationTypes();
  }

  Future<void> _loadViolationTypes() async {
    setState(() { _isLoading = true; });
    try {
      final types = await ApiService.getViolationTypes();
      setState(() { _violationTypes = types; _isLoading = false; });
    } catch (e) {
      setState(() { _error = 'Failed to load violation types.'; _isLoading = false; });
    }
  }

  Future<void> _submit() async {
    if (_selectedTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a violation type')));
      return;
    }
    setState(() { _isSubmitting = true; });
    try {
      final auth = context.read<AuthProvider>();
      await ApiService.reportViolation(
        customerId: widget.customerId,
        routeId: widget.routeId,
        violationTypeId: _selectedTypeId!,
        description: _descController.text,
        severity: _severity,
        workerId: auth.workerId ?? 0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Violation reported successfully'), backgroundColor: Colors.green));
        context.pop();
      }
    } catch (e) {
      setState(() { _isSubmitting = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.customerName != null ? 'Report Violation — ${widget.customerName}' : 'Report Violation')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Violation Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (_violationTypes.isEmpty)
                    const Text('No violation types available', style: TextStyle(color: Colors.grey))
                  else
                    ...(_violationTypes.map((t) {
                      final id = t['id'] as int;
                      final name = t['name'] as String? ?? 'Unknown';
                      return RadioListTile<int>(
                        value: id,
                        groupValue: _selectedTypeId,
                        title: Text(name),
                        onChanged: (v) => setState(() => _selectedTypeId = v),
                        contentPadding: EdgeInsets.zero,
                      );
                    })),
                  const SizedBox(height: 20),
                  const Text('Severity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'low', label: Text('Low'), icon: Icon(Icons.arrow_downward)),
                      ButtonSegment(value: 'medium', label: Text('Medium'), icon: Icon(Icons.remove)),
                      ButtonSegment(value: 'high', label: Text('High'), icon: Icon(Icons.arrow_upward)),
                    ],
                    selected: {_severity},
                    onSelectionChanged: (s) => setState(() => _severity = s.first),
                  ),
                  const SizedBox(height: 20),
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Describe the violation...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _isSubmitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit Violation Report', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }
}

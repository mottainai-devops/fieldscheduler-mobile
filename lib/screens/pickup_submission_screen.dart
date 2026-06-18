import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

/// Pickup submission screen for supervisors.
/// Pre-fills customer data from the route customer record and collects
/// bin type, bin quantity, before/after photos, and an optional incident report.
class PickupSubmissionScreen extends StatefulWidget {
  final int routeId;
  final int customerId;
  final Map<String, dynamic> customer;

  const PickupSubmissionScreen({
    super.key,
    required this.routeId,
    required this.customerId,
    required this.customer,
  });

  @override
  State<PickupSubmissionScreen> createState() => _PickupSubmissionScreenState();
}

class _PickupSubmissionScreenState extends State<PickupSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _incidentController = TextEditingController();
  final _binQtyController = TextEditingController(text: '1');

  String _binType = 'Wheelie Bin';
  File? _beforePhoto;
  File? _afterPhoto;
  bool _isSubmitting = false;
  String? _error;

  static const List<String> _binTypes = [
    'Wheelie Bin',
    'Bag',
    'Skip',
    'Container',
    'Other',
  ];

  Map<String, dynamic> get _cd => widget.customer['customer'] ?? widget.customer;

  String get _customerName =>
      (_cd['name'] ?? widget.customer['customerName'] ?? '').toString();
  String get _customerPhone => (_cd['phone'] ?? '').toString();
  String get _customerAddress => (_cd['address'] ?? '').toString();
  String get _mafCode =>
      (_cd['customermaf'] ?? _cd['maf'] ?? '').toString();
  String get _buildingId =>
      (_cd['buildingId'] ?? _cd['arcgisBuildingId'] ?? '').toString();
  String get _unitCode => (_cd['unitCode'] ?? '').toString();

  @override
  void dispose() {
    _incidentController.dispose();
    _binQtyController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(bool isBefore) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (picked == null) return;
    setState(() {
      if (isBefore) {
        _beforePhoto = File(picked.path);
      } else {
        _afterPhoto = File(picked.path);
      }
    });
  }

  Future<String> _toBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_beforePhoto == null) {
      setState(() => _error = 'Before photo is required');
      return;
    }
    if (_afterPhoto == null) {
      setState(() => _error = 'After photo is required');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final supervisorId = auth.workerName ?? 'Supervisor';
      final qty = int.tryParse(_binQtyController.text.trim()) ?? 1;

      final beforeB64 = await _toBase64(_beforePhoto!);
      final afterB64 = await _toBase64(_afterPhoto!);

      await ApiService.submitPickup(
        routeId: widget.routeId,
        customerId: widget.customerId,
        supervisorId: supervisorId,
        binType: _binType,
        binQuantity: qty,
        beforePhotoBase64: beforeB64,
        afterPhotoBase64: afterB64,
        incidentReport: _incidentController.text.trim(),
        customerName: _customerName,
        customerPhone: _customerPhone,
        customerAddress: _customerAddress,
        mafCode: _mafCode,
        buildingId: _buildingId,
        unitCode: _unitCode,
      );

      if (mounted) {
        Navigator.pop(context, true); // true = success, caller marks as Picked
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          'Record Pickup',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Customer Info ──────────────────────────────────────────────
              _sectionLabel('Customer'),
              _infoRow('Name', _customerName),
              if (_customerPhone.isNotEmpty) _infoRow('Phone', _customerPhone),
              if (_customerAddress.isNotEmpty)
                _infoRow('Address', _customerAddress),
              if (_mafCode.isNotEmpty) _infoRow('MAF Code', _mafCode),
              if (_buildingId.isNotEmpty)
                _infoRow('Building ID', _buildingId),
              const SizedBox(height: 20),

              // ── Bin Details ────────────────────────────────────────────────
              _sectionLabel('Bin Details'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _binType,
                dropdownColor: AppTheme.bgCard,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Bin Type'),
                items: _binTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t,
                              style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _binType = v ?? _binType),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _binQtyController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Bin Quantity'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (int.tryParse(v.trim()) == null || int.parse(v.trim()) < 1) {
                    return 'Enter a valid quantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Photos ─────────────────────────────────────────────────────
              _sectionLabel('Photos'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _photoCard(
                      label: 'Before',
                      file: _beforePhoto,
                      onTap: () => _pickPhoto(true),
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _photoCard(
                      label: 'After',
                      file: _afterPhoto,
                      onTap: () => _pickPhoto(false),
                      required: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Incident Report ────────────────────────────────────────────
              _sectionLabel('Incident Report (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _incidentController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Describe any incident…'),
              ),
              const SizedBox(height: 24),

              // ── Error ──────────────────────────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)),
                ),

              // ── Submit ─────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Submit Pickup',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _photoCard({
    required String label,
    required File? file,
    required VoidCallback onTap,
    bool required = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: file != null
                ? Colors.green.withOpacity(0.5)
                : Colors.white.withOpacity(0.2),
          ),
        ),
        child: file != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.file(file, fit: BoxFit.cover,
                    width: double.infinity),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt,
                      color: required ? Colors.orange : Colors.white38,
                      size: 32),
                  const SizedBox(height: 6),
                  Text(
                    '$label Photo${required ? ' *' : ''}',
                    style: TextStyle(
                      color: required ? Colors.orange : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: AppTheme.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppTheme.primaryColor),
        ),
      );
}

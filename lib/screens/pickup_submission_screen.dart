import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../services/lot_cache.dart';
import '../utils/theme.dart';

/// Pickup submission screen for supervisors.
///
/// Area D (§4): Submits the full Survey App schema directly to the resolved
/// webhook URL via http.MultipartRequest — NOT via the workerAuth.submitPickup
/// tRPC proxy.
///
/// Key changes from the previous version:
///   D1  — Authorization: Bearer header is attached by ApiService._getHeaders()
///          at request time; no change needed here.
///   D3  — Full provenance payload per §4.1 (userId, companyId, companyName,
///          lotCode, lotName, socioClass, submittedFrom, supervisorId, etc.)
///   D4  — Null omission helper skips null / empty / "null" / "undefined" values.
///   D5  — Webhook URL resolved from cached lot by customerType (billing type):
///          monthlyBilling → monthlyWebhook, otherwise → paytWebhook.
///   BIN — Seven Survey App bin types; wheelieBinType sub-dropdown shown when
///          the selected bin type is a wheelie variant.
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

  // D3: Seven Survey App bin types (§4.1)
  static const List<String> _binTypes = [
    'Wheelie Bin 120L',
    'Wheelie Bin 240L',
    'Wheelie Bin 360L',
    'Bag',
    'Skip',
    'Container',
    'Other',
  ];

  // Wheelie sub-types shown only when a wheelie variant is selected
  static const List<String> _wheelieBinSubTypes = [
    'Residential',
    'Commercial',
  ];

  static bool _isWheelieType(String t) => t.startsWith('Wheelie Bin');

  String _binType = 'Wheelie Bin 120L';
  String _wheelieBinType = 'Residential';
  File? _beforePhoto;
  File? _afterPhoto;
  bool _isSubmitting = false;
  String? _error;

  // ─── Customer field accessors ────────────────────────────────────────────────

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
  String get _socioClass => (_cd['socioClass'] ?? '').toString();

  /// D3: customerType sourced from the customer record's billing type,
  /// not the supervisor's global preference.
  String get _customerType =>
      (_cd['customerType'] ?? _cd['billingType'] ?? _cd['type'] ?? '').toString();

  /// D3: composite customerId = "${arcgisBuildingId}-${unitCode}" with HYPHEN.
  /// Falls back to String(customer.id) only if either component is null/empty.
  String get _compositeCustomerId {
    final bId = _buildingId;
    final uCode = _unitCode;
    if (bId.isNotEmpty && uCode.isNotEmpty) return '$bId-$uCode';
    return widget.customerId.toString();
  }

  @override
  void dispose() {
    _incidentController.dispose();
    _binQtyController.dispose();
    super.dispose();
  }

  // ─── Photo picker ────────────────────────────────────────────────────────────

  Future<void> _pickPhoto(bool isBefore) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
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

  // ─── D4: Null omission helper ────────────────────────────────────────────────

  /// Returns true if the value should be omitted from the multipart payload.
  static bool _isBlank(dynamic v) {
    if (v == null) return true;
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' || s == 'undefined';
  }

  /// Add a field to the multipart request only if it is non-blank.
  static void _addField(
      http.MultipartRequest req, String key, dynamic value) {
    if (!_isBlank(value)) {
      req.fields[key] = value.toString().trim();
    }
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

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

      // ── D5: Resolve webhook URL from cached lot by customerType ──────────────
      // C3: On cache miss, NoAccessibleLotException is thrown — no fallback.
      final lot = lotCache.resolveByMafCode(_mafCode);

      // D5: Route by billing type — monthlyBilling customers → monthlyWebhook
      final isMonthly = _customerType.toLowerCase().contains('monthly') ||
          (_cd['monthlyBilling'] == true);
      final webhookUrl = isMonthly
          ? (lot['monthlyWebhook'] as String?)
          : (lot['paytWebhook'] as String?);

      if (webhookUrl == null || webhookUrl.isEmpty) {
        throw Exception(
            'No webhook URL found for this lot (lotCode=${lot['lotCode']}). '
            'Contact your administrator.');
      }

      // ── D3: Build the full multipart request ─────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('worker_email') ??
          auth.workerEmail ??
          auth.workerId?.toString() ??
          '';
      final companyId = prefs.getString('companyId') ?? auth.companyId ?? '';
      final companyName = prefs.getString('companyName') ?? auth.companyName ?? '';
      final supervisorFullName = auth.workerName ?? 'Supervisor';
      final qty = int.tryParse(_binQtyController.text.trim()) ?? 1;

      final uri = Uri.parse(webhookUrl);
      final req = http.MultipartRequest('POST', uri);

      // Core identity fields
      _addField(req, 'userId', userId);
      _addField(req, 'companyId', companyId);
      _addField(req, 'companyName', companyName);
      _addField(req, 'supervisorId', supervisorFullName);
      _addField(req, 'submittedFrom', 'FieldWorker');

      // Lot fields
      _addField(req, 'lotCode', lot['lotCode']);
      _addField(req, 'lotName', lot['lotName']);

      // Customer fields
      _addField(req, 'customerId', _compositeCustomerId);
      _addField(req, 'customerName', _customerName);
      _addField(req, 'customerPhone', _customerPhone);
      _addField(req, 'customerAddress', _customerAddress);
      _addField(req, 'mafCode', _mafCode);
      _addField(req, 'buildingId', _buildingId);
      _addField(req, 'unitCode', _unitCode);
      _addField(req, 'customerType', _customerType);
      _addField(req, 'socioClass', _socioClass);

      // Bin fields
      _addField(req, 'binType', _binType);
      if (_isWheelieType(_binType)) {
        _addField(req, 'wheelieBinType', _wheelieBinType);
      }
      _addField(req, 'binQuantity', qty);

      // Incident report (optional)
      _addField(req, 'incidentReport', _incidentController.text.trim());

      // Photos as multipart files
      req.files.add(await http.MultipartFile.fromPath(
          'beforePhoto', _beforePhoto!.path));
      req.files.add(await http.MultipartFile.fromPath(
          'afterPhoto', _afterPhoto!.path));

      final streamed = await req.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'Survey App returned ${response.statusCode}: ${response.body}');
      }

      if (mounted) {
        Navigator.pop(context, true); // true = success, caller marks as Picked
      }
    } on NoAccessibleLotException catch (e) {
      setState(() {
        _error = e.message;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

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
              if (_customerType.isNotEmpty)
                _infoRow('Customer Type', _customerType),
              if (_socioClass.isNotEmpty)
                _infoRow('Socio Class', _socioClass),
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
              // Wheelie sub-type — shown only for wheelie variants
              if (_isWheelieType(_binType)) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _wheelieBinType,
                  dropdownColor: AppTheme.bgCard,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Wheelie Bin Type'),
                  items: _wheelieBinSubTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t,
                                style: const TextStyle(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _wheelieBinType = v ?? _wheelieBinType),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _binQtyController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Bin Quantity'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (int.tryParse(v.trim()) == null ||
                      int.parse(v.trim()) < 1) {
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

  // ─── Helpers ─────────────────────────────────────────────────────────────────

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
              width: 100,
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

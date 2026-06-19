import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../services/database.dart';
import '../services/lot_cache.dart';
import '../services/photo_store.dart';
import '../services/pickup_queue.dart';
import '../utils/theme.dart';

/// Pickup submission screen for supervisors.
///
/// Tranche 1 (Area D) + Tranche 2 (Sub-areas 6, E7):
///
///   D1  — Authorization: Bearer header read live from secure storage.
///   D3  — Full provenance payload per §4.1.
///   D4  — Null omission helper.
///   D5  — Webhook URL resolved from LotCache by customerType.
///   E6  — Draft auto-save (debounced 500ms) keyed on routeCustomerId.
///          Rehydrates form on reopen. Draft deleted on successful enqueue.
///   E7  — Submission refactored to use PickupQueue.enqueue() — synchronous
///          submit path is gone. Pickup feels instant regardless of connectivity.
class PickupSubmissionScreen extends StatefulWidget {
  final int routeId;
  final int customerId;
  final Map<String, dynamic> customer;

  /// Optional: the route_customer_id used as the draft key.
  /// If not provided, falls back to customerId.
  final int? routeCustomerId;

  const PickupSubmissionScreen({
    super.key,
    required this.routeId,
    required this.customerId,
    required this.customer,
    this.routeCustomerId,
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

  // E6: draft key
  int get _draftKey => widget.routeCustomerId ?? widget.customerId;

  // E6: debounce timer for auto-save
  Timer? _draftSaveTimer;

  @override
  void initState() {
    super.initState();
    _rehydrateDraft();
    // Listen to form field changes for auto-save
    _incidentController.addListener(_scheduleDraftSave);
    _binQtyController.addListener(_scheduleDraftSave);
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _incidentController.removeListener(_scheduleDraftSave);
    _binQtyController.removeListener(_scheduleDraftSave);
    _incidentController.dispose();
    _binQtyController.dispose();
    super.dispose();
  }

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

  String get _customerType =>
      (_cd['customerType'] ?? _cd['billingType'] ?? _cd['type'] ?? '').toString();

  String get _compositeCustomerId {
    final bId = _buildingId;
    final uCode = _unitCode;
    if (bId.isNotEmpty && uCode.isNotEmpty) return '$bId-$uCode';
    return widget.customerId.toString();
  }

  // ─── E6: Draft persistence ───────────────────────────────────────────────────

  /// Rehydrate form state from the saved draft (if any).
  Future<void> _rehydrateDraft() async {
    final draft = await AppDatabase.instance.getDraft(_draftKey);
    if (draft == null) return;
    try {
      final state = jsonDecode(draft['form_state_json'] as String)
          as Map<String, dynamic>;
      setState(() {
        _binType = (state['binType'] as String?) ?? _binType;
        _wheelieBinType = (state['wheelieBinType'] as String?) ?? _wheelieBinType;
        _incidentController.text = (state['incidentReport'] as String?) ?? '';
        _binQtyController.text = (state['binQuantity'] as String?) ?? '1';
      });
      // Rehydrate photo paths
      final beforePath = draft['before_photo_path'] as String?;
      final afterPath = draft['after_photo_path'] as String?;
      if (beforePath != null && beforePath.isNotEmpty) {
        final f = File(beforePath);
        if (await f.exists()) setState(() => _beforePhoto = f);
      }
      if (afterPath != null && afterPath.isNotEmpty) {
        final f = File(afterPath);
        if (await f.exists()) setState(() => _afterPhoto = f);
      }
    } catch (_) {}
  }

  /// Schedule a debounced draft save (500ms after last change).
  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  /// Persist current form state to pickup_drafts.
  Future<void> _saveDraft() async {
    final state = {
      'binType': _binType,
      'wheelieBinType': _wheelieBinType,
      'incidentReport': _incidentController.text.trim(),
      'binQuantity': _binQtyController.text.trim(),
    };
    await AppDatabase.instance.upsertDraft({
      'route_customer_id': _draftKey,
      'route_id': widget.routeId,
      'customer_id': widget.customerId,
      'form_state_json': jsonEncode(state),
      'before_photo_path': _beforePhoto?.path ?? '',
      'after_photo_path': _afterPhoto?.path ?? '',
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    });
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
    _scheduleDraftSave();
  }

  // ─── D1: Auth helper ──────────────────────────────────────────────────────────

  static Future<void> _attachAuth(http.MultipartRequest req) async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'workerSurveyToken');
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
  }

  // ─── D4: Null omission helper ────────────────────────────────────────────────

  static bool _isBlank(dynamic v) {
    if (v == null) return true;
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' || s == 'undefined';
  }

  static void _addField(
      http.MultipartRequest req, String key, dynamic value) {
    if (!_isBlank(value)) {
      req.fields[key] = value.toString().trim();
    }
  }

  // ─── E7: Enqueue (replaces synchronous _submit) ──────────────────────────────

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
      final lot = lotCache.resolveByMafCode(_mafCode);

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

      // ── D3: Build payload field bag ──────────────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('surveyAppUserId') ??
          prefs.getString('worker_email') ??
          auth.workerEmail ??
          auth.workerId?.toString() ??
          '';
      final companyId = prefs.getString('companyId') ?? auth.companyId ?? '';
      final companyName = prefs.getString('companyName') ?? auth.companyName ?? '';
      final supervisorFullName = auth.workerName ?? 'Supervisor';
      final qty = int.tryParse(_binQtyController.text.trim()) ?? 1;
      final customerEmail =
          (_cd['email'] ?? _cd['customerEmail'] ?? '').toString();
      final latitude = (_cd['latitude'] ?? _cd['lat'] ?? '').toString();
      final longitude =
          (_cd['longitude'] ?? _cd['lng'] ?? _cd['lon'] ?? '').toString();
      final pickUpDate =
          DateTime.now().toIso8601String().substring(0, 10);

      final payload = <String, dynamic>{};

      void addToPayload(String key, dynamic value) {
        if (!_isBlank(value)) payload[key] = value.toString().trim();
      }

      addToPayload('userId', userId);
      addToPayload('companyId', companyId);
      addToPayload('companyName', companyName);
      addToPayload('supervisorId', supervisorFullName);
      addToPayload('submittedFrom', 'FieldWorker');
      addToPayload('lotCode', lot['lotCode']);
      addToPayload('lotName', lot['lotName']);
      addToPayload('customerId', _compositeCustomerId);
      addToPayload('customerName', _customerName);
      addToPayload('customerPhone', _customerPhone);
      addToPayload('customerAddress', _customerAddress);
      addToPayload('mafCode', _mafCode);
      addToPayload('buildingId', _buildingId);
      addToPayload('unitCode', _unitCode);
      addToPayload('customerType', _customerType);
      addToPayload('socioClass', _socioClass);
      addToPayload('binType', _binType);
      if (_isWheelieType(_binType)) {
        addToPayload('wheelieBinType', _wheelieBinType);
      }
      addToPayload('binQuantity', qty);
      addToPayload('customerEmail', customerEmail);
      addToPayload('latitude', latitude);
      addToPayload('longitude', longitude);
      addToPayload('pickUpDate', pickUpDate);
      addToPayload('incidentReport', _incidentController.text.trim());

      // ── E2: Resize-and-store photos ──────────────────────────────────────────
      final beforePath =
          await PhotoStore.storePhoto(_beforePhoto!, prefix: 'before');
      final afterPath =
          await PhotoStore.storePhoto(_afterPhoto!, prefix: 'after');

      // ── E7: Enqueue — no direct network call here ────────────────────────────
      await pickupQueue.enqueue(
        routeId: widget.routeId,
        customerId: widget.customerId,
        customerName: _customerName,
        lotCode: (lot['lotCode'] ?? '').toString(),
        payload: payload,
        beforePath: beforePath,
        afterPath: afterPath,
        webhookUrl: webhookUrl,
      );

      // E6: Delete draft on successful enqueue
      await AppDatabase.instance.deleteDraft(_draftKey);

      // E7: Trigger flush in background (fire and forget)
      pickupQueue.flush();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pickup queued — will submit when online'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        // Return true so route_detail_screen marks customer as picked optimistically
        Navigator.pop(context, true);
      }
    } on QueueFullException catch (e) {
      setState(() {
        _error = e.message;
        _isSubmitting = false;
      });
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
                onChanged: (v) {
                  setState(() => _binType = v ?? _binType);
                  _scheduleDraftSave();
                },
              ),
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
                  onChanged: (v) {
                    setState(() => _wheelieBinType = v ?? _wheelieBinType);
                    _scheduleDraftSave();
                  },
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
                          'Queue Pickup',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              // E7: Offline-first hint
              const Center(
                child: Text(
                  'Pickup will be submitted when online',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
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
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: file != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(file, fit: BoxFit.cover),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined,
                        color: required ? Colors.orange : AppTheme.textSecondary,
                        size: 28),
                    const SizedBox(height: 6),
                    Text(
                      label + (required ? ' *' : ''),
                      style: TextStyle(
                        color: required
                            ? Colors.orange
                            : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

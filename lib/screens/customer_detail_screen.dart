import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import 'report_violation_screen.dart';
import 'customer_notes_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  final String? customerName;
  final int routeId;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.customerName,
    required this.routeId,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, dynamic>? _customer;
  List<dynamic> _invoices = [];
  List<dynamic> _violations = [];
  List<dynamic> _notices = [];
  Map<String, dynamic>? _statement;
  List<dynamic> _payments = [];
  Map<String, dynamic>? _linkageStatus;

  bool _isLoading = true;
  String? _error;
  String _invoiceSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final customerData = await ApiService.getCustomerById(widget.customerId);
      final zohoContactId = customerData['zohoContactId']?.toString();

      final results = await Future.wait([
        zohoContactId != null && zohoContactId.isNotEmpty
            ? ApiService.getCustomerInvoicesByZohoId(zohoContactId)
            : Future.value(<dynamic>[]),
        ApiService.getViolationsByCustomer(widget.customerId),
        ApiService.getAbatementNoticesByCustomer(widget.customerId),
        ApiService.getCustomerStatement(widget.customerId).catchError((_) => <String, dynamic>{}),
        zohoContactId != null && zohoContactId.isNotEmpty
            ? ApiService.getCustomerPayments(zohoContactId).catchError((_) => <dynamic>[])
            : Future.value(<dynamic>[]),
        ApiService.getCustomerLinkageStatus(widget.customerId).catchError((_) => <String, dynamic>{}),
      ]);

      if (mounted) {
        setState(() {
          _customer = customerData;
          _invoices = results[0] as List<dynamic>;
          _violations = results[1] as List<dynamic>;
          _notices = results[2] as List<dynamic>;
          _statement = results[3] is Map<String, dynamic> ? results[3] as Map<String, dynamic> : null;
          _payments = results[4] as List<dynamic>;
          _linkageStatus = results[5] is Map<String, dynamic> ? results[5] as Map<String, dynamic> : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _isLoading = false; });
    }
  }

  Future<void> _navigateToCustomer() async {
    final c = _customer!;
    final lat = c['latitude'] ?? c['lat'];
    final lng = c['longitude'] ?? c['lng'] ?? c['lon'];
    if (lat == null || lng == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No GPS coordinates for this customer')));
      return;
    }
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final mapsUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open maps: $e')));
      }
    }
  }

  void _showLinkBuildingIdDialog() {
    final searchController = TextEditingController();
    List<dynamic> searchResults = [];
    bool searching = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Link Building ID', style: TextStyle(color: AppTheme.textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Search for the main building to link this customer as an annex.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(hintText: 'Search by name or ID...', prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary)),
                  onChanged: (v) async {
                    if (v.length < 2) return;
                    setDialogState(() => searching = true);
                    try {
                      final results = await ApiService.getCustomers(search: v);
                      setDialogState(() {
                        searchResults = results.where((r) => (r['id'] ?? r['customerId']) != widget.customerId).take(5).toList();
                        searching = false;
                      });
                    } catch (_) { setDialogState(() => searching = false); }
                  },
                ),
                const SizedBox(height: 8),
                if (searching) const Center(child: CircularProgressIndicator())
                else ...searchResults.map((r) {
                  final name = (r['name'] ?? r['customerName'] ?? 'Unknown').toString();
                  final id = r['id'] ?? r['customerId'];
                  return ListTile(
                    dense: true,
                    title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    subtitle: Text('ID: $id', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        final worker = await ApiService.getCurrentWorker();
                        await ApiService.createLinkageRequest(
                          mainCustomerId: id is int ? id : int.tryParse(id.toString()) ?? 0,
                          annexCustomerId: widget.customerId,
                          requestedBy: worker?['id'] ?? 0,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Linkage request submitted!'), backgroundColor: Colors.green));
                          _loadData();
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
                      }
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        ),
      ),
    );
  }

  void _showUploadPaymentProofDialog(Map<String, dynamic>? invoice) {
    final amountController = TextEditingController(text: invoice?['balance']?.toString() ?? invoice?['total']?.toString() ?? '');
    final notesController = TextEditingController();
    String? selectedMethod;
    File? selectedFile;
    bool uploading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Upload Payment Proof', style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (invoice != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppTheme.bgCardLight, borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.receipt, color: AppTheme.primaryColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Invoice: ${invoice['invoiceNumber'] ?? invoice['id'] ?? 'N/A'}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
                    ]),
                  ),
                const SizedBox(height: 12),
                TextField(controller: amountController, style: const TextStyle(color: AppTheme.textPrimary), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (N)', prefixIcon: Icon(Icons.attach_money, color: AppTheme.textSecondary))),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedMethod,
                  dropdownColor: AppTheme.bgCard,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Payment Method', prefixIcon: Icon(Icons.payment, color: AppTheme.textSecondary)),
                  items: ['Cash', 'Bank Transfer', 'POS', 'Mobile Money', 'Cheque'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setDialogState(() => selectedMethod = v),
                ),
                const SizedBox(height: 10),
                TextField(controller: notesController, style: const TextStyle(color: AppTheme.textPrimary), maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.note, color: AppTheme.textSecondary))),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                    if (picked != null) setDialogState(() => selectedFile = File(picked.path));
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(selectedFile != null ? selectedFile!.path.split('/').last : 'Attach Receipt / Photo'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryColor, side: const BorderSide(color: AppTheme.primaryColor)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: uploading ? null : () async {
                if (selectedFile == null) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please attach a receipt or photo'))); return; }
                setDialogState(() => uploading = true);
                try {
                  final bytes = await selectedFile!.readAsBytes();
                  final base64Data = base64Encode(bytes);
                  final fileName = selectedFile!.path.split('/').last;
                  final fileType = fileName.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'image/jpeg';
                  final worker = await ApiService.getCurrentWorker();
                  await ApiService.uploadPaymentProof(
                    customerId: widget.customerId,
                    workerId: worker?['id'] ?? 0,
                    fileData: base64Data,
                    fileName: fileName,
                    fileType: fileType,
                    invoiceId: invoice?['invoiceNumber']?.toString() ?? invoice?['id']?.toString(),
                    amount: amountController.text,
                    paymentMethod: selectedMethod,
                    notes: notesController.text,
                  );
                  Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment proof uploaded!'), backgroundColor: Colors.green));
                } catch (e) {
                  setDialogState(() => uploading = false);
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red));
                }
              },
              child: uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPaymentReminder(Map<String, dynamic> invoice) async {
    final invoiceId = (invoice['invoiceNumber'] ?? invoice['id'] ?? '').toString();
    final amount = (invoice['balance'] ?? invoice['total'] ?? '0').toString();
    final dueDate = (invoice['dueDate'] ?? invoice['due_date'] ?? '').toString();

    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Send Payment Reminder', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Send a reminder for invoice $invoiceId (N$amount)?', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'email'), child: const Text('Send Email')),
        ],
      ),
    );
    if (method == null) return;

    try {
      await ApiService.sendPaymentReminder(customerId: widget.customerId, invoiceId: invoiceId, amount: amount, dueDate: dueDate, method: method);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder sent!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _customer?['name']?.toString() ?? widget.customerName ?? 'Customer';
    final hasGps = _customer != null && (_customer!['latitude'] != null || _customer!['lat'] != null);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('Customer Details', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
        actions: [
          if (hasGps)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ElevatedButton.icon(
                onPressed: _navigateToCustomer,
                icon: const Icon(Icons.navigation, size: 16),
                label: const Text('Navigate'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), textStyle: const TextStyle(fontSize: 12)),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary), onPressed: _loadData),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Info'),
            const Tab(text: 'Statement'),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Invoices'),
              if (_invoices.isNotEmpty) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(8)), child: Text('${_invoices.length}', style: const TextStyle(color: Colors.white, fontSize: 10)))],
            ])),
            const Tab(text: 'Payments'),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Compliance'),
              if (_violations.isNotEmpty || _notices.isNotEmpty) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppTheme.dangerColor, borderRadius: BorderRadius.circular(8)), child: Text('${_violations.length + _notices.length}', style: const TextStyle(color: Colors.white, fontSize: 10)))],
            ])),
            const Tab(text: 'Notes', icon: Icon(Icons.notes_outlined, size: 16)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [_buildInfoTab(), _buildStatementTab(), _buildInvoicesTab(), _buildPaymentsTab(), _buildComplianceTab(), _buildNotesTab()],
                ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final role = context.watch<AuthProvider>().workerRole ?? '';
          final isSupervisor = role == 'supervisor';
          if (isSupervisor) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportViolationScreen(customerId: widget.customerId, routeId: widget.routeId, customerName: name))),
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Report Violation'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor, minimumSize: const Size(double.infinity, 48)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoTab() {
    if (_customer == null) return const SizedBox();
    final c = _customer!;
    final lat = c['latitude'] ?? c['lat'];
    final lng = c['longitude'] ?? c['lng'] ?? c['lon'];
    final linkageType = _linkageStatus?['type']?.toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _InfoCard(children: [
            Row(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.person_rounded, color: AppTheme.primaryColor, size: 28)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['name']?.toString() ?? widget.customerName ?? 'N/A', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
                Text('MAF: ${c['customermaf'] ?? c['id'] ?? 'N/A'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                if (linkageType != null)
                  Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: (linkageType == 'MAIN' ? AppTheme.accentColor : AppTheme.warningColor).withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(linkageType, style: TextStyle(color: linkageType == 'MAIN' ? AppTheme.accentColor : AppTheme.warningColor, fontSize: 11, fontWeight: FontWeight.w600))),
              ])),
            ]),
          ]),
          const SizedBox(height: 12),
          _InfoCard(title: 'Contact Information', icon: Icons.location_on_outlined, children: [
            if (c['phone'] != null) _InfoRow(Icons.phone_outlined, 'Phone', c['phone'].toString()),
            if (c['email'] != null) _InfoRow(Icons.email_outlined, 'Email', c['email'].toString()),
            if (c['address'] != null || c['buildingAddress'] != null) _InfoRow(Icons.location_on_outlined, 'Address', (c['address'] ?? c['buildingAddress']).toString()),
            if (lat != null && lng != null) _InfoRow(Icons.gps_fixed, 'Coordinates', '$lat, $lng'),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _showLinkBuildingIdDialog,
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Link Building ID'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryColor, side: const BorderSide(color: AppTheme.primaryColor)),
            )),
          ]),
          const SizedBox(height: 12),
          _InfoCard(title: 'Account Details', children: [
            if (c['customerType'] != null) _InfoRow(Icons.category_outlined, 'Customer Type', c['customerType'].toString()),
            if (c['serviceType'] != null) _InfoRow(Icons.miscellaneous_services_outlined, 'Service Type', c['serviceType'].toString()),
            if (c['priority'] != null) _InfoRow(Icons.flag_outlined, 'Priority', c['priority'].toString()),
            if (c['routeAssignmentStatus'] != null) _InfoRow(Icons.circle, 'Status', c['routeAssignmentStatus'].toString(), valueColor: AppColors.statusColor(c['routeAssignmentStatus'].toString())),
            if (c['zohoContactId'] != null) _InfoRow(Icons.cloud_outlined, 'Zoho ID', c['zohoContactId'].toString()),
          ]),
        ],
      ),
    );
  }

  Widget _buildStatementTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _InfoCard(children: [
        Row(children: [
          const Icon(Icons.receipt_long, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 8),
          const Text('Zoho Books Statement', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 16),
        if (_statement == null || _statement!.isEmpty)
          const _EmptyState(icon: Icons.receipt_long_outlined, message: 'No statement available', color: AppTheme.textSecondary)
        else ...[
          _StatRow('Total', 'N${_statement!['total'] ?? _statement!['totalAmount'] ?? '0.00'}', bold: true),
          const Divider(color: AppTheme.borderColor, height: 16),
          _StatRow('Balance', 'N${_statement!['balance'] ?? _statement!['outstandingBalance'] ?? '0.00'}', valueColor: AppTheme.dangerColor, bold: true),
          if (_statement!['lastPaymentDate'] != null) ...[const SizedBox(height: 8), _StatRow('Last Payment', _statement!['lastPaymentDate'].toString())],
          if (_statement!['lastPaymentAmount'] != null) _StatRow('Last Amount', 'N${_statement!['lastPaymentAmount']}'),
        ],
      ]),
    );
  }

  Widget _buildInvoicesTab() {
    final filtered = _invoiceSearch.isEmpty ? _invoices : _invoices.where((inv) {
      final q = _invoiceSearch.toLowerCase();
      return (inv['invoiceNumber'] ?? inv['id'] ?? '').toString().toLowerCase().contains(q) ||
             (inv['status'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Search invoices...', prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary), contentPadding: EdgeInsets.symmetric(vertical: 10)),
          onChanged: (v) => setState(() => _invoiceSearch = v),
        ),
      ),
      Expanded(child: filtered.isEmpty
          ? const Center(child: _EmptyState(icon: Icons.receipt_outlined, message: 'No invoices found', color: AppTheme.textSecondary))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final inv = filtered[i] as Map<String, dynamic>;
                final invoiceNum = (inv['invoiceNumber'] ?? inv['id'] ?? 'N/A').toString();
                final status = (inv['status'] ?? 'unknown').toString();
                final amount = (inv['total'] ?? inv['amount'] ?? '0').toString();
                final balance = (inv['balance'] ?? '0').toString();
                final date = inv['date']?.toString() ?? inv['invoiceDate']?.toString();
                final dueDate = inv['dueDate']?.toString() ?? inv['due_date']?.toString();
                final isOverdue = status.toLowerCase() == 'overdue';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isOverdue ? AppTheme.dangerColor.withOpacity(0.4) : AppTheme.borderColor),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(invoiceNum, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                        if (date != null) Text(date, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        if (dueDate != null) Text('Due: $dueDate', style: TextStyle(color: isOverdue ? AppTheme.dangerColor : AppTheme.textSecondary, fontSize: 11)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('N$amount', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                        if (balance != '0' && balance != amount) Text('Bal: N$balance', style: const TextStyle(color: AppTheme.dangerColor, fontSize: 12)),
                        Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(status, style: TextStyle(color: AppColors.statusColor(status), fontSize: 11))),
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => _showUploadPaymentProofDialog(inv),
                        icon: const Icon(Icons.upload_file, size: 14),
                        label: const Text('Upload Proof', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentColor, side: BorderSide(color: AppTheme.accentColor.withOpacity(0.5)), padding: const EdgeInsets.symmetric(vertical: 6)),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => _sendPaymentReminder(inv),
                        icon: const Icon(Icons.send, size: 14),
                        label: const Text('Reminder', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.warningColor, side: BorderSide(color: AppTheme.warningColor.withOpacity(0.5)), padding: const EdgeInsets.symmetric(vertical: 6)),
                      )),
                    ]),
                  ]),
                );
              },
            )),
    ]);
  }

  Widget _buildPaymentsTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(
          onPressed: () => _showUploadPaymentProofDialog(null),
          icon: const Icon(Icons.upload_file),
          label: const Text('Upload Payment Proof'),
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryColor, side: const BorderSide(color: AppTheme.primaryColor), minimumSize: const Size(double.infinity, 44)),
        ),
      ),
      Expanded(child: _payments.isEmpty
          ? const Center(child: _EmptyState(icon: Icons.payment_outlined, message: 'No payment records found', color: AppTheme.textSecondary))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: _payments.length,
              itemBuilder: (_, i) {
                final p = _payments[i] as Map<String, dynamic>;
                final amount = (p['amount'] ?? p['paymentAmount'] ?? '0').toString();
                final date = (p['date'] ?? p['paymentDate'] ?? '').toString();
                final mode = (p['paymentMode'] ?? p['method'] ?? 'N/A').toString();
                final ref = (p['referenceNumber'] ?? p['reference'] ?? '').toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderColor)),
                  child: Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.check_circle_outline, color: AppTheme.accentColor, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('N$amount', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(date, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text(mode, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ])),
                    if (ref.isNotEmpty)
                      GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: ref)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reference copied'))); },
                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.bgCardLight, borderRadius: BorderRadius.circular(6)),
                          child: Text(ref.length > 12 ? '${ref.substring(0, 12)}...' : ref, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11))),
                      ),
                  ]),
                );
              },
            )),
    ]);
  }

  Widget _buildComplianceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 18), const SizedBox(width: 8), Text('Violations (${_violations.length})', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 10),
        if (_violations.isEmpty) const _EmptyState(icon: Icons.check_circle_outline, message: 'No violations recorded', color: AppTheme.accentColor)
        else ..._violations.map((v) => _ViolationCard(violation: v as Map<String, dynamic>)),
        const SizedBox(height: 20),
        Row(children: [const Icon(Icons.gavel_rounded, color: AppTheme.dangerColor, size: 18), const SizedBox(width: 8), Text('Abatement Notices (${_notices.length})', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 10),
        if (_notices.isEmpty) const _EmptyState(icon: Icons.check_circle_outline, message: 'No abatement notices issued', color: AppTheme.accentColor)
        else ..._notices.map((n) => _NoticeCard(notice: n as Map<String, dynamic>)),
      ]),
    );
  }

  Widget _buildNotesTab() {
    final name = (_customer?['name'] ?? _customer?['customerName'] ?? widget.customerName ?? 'Customer').toString();
    return CustomerNotesScreen(
      customerId: widget.customerId,
      customerName: name,
      routeId: widget.routeId,
    );
  }

  Widget _buildError() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, color: AppTheme.dangerColor, size: 48),
      const SizedBox(height: 16),
      Text(_error!, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('Retry')),
    ])));
  }
}

class _InfoCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final List<Widget> children;
  const _InfoCard({this.title, this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox();
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) ...[
          Row(children: [
            if (icon != null) ...[Icon(icon, color: AppTheme.textSecondary, size: 16), const SizedBox(width: 6)],
            Text(title!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 12),
        ],
        ...children,
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.icon, this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppTheme.textSecondary, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        Text(value, style: TextStyle(color: valueColor ?? AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
      ])),
    ]));
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  const _StatRow(this.label, this.value, {this.valueColor, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      Text(value, style: TextStyle(color: valueColor ?? AppTheme.textPrimary, fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    ]));
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  const _EmptyState({required this.icon, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Column(children: [
      Icon(icon, color: color, size: 36),
      const SizedBox(height: 8),
      Text(message, style: TextStyle(color: color, fontSize: 14)),
    ])));
  }
}

class _ViolationCard extends StatelessWidget {
  final Map<String, dynamic> violation;
  const _ViolationCard({required this.violation});

  @override
  Widget build(BuildContext context) {
    final type = (violation['violationType']?['name'] ?? violation['type'] ?? 'Violation').toString();
    final severity = (violation['severity'] ?? 'medium').toString();
    final date = violation['createdAt']?.toString() ?? violation['date']?.toString() ?? '';
    final description = (violation['description'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.severityColor(severity).withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(type, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.severityColor(severity).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(severity, style: TextStyle(color: AppColors.severityColor(severity), fontSize: 11))),
        ]),
        if (description.isNotEmpty) ...[const SizedBox(height: 4), Text(description, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))],
        if (date.isNotEmpty) ...[const SizedBox(height: 4), Text(date.substring(0, date.length > 10 ? 10 : date.length), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11))],
      ]),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final Map<String, dynamic> notice;
  const _NoticeCard({required this.notice});

  @override
  Widget build(BuildContext context) {
    final title = (notice['title'] ?? notice['type'] ?? 'Notice').toString();
    final status = (notice['status'] ?? 'pending').toString();
    final deadline = notice['deadline']?.toString() ?? notice['dueDate']?.toString() ?? '';
    final description = (notice['description'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: TextStyle(color: AppColors.statusColor(status), fontSize: 11))),
        ]),
        if (description.isNotEmpty) ...[const SizedBox(height: 4), Text(description, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))],
        if (deadline.isNotEmpty) ...[const SizedBox(height: 4), Text('Deadline: ${deadline.substring(0, deadline.length > 10 ? 10 : deadline.length)}', style: const TextStyle(color: AppTheme.warningColor, fontSize: 11))],
      ]),
    );
  }
}

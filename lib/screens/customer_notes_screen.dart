import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

class CustomerNotesScreen extends StatefulWidget {
  final int customerId;
  final String customerName;
  final int? routeId;

  const CustomerNotesScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.routeId,
  });

  @override
  State<CustomerNotesScreen> createState() => _CustomerNotesScreenState();
}

class _CustomerNotesScreenState extends State<CustomerNotesScreen> {
  List<dynamic> _notes = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _noteController = TextEditingController();
  File? _selectedPhoto;
  bool _submitting = false;
  int? _replyingToId;
  final TextEditingController _replyController = TextEditingController();
  String? _workerName;
  int? _workerId;

  @override
  void initState() {
    super.initState();
    _loadWorkerInfo();
    _loadNotes();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkerInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _workerId = prefs.getInt(ApiService.workerIdKey);
      _workerName = prefs.getString(ApiService.workerNameKey);
    });
  }

  Future<void> _loadNotes() async {
    setState(() { _loading = true; _error = null; });
    try {
      final notes = await ApiService.getCustomerNotes(widget.customerId);
      setState(() { _notes = notes; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() => _selectedPhoto = File(picked.path));
    }
  }

  Future<void> _submitNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty && _selectedPhoto == null) return;
    setState(() => _submitting = true);
    try {
      String? photoUrl;
      if (_selectedPhoto != null) {
        // Convert photo to base64 for upload
        final bytes = await _selectedPhoto!.readAsBytes();
        final base64Data = base64Encode(bytes);
        final fileName = _selectedPhoto!.path.split('/').last;
        // Upload via payments.uploadPaymentProof reusing the S3 upload
        final result = await ApiService.uploadPaymentProof(
          customerId: widget.customerId,
          workerId: _workerId ?? 0,
          fileData: base64Data,
          fileName: fileName,
          fileType: 'image/jpeg',
          notes: 'Visit note photo',
        );
        photoUrl = result['fileUrl'] as String?;
      }
      await ApiService.addCustomerNote(
        customerId: widget.customerId,
        routeId: widget.routeId,
        workerId: _workerId,
        authorType: 'worker',
        authorName: _workerName,
        noteText: text.isNotEmpty ? text : null,
        photoUrl: photoUrl,
        visitDate: DateTime.now().toIso8601String().split('T').first,
      );
      _noteController.clear();
      setState(() { _selectedPhoto = null; _submitting = false; });
      await _loadNotes();
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add note: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitReply(int parentNoteId) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ApiService.addCustomerNote(
        customerId: widget.customerId,
        routeId: widget.routeId,
        workerId: _workerId,
        authorType: 'worker',
        authorName: _workerName,
        noteText: text,
        parentNoteId: parentNoteId,
        visitDate: DateTime.now().toIso8601String().split('T').first,
      );
      _replyController.clear();
      setState(() { _replyingToId = null; _submitting = false; });
      await _loadNotes();
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reply: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteNote(int id) async {
    try {
      await ApiService.deleteCustomerNote(id);
      await _loadNotes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Visit Notes', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.customerName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: _loadNotes,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Add Note Input ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Add a visit note...',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.bgDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primaryColor),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 8),
                if (_selectedPhoto != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_selectedPhoto!, height: 100, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedPhoto = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_camera, size: 16),
                      label: const Text('Photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitNote,
                      icon: _submitting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 16),
                      label: const Text('Post Note'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Notes List ──────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 40),
                            const SizedBox(height: 8),
                            Text(_error!, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(onPressed: _loadNotes, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _notes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notes_outlined, color: AppTheme.textSecondary.withOpacity(0.4), size: 56),
                                const SizedBox(height: 12),
                                const Text('No visit notes yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                                const SizedBox(height: 4),
                                const Text('Add the first note above', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _notes.length,
                            itemBuilder: (context, index) {
                              final note = _notes[index];
                              return _buildNoteCard(note);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(Map<String, dynamic> note) {
    final isAdmin = note['authorType'] == 'admin';
    final replies = (note['replies'] as List<dynamic>?) ?? [];
    final isReplying = _replyingToId == note['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Note header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isAdmin ? Colors.blue.withOpacity(0.15) : Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isAdmin ? 'Admin' : 'Field Worker',
                    style: TextStyle(
                      color: isAdmin ? Colors.blue[300] : Colors.green[300],
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note['authorName'] ?? 'Unknown',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatDate(note['visitDate'] ?? note['createdAt']),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
                if (!isAdmin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    onPressed: () => _confirmDelete(note['id']),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
              ],
            ),
          ),

          // Note text
          if (note['noteText'] != null && (note['noteText'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(note['noteText'], style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
            ),

          // Note photo
          if (note['photoUrl'] != null && (note['photoUrl'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  note['photoUrl'],
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    color: AppTheme.bgDark,
                    child: const Center(child: Icon(Icons.broken_image, color: AppTheme.textSecondary)),
                  ),
                ),
              ),
            ),

          // Replies
          if (replies.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: isAdmin ? Colors.blue.withOpacity(0.4) : Colors.green.withOpacity(0.4), width: 2)),
              ),
              child: Column(
                children: replies.map<Widget>((reply) => _buildReplyCard(reply)).toList(),
              ),
            ),

          // Reply input
          if (isReplying)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      autofocus: true,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Write a reply...',
                        hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.bgDark,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primaryColor)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppTheme.primaryColor, size: 20),
                    onPressed: _submitting ? null : () => _submitReply(note['id']),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                    onPressed: () => setState(() { _replyingToId = null; _replyController.clear(); }),
                  ),
                ],
              ),
            ),

          // Reply button
          if (!isReplying)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: GestureDetector(
                onTap: () => setState(() { _replyingToId = note['id']; _replyController.clear(); }),
                child: const Text('Reply', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyCard(Map<String, dynamic> reply) {
    final isAdmin = reply['authorType'] == 'admin';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isAdmin ? Colors.blue.withOpacity(0.15) : Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isAdmin ? 'Admin' : 'Worker',
                  style: TextStyle(color: isAdmin ? Colors.blue[300] : Colors.green[300], fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(reply['authorName'] ?? '', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis),
              ),
              Text(_formatDate(reply['visitDate'] ?? reply['createdAt']), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          if (reply['noteText'] != null)
            Text(reply['noteText'], style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString());
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return date.toString();
    }
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Note', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Are you sure you want to delete this note?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(context); _deleteNote(id); },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

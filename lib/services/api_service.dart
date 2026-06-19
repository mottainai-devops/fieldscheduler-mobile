import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/auth_provider.dart';

/// Thrown by the 401 interceptor so callers can distinguish session expiry
/// from other errors.
class SessionExpiredException implements Exception {
  final String message;
  const SessionExpiredException([this.message = 'Session expired']);
  @override
  String toString() => message;
}

class ApiService {
  static const String baseUrl = 'https://app.fieldscheduler.net/api/trpc';
  static const String sessionKey = 'worker_session';
  static const String workerIdKey = 'worker_id';
  static const String workerNameKey = 'worker_name';

  static const _secureStorage = FlutterSecureStorage();

  // ─── Navigator key for 401 redirect ─────────────────────────────────────────
  // Callers must assign this in main() so the interceptor can navigate without
  // a BuildContext.
  static GlobalKey<NavigatorState>? navigatorKey;

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// Build headers for a request.
  ///
  /// Area B (D1): surveyToken is read LIVE from flutter_secure_storage at
  /// request time, not from a cached field. This ensures that after a
  /// re-login the very next request carries the fresh token.
  ///
  /// Branching:
  ///   - Supervisor path: surveyToken present → Authorization: Bearer <token>
  ///   - Field manager path: Cookie session present → Cookie: <session>
  static Future<Map<String, String>> _getHeaders() async {
    // D1: read token live from secure storage on every request
    final surveyToken = await _secureStorage.read(key: 'workerSurveyToken');
    if (surveyToken != null && surveyToken.isNotEmpty) {
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $surveyToken',
      };
    }
    // Field manager path — Cookie session
    final prefs = await SharedPreferences.getInstance();
    final session = prefs.getString(sessionKey) ?? '';
    return {
      'Content-Type': 'application/json',
      if (session.isNotEmpty) 'Cookie': session,
    };
  }

  /// Central 401 interceptor.
  ///
  /// B6: On 401:
  ///   1. Clears ONLY the surveyToken from secure storage. SharedPreferences
  ///      (sessionKind, assignedLots, pending queue) is intentionally preserved
  ///      so Tranche 2 offline queue state survives.
  ///   2. Calls clearIdentityOnly() on AuthProvider so in-memory supervisor
  ///      state is cleared (sessionKind still says 'supervisor' until this runs).
  ///   3. Navigates to /supervisor-login via go_router using the shared
  ///      navigatorKey. Uses context.go() which is go_router-compatible.
  static Future<void> _handle401() async {
    await _secureStorage.delete(key: 'workerSurveyToken');
    // B6: clear in-memory supervisor state via AuthProvider
    final ctx = navigatorKey?.currentContext;
    if (ctx != null) {
      try {
        ctx.read<AuthProvider>().clearIdentityOnly();
      } catch (_) {}
      // B6: navigate to supervisor-login using go_router-compatible go()
      ctx.go('/supervisor-login');
    }
    throw const SessionExpiredException('Session expired, please sign in again');
  }

  static Future<dynamic> _get(String procedure, Map<String, dynamic> input) async {
    final inputJson = Uri.encodeComponent(jsonEncode({'json': input}));
    final url = Uri.parse('$baseUrl/$procedure?input=$inputJson');
    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 401) await _handle401();
    return _handleResponse(response);
  }

  static Future<dynamic> _post(String procedure, Map<String, dynamic> input) async {
    final url = Uri.parse('$baseUrl/$procedure');
    final headers = await _getHeaders();
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'json': input}),
    );
    if (response.statusCode == 401) await _handle401();
    return _handleResponse(response);
  }

  static dynamic _handleResponse(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is Map && body.containsKey('result')) {
        return body['result']['data']['json'];
      }
      return body;
    } else {
      final error = body['error']?['json']?['message'] ?? 'Unknown error';
      throw Exception(error);
    }
  }

  // ─── Auth ────────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getAllWorkers() async {
    return await _get('workerAuth.getAllWorkers', {});
  }

  static Future<Map<String, dynamic>> supervisorLogin({
    required String email,
    required String password, // already base64-encoded by caller
  }) async {
    // Uses supervisorLogin (mutation) — returns {surveyToken, worker, assignedLots}
    return await _post('workerAuth.supervisorLogin', {
      'email': email,
      'password': password,
    });
  }

  static Future<Map<String, dynamic>> loginWithPin(int workerId, String pin) async {
    // Uses verifyPin (query) — accepts workerId + pin, returns {success, worker}
    final result = await _get('workerAuth.verifyPin', {
      'workerId': workerId,
      'pin': pin,
    });
    final data = result as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'Invalid PIN');
    }
    return data;
  }

  static Future<void> saveSession(String cookie, int workerId, String workerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sessionKey, cookie);
    await prefs.setInt(workerIdKey, workerId);
    await prefs.setString(workerNameKey, workerName);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(sessionKey);
    await prefs.remove(workerIdKey);
    await prefs.remove(workerNameKey);
  }

  static Future<Map<String, dynamic>?> getCurrentWorker() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt(workerIdKey);
    final workerName = prefs.getString(workerNameKey);
    if (workerId == null) return null;
    return {'id': workerId, 'name': workerName};
  }

  static Future<Map<String, dynamic>> getMe() async {
    return await _get('workerAuth.me', {});
  }

  /// Fetch the enriched assigned-lots list for the current supervisor session.
  /// Returns a list of lot objects with paytWebhook, monthlyWebhook, lotId, lotNumber.
  static Future<List<dynamic>> getAssignedLots(String surveyToken) async {
    final result = await _get('workerAuth.getAssignedLots', {'surveyToken': surveyToken});
    if (result is List) return result;
    if (result is Map && result.containsKey('lots')) return result['lots'] as List;
    return [];
  }

  static Future<void> logout() async {
    try {
      await _post('workerAuth.logout', {});
    } catch (_) {}
    await clearSession();
    // Also clear the supervisor token on explicit logout
    await _secureStorage.delete(key: 'workerSurveyToken');
  }

  // ─── Routes ──────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getRoutesByWorkerId(int workerId) async {
    return await _get('workerAuth.getRoutesByWorkerId', {'workerId': workerId});
  }

  static Future<Map<String, dynamic>> getRouteById(int routeId) async {
    return await _get('workerAuth.getRouteById', {'routeId': routeId});
  }

  static Future<List<dynamic>> getRouteCustomers(int routeId) async {
    return await _get('workerAuth.getRouteCustomers', {'routeId': routeId});
  }

  /// Mark a single customer stop as completed
  static Future<void> markCustomerComplete(int routeId, int customerId) async {
    await _post('workerAuth.markCustomerComplete', {
      'routeId': routeId,
      'customerId': customerId,
    });
  }

  /// Undo a customer stop completion
  static Future<void> markCustomerIncomplete(int routeId, int customerId) async {
    await _post('workerAuth.markCustomerIncomplete', {
      'routeId': routeId,
      'customerId': customerId,
    });
  }

  /// Complete an entire route (sets status to 'completed')
  static Future<Map<String, dynamic>> completeRoute(int routeId) async {
    return await _post('workerAuth.completeRoute', {'routeId': routeId});
  }

  /// Start a route (sets status to 'in_progress')
  static Future<Map<String, dynamic>> startRoute(int routeId) async {
    return await _post('workerAuth.startRoute', {'routeId': routeId});
  }

  // ─── Customers ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getCustomers({String? search}) async {
    return await _get('workerAuth.getCustomers', {
      if (search != null && search.isNotEmpty) 'search': search,
    });
  }

  static Future<Map<String, dynamic>> getCustomerById(int customerId) async {
    return await _get('workerAuth.getCustomerById', {'customerId': customerId});
  }

  static Future<List<dynamic>> getCustomerInvoices(int customerId) async {
    return await _get('workerAuth.getCustomerInvoices', {'customerId': customerId});
  }

  static Future<List<dynamic>> getCustomerInvoicesByZohoId(String zohoContactId) async {
    return await _get('workerAuth.getCustomerInvoices', {'zohoContactId': zohoContactId});
  }

  static Future<Map<String, dynamic>> getCustomerStatement(int customerId) async {
    return await _get('workerAuth.getCustomerStatement', {'customerId': customerId});
  }

  /// Get Zoho Books statement by zohoContactId
  static Future<Map<String, dynamic>?> getCustomerStatementByZohoId(String zohoContactId) async {
    try {
      final result = await _get('workerAuth.getCustomerStatement', {'zohoContactId': zohoContactId});
      if (result is Map<String, dynamic>) return result;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> getCustomerPaymentStatus(int customerId) async {
    return await _get('workerAuth.getCustomerPaymentStatus', {'customerId': customerId});
  }

  /// Get Zoho Books payment history by zohoContactId
  static Future<List<dynamic>> getCustomerPayments(String zohoContactId) async {
    return await _get('workerAuth.getCustomerPayments', {'zohoContactId': zohoContactId});
  }

  static Future<Map<String, dynamic>> getCustomerLinkageStatus(int customerId) async {
    return await _get('workerAuth.getCustomerLinkageStatus', {'customerId': customerId});
  }

  /// Submit a building ID linkage request
  static Future<void> createLinkageRequest({
    required int mainCustomerId,
    required int annexCustomerId,
    required int requestedBy,
    String? notes,
  }) async {
    await _post('workerAuth.createLinkageRequest', {
      'mainCustomerId': mainCustomerId,
      'annexCustomerId': annexCustomerId,
      'requestedBy': requestedBy,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  // ─── Compliance ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getViolationTypes() async {
    return await _get('workerAuth.getAllViolationTypes', {});
  }

  static Future<List<dynamic>> getViolationsByCustomer(int customerId) async {
    return await _get('workerAuth.getViolationsByCustomer', {'customerId': customerId});
  }

  static Future<List<dynamic>> getAbatementNoticesByCustomer(int customerId) async {
    return await _get('workerAuth.getAbatementNoticesByCustomer', {'customerId': customerId});
  }

  static Future<Map<String, dynamic>> reportViolation({
    required int customerId,
    required int routeId,
    required int violationTypeId,
    required String description,
    required String severity,
  }) async {
    return await _post('compliance.createViolation', {
      'customerId': customerId,
      'routeId': routeId,
      'violationTypeId': violationTypeId,
      'description': description,
      'severity': severity,
    });
  }

  // ─── Payments ────────────────────────────────────────────────────────────────

  /// Upload payment proof (base64-encoded file)
  static Future<Map<String, dynamic>> uploadPaymentProof({
    required int customerId,
    required int workerId,
    required String fileData, // base64
    required String fileName,
    required String fileType,
    String? invoiceId,
    String? notes,
    String? amount,
    String? paymentMethod,
  }) async {
    return await _post('payments.uploadPaymentProof', {
      'customerId': customerId,
      'workerId': workerId,
      'fileData': fileData,
      'fileName': fileName,
      'fileType': fileType,
      if (invoiceId != null) 'invoiceId': invoiceId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (amount != null && amount.isNotEmpty) 'amount': amount,
      if (paymentMethod != null && paymentMethod.isNotEmpty) 'paymentMethod': paymentMethod,
    });
  }

  /// Send a payment reminder for an overdue invoice
  static Future<Map<String, dynamic>> sendPaymentReminder({
    required int customerId,
    required String invoiceId,
    required String amount,
    required String dueDate,
    String method = 'email',
  }) async {
    return await _post('payments.sendPaymentReminder', {
      'customerId': customerId,
      'invoiceId': invoiceId,
      'amount': amount,
      'dueDate': dueDate,
      'method': method,
    });
  }

  /// Get payment evidence records for a customer
  static Future<List<dynamic>> getPaymentEvidence(int customerId) async {
    return await _get('payments.getPaymentEvidence', {'customerId': customerId});
  }

  // ─── Route Optimization ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> optimizeRoute({
    required List<int> customerIds,
    required double startingLatitude,
    required double startingLongitude,
  }) async {
    try {
      final result = await ApiService._post('arcgis.calculateRoute', {
        'stops': <Map<String, dynamic>>[],
        'customerIds': customerIds,
        'startingLatitude': startingLatitude,
        'startingLongitude': startingLongitude,
      });
      if (result is Map<String, dynamic>) return result;
      return null;
    } catch (e) {
      throw Exception('Route optimization failed: $e');
    }
  }

  // ─── Notifications ───────────────────────────────────────────────────────────

  static Future<List<dynamic>> getWorkerNotifications(int workerId) async {
    return await _get('workerNotifications.getWorkerNotifications', {'workerId': workerId});
  }

  static Future<int> getUnreadNotificationCount(int workerId) async {
    final result = await _get('workerNotifications.getUnreadCount', {'workerId': workerId});
    if (result is Map) return result['count'] ?? 0;
    return 0;
  }

  static Future<void> markNotificationAsRead(int notificationId, int workerId) async {
    await _post('workerNotifications.markAsRead', {'id': notificationId, 'workerId': workerId});
  }

  static Future<void> markAllNotificationsAsRead(int workerId) async {
    await _post('workerNotifications.markAllAsRead', {'workerId': workerId});
  }

  // ─── Customer Visit Notes ─────────────────────────────────────────────────────

  static Future<List<dynamic>> getCustomerNotes(int customerId) async {
    return await _get('workerAuth.getCustomerNotes', {'customerId': customerId});
  }

  static Future<void> addCustomerNote({
    required int customerId,
    int? routeId,
    int? workerId,
    String authorType = 'worker',
    String? authorName,
    String? noteText,
    String? photoUrl,
    String? visitDate,
    int? parentNoteId,
  }) async {
    await _post('workerAuth.addCustomerNote', {
      'customerId': customerId,
      if (routeId != null) 'routeId': routeId,
      if (workerId != null) 'workerId': workerId,
      'authorType': authorType,
      if (authorName != null) 'authorName': authorName,
      if (noteText != null) 'noteText': noteText,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (visitDate != null) 'visitDate': visitDate,
      if (parentNoteId != null) 'parentNoteId': parentNoteId,
    });
  }

  static Future<void> deleteCustomerNote(int id) async {
    await _post('workerAuth.deleteCustomerNote', {'id': id});
  }

  // ─── Pickup Submission ───────────────────────────────────────────────────────

  /// Mark a customer as picked (sets pickedAt timestamp) in the fieldscheduler DB
  static Future<void> markCustomerPicked(int routeId, int customerId) async {
    await _post('workerAuth.markCustomerPicked', {
      'routeId': routeId,
      'customerId': customerId,
    });
  }
}

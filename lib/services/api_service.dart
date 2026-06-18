import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://app.fieldscheduler.net/api/trpc';
  static const String sessionKey = 'worker_session';
  static const String workerIdKey = 'worker_id';
  static const String workerNameKey = 'worker_name';

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final session = prefs.getString(sessionKey) ?? '';
    return {
      'Content-Type': 'application/json',
      if (session.isNotEmpty) 'Cookie': session,
    };
  }

  static Future<dynamic> _get(String procedure, Map<String, dynamic> input) async {
    final inputJson = Uri.encodeComponent(jsonEncode({'json': input}));
    final url = Uri.parse('$baseUrl/$procedure?input=$inputJson');
    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);
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

  static Future<Map<String, dynamic>> loginWithPin(int workerId, String pin) async {
    final result = await _post('workerAuth.login', {
      'workerId': workerId,
      'pin': pin,
    });
    return result as Map<String, dynamic>;
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

  static Future<void> logout() async {
    try {
      await _post('workerAuth.logout', {});
    } catch (_) {}
    await clearSession();
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
}

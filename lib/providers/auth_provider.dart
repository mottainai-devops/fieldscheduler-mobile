import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session discriminator values — mirrors sessionKind in SharedPreferences.
enum SessionKind { fieldManager, supervisor, none }

class AuthProvider extends ChangeNotifier {
  int? _workerId;
  String? _workerName;
  String? _workerRole;
  String? _workerEmail;
  String? _companyId;
  String? _companyName;
  SessionKind _sessionKind = SessionKind.none;

  int? get workerId => _workerId;
  String? get workerName => _workerName;
  String? get workerRole => _workerRole;
  String? get workerEmail => _workerEmail;
  String? get companyId => _companyId;
  String? get companyName => _companyName;
  SessionKind get sessionKind => _sessionKind;

  bool get isLoggedIn => _workerId != null;
  bool get isSupervisor => _sessionKind == SessionKind.supervisor;

  AuthProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('worker_id');
    if (id != null) {
      _workerId = id;
      _workerName = prefs.getString('worker_name');
      _workerRole = prefs.getString('worker_role');
      _workerEmail = prefs.getString('worker_email');
      _companyId = prefs.getString('companyId');
      _companyName = prefs.getString('companyName');
      final kindStr = prefs.getString('sessionKind') ?? 'fieldManager';
      _sessionKind = kindStr == 'supervisor'
          ? SessionKind.supervisor
          : SessionKind.fieldManager;
      notifyListeners();
    }
  }

  /// PIN flow — field manager login (unchanged).
  Future<bool> selectWorker(Map<String, dynamic> worker) async {
    _workerId = worker['id'] as int?;
    _workerName = worker['name'] as String?;
    _workerRole = worker['role'] as String?;
    _workerEmail = null;
    _companyId = null;
    _companyName = null;
    _sessionKind = SessionKind.fieldManager;

    final prefs = await SharedPreferences.getInstance();
    if (_workerId != null) prefs.setInt('worker_id', _workerId!);
    if (_workerName != null) prefs.setString('worker_name', _workerName!);
    if (_workerRole != null) prefs.setString('worker_role', _workerRole!);
    prefs.setString('sessionKind', 'fieldManager');
    notifyListeners();
    return true;
  }

  /// Supervisor login — called after supervisorLogin tRPC response is validated.
  /// The token and lot cache are written by SupervisorLoginScreen directly;
  /// this method only updates the in-memory AuthProvider state and the
  /// SharedPreferences keys that AuthProvider owns.
  Future<void> loginAsSupervisor(Map<String, dynamic> worker) async {
    _workerId = (worker['id'] as num?)?.toInt();
    _workerName = worker['name'] as String?;
    _workerRole = worker['surveyAppRole'] as String? ?? worker['role'] as String?;
    _workerEmail = worker['email'] as String?;
    _companyId = worker['companyId']?.toString();
    _companyName = worker['companyName'] as String?;
    _sessionKind = SessionKind.supervisor;

    final prefs = await SharedPreferences.getInstance();
    if (_workerId != null) prefs.setInt('worker_id', _workerId!);
    if (_workerName != null) prefs.setString('worker_name', _workerName!);
    if (_workerRole != null) prefs.setString('worker_role', _workerRole!);
    if (_workerEmail != null) prefs.setString('worker_email', _workerEmail!);
    if (_companyId != null) prefs.setString('companyId', _companyId!);
    if (_companyName != null) prefs.setString('companyName', _companyName!);
    prefs.setString('sessionKind', 'supervisor');
    notifyListeners();
  }

  /// Clear session.
  /// B6: logout does NOT clear SharedPreferences wholesale — it only clears
  /// identity/token keys so future-tranche queue state is preserved.
  /// Call this on explicit user logout only; the 401 interceptor calls
  /// clearTokenOnly() instead.
  Future<void> logout() async {
    _workerId = null;
    _workerName = null;
    _workerRole = null;
    _workerEmail = null;
    _companyId = null;
    _companyName = null;
    _sessionKind = SessionKind.none;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }

  /// B6: 401 interceptor path — clear identity/token but preserve queue state.
  Future<void> clearIdentityOnly() async {
    _workerId = null;
    _workerName = null;
    _workerRole = null;
    _workerEmail = null;
    _companyId = null;
    _companyName = null;
    _sessionKind = SessionKind.none;
    final prefs = await SharedPreferences.getInstance();
    // Remove only identity keys; leave sessionKind, assignedLots, pending queue, etc.
    await prefs.remove('worker_id');
    await prefs.remove('worker_name');
    await prefs.remove('worker_role');
    await prefs.remove('worker_email');
    await prefs.remove('companyId');
    await prefs.remove('companyName');
    await prefs.remove('fieldworkerId');
    await prefs.remove('tokenIssuedAt');
    // sessionKind and assignedLots intentionally retained for Tranche 2 queue
    notifyListeners();
  }
}

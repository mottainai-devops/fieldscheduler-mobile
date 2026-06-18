import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  int? _workerId;
  String? _workerName;
  String? _workerRole;

  int? get workerId => _workerId;
  String? get workerName => _workerName;
  String? get workerRole => _workerRole;
  bool get isLoggedIn => _workerId != null;

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
      notifyListeners();
    }
  }

  Future<bool> selectWorker(Map<String, dynamic> worker) async {
    _workerId = worker['id'] as int?;
    _workerName = worker['name'] as String?;
    _workerRole = worker['role'] as String?;
    final prefs = await SharedPreferences.getInstance();
    if (_workerId != null) prefs.setInt('worker_id', _workerId!);
    if (_workerName != null) prefs.setString('worker_name', _workerName!);
    if (_workerRole != null) prefs.setString('worker_role', _workerRole!);
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _workerId = null;
    _workerName = null;
    _workerRole = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }
}

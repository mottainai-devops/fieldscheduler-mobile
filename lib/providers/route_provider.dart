import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RouteProvider extends ChangeNotifier {
  List<dynamic> _routes = [];
  bool _isLoading = false;
  String? _error;

  List<dynamic> get routes => _routes;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadRoutes(int workerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _routes = await ApiService.getRoutesByWorkerId(workerId);
    } catch (e) {
      _error = 'Failed to load routes. Please try again.';
    }
    _isLoading = false;
    notifyListeners();
  }

  void clearRoutes() {
    _routes = [];
    _error = null;
    notifyListeners();
  }
}

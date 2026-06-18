import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationProvider extends ChangeNotifier {
  List<dynamic> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;

  List<dynamic> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  Future<void> loadNotifications(int workerId) async {
    _isLoading = true;
    notifyListeners();
    try {
      _notifications = await ApiService.getWorkerNotifications(workerId);
      _unreadCount = _notifications.where((n) => n['isRead'] == false).length;
    } catch (e) {
      debugPrint('Notification load error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> markAsRead(int notificationId, int workerId) async {
    try {
      await ApiService.markNotificationAsRead(notificationId, workerId);
      final idx = _notifications.indexWhere((n) => n['id'] == notificationId);
      if (idx >= 0) {
        _notifications[idx] = {..._notifications[idx], 'isRead': true};
        _unreadCount = _notifications.where((n) => n['isRead'] == false).length;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Mark read error: $e');
    }
  }

  Future<void> markAllAsRead(int workerId) async {
    try {
      await ApiService.markAllNotificationsAsRead(workerId);
      _notifications = _notifications.map((n) => {...n, 'isRead': true}).toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Mark all read error: $e');
    }
  }
}

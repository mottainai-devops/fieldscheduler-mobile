import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.workerId != null) {
        context.read<NotificationProvider>().loadNotifications(auth.workerId!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifProvider = context.watch<NotificationProvider>();
    final auth = context.read<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (notifProvider.unreadCount > 0)
            TextButton(
              onPressed: () {
                if (auth.workerId != null) {
                  notifProvider.markAllAsRead(auth.workerId!);
                }
              },
              child: const Text('Mark all read', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: notifProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : notifProvider.notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No notifications', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: notifProvider.notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final n = notifProvider.notifications[index] as Map<String, dynamic>;
                    final isRead = n['isRead'] == true;
                    final title = n['title'] as String? ?? 'Notification';
                    final message = n['message'] as String? ?? '';
                    final createdAt = n['createdAt'] as String?;
                    return ListTile(
                      tileColor: isRead ? null : Colors.blue.shade50,
                      leading: CircleAvatar(
                        backgroundColor: isRead ? Colors.grey.shade200 : const Color(0xFF1565C0),
                        child: Icon(Icons.notifications, color: isRead ? Colors.grey : Colors.white, size: 20),
                      ),
                      title: Text(title, style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message),
                          if (createdAt != null)
                            Text(_formatDate(createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                      onTap: () {
                        if (!isRead && auth.workerId != null) {
                          notifProvider.markAsRead(n['id'] as int, auth.workerId!);
                        }
                      },
                    );
                  },
                ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(d);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

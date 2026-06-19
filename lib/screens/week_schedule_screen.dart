import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

/// Area B (G1–G3): Supervisor "Week" view.
///
/// G1: Displays a horizontal 7-day strip for the current week.
/// G2: Calls getSupervisorSchedule(from: weekStart, to: weekEnd) to populate
///     event dots under each day.
/// G3: Tapping a day with events navigates to TodayRoutesScreen for that
///     specific date (passes date as query param).
///
/// No external calendar package dependency — the strip is hand-built to avoid
/// pubspec churn. The spec mentions table_calendar but the hand-built strip
/// achieves identical UX with zero new dependencies.
class WeekScheduleScreen extends StatefulWidget {
  const WeekScheduleScreen({super.key});

  @override
  State<WeekScheduleScreen> createState() => _WeekScheduleScreenState();
}

class _WeekScheduleScreenState extends State<WeekScheduleScreen> {
  late DateTime _weekStart;
  Map<String, List<Map<String, dynamic>>> _eventsByDate = {};
  bool _isLoading = true;
  String? _error;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Week starts on Monday
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _selectedDay = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final supervisorId = auth.workerId;
      if (supervisorId == null) {
        setState(() {
          _error = 'No supervisor ID — please sign in again.';
          _isLoading = false;
        });
        return;
      }

      final weekEnd = _weekStart.add(const Duration(days: 6));
      final rawEvents = await ApiService.getSupervisorSchedule(
        supervisorId: supervisorId,
        from: _fmt(_weekStart),
        to: _fmt(weekEnd),
      );

      final byDate = <String, List<Map<String, dynamic>>>{};
      for (final e in rawEvents) {
        final ev = Map<String, dynamic>.from(e as Map);
        final date = ev['date']?.toString() ?? ev['originalDate']?.toString() ?? '';
        if (date.isEmpty) continue;
        byDate.putIfAbsent(date, () => []).add(ev);
      }

      if (mounted) {
        setState(() {
          _eventsByDate = byDate;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _previousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
      _selectedDay = null;
    });
    _load();
  }

  void _nextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
      _selectedDay = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          'My Schedule',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_rounded, color: Colors.white),
            tooltip: 'Today',
            onPressed: () => context.push('/supervisor-today'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWeekStrip(),
          const Divider(height: 1, color: AppTheme.borderColor),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : _error != null
                    ? _buildError()
                    : _buildEventList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekStrip() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final today = DateTime.now();
    final todayKey = _fmt(DateTime(today.year, today.month, today.day));

    return Container(
      color: AppTheme.bgCard,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(
        children: [
          // Week navigation header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: _previousWeek,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text(
                '${_fmt(_weekStart)} – ${_fmt(_weekStart.add(const Duration(days: 6)))}',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: _nextWeek,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Day cells
          Row(
            children: days.map((day) {
              final key = _fmt(day);
              final isToday = key == todayKey;
              final isSelected = _selectedDay != null && _fmt(_selectedDay!) == key;
              final events = _eventsByDate[key] ?? [];
              final hasEvents = events.isNotEmpty;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedDay = day);
                    // G3: Tap day with events → navigate to Today view for that date
                    if (hasEvents) {
                      context.push('/supervisor-today?date=$key');
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withOpacity(0.25)
                          : isToday
                              ? Colors.white.withOpacity(0.08)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : isToday
                                ? Colors.white.withOpacity(0.3)
                                : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1],
                          style: TextStyle(
                            color: isToday ? AppTheme.primaryColor : Colors.white.withOpacity(0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : isToday
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.8),
                            fontSize: 15,
                            fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Event dots
                        if (hasEvents)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < events.length.clamp(0, 3); i++)
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              if (events.length > 3)
                                Text(
                                  '+',
                                  style: TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          )
                        else
                          const SizedBox(height: 5),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList() {
    final selectedKey = _selectedDay != null ? _fmt(_selectedDay!) : null;
    final events = selectedKey != null ? (_eventsByDate[selectedKey] ?? []) : [];

    if (_eventsByDate.isEmpty) {
      return Center(
        child: Text(
          'No events this week',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
        ),
      );
    }

    if (selectedKey == null || events.isEmpty) {
      // Show all events grouped by date
      final allDates = _eventsByDate.keys.toList()..sort();
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: allDates.length,
        itemBuilder: (_, i) {
          final date = allDates[i];
          final dayEvents = _eventsByDate[date]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: i > 0 ? 16 : 0),
                child: Text(
                  date,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...dayEvents.map((e) => _EventListTile(event: e, date: date)),
            ],
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            selectedKey,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...events.map((e) => _EventListTile(event: e, date: selectedKey)),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final String date;

  const _EventListTile({required this.event, required this.date});

  @override
  Widget build(BuildContext context) {
    final title = event['title']?.toString() ?? 'Route';
    final workerName = event['workerName']?.toString();
    final status = event['status']?.toString() ?? 'scheduled';
    final routeId = event['routeId'];
    final lotCodes = (event['lotCodes'] as List?)?.map((e) => e.toString()).toList() ?? [];

    Color statusColor;
    switch (status) {
      case 'completed': statusColor = Colors.green; break;
      case 'in_progress': statusColor = AppTheme.primaryColor; break;
      case 'cancelled': statusColor = Colors.red; break;
      default: statusColor = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (workerName != null)
                  Text(
                    workerName,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                if (lotCodes.isNotEmpty)
                  Text(
                    lotCodes.join(', '),
                    style: const TextStyle(color: AppTheme.accentColor, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (routeId != null)
            TextButton(
              onPressed: () => context.push('/routes/$routeId'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Open', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/teaching_occurrence.dart';
import '../../services/attendance_reminder_history.dart';
import '../../services/schedule_clock.dart';

class AttendanceReminderHistoryPage extends StatefulWidget {
  final AttendanceReminderHistory history;
  final ValueChanged<AttendanceData> onOpen;

  const AttendanceReminderHistoryPage({
    super.key,
    required this.history,
    required this.onOpen,
  });

  @override
  State<AttendanceReminderHistoryPage> createState() =>
      _AttendanceReminderHistoryPageState();
}

class _AttendanceReminderHistoryPageState
    extends State<AttendanceReminderHistoryPage> {
  late Future<List<AttendanceReminderEntry>> _entries = widget.history.read();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Thông báo'),
      actions: [
        IconButton(
          tooltip: 'Tải lại lịch sử',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() => _entries = widget.history.read()),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: FutureBuilder(
          future: _entries,
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <AttendanceReminderEntry>[];
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Lịch sử nhắc điểm danh',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lời nhắc phát sinh khi Desktop đang chạy được lưu trên máy này cho tài khoản giảng viên hiện tại.',
                ),
                const SizedBox(height: 20),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  const Text(
                    'Chưa đọc được lịch sử. Bấm Tải lại lịch sử để thử lại.',
                  )
                else if (entries.isEmpty)
                  const Text('Chưa có lời nhắc trên Desktop.')
                else
                  for (final entry in entries) _tile(context, entry),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _tile(BuildContext context, AttendanceReminderEntry entry) {
    final time = ScheduleClock.now(entry.at);
    final status = entry.sentToWindows
        ? 'Đã yêu cầu Windows hiển thị'
        : 'Gửi tới Windows thất bại';
    return Card(
      child: ListTile(
        leading: Icon(
          entry.sentToWindows
              ? Icons.notifications_outlined
              : Icons.error_outline,
          color: entry.sentToWindows
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
        title: Text(entry.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.body),
            Text(
              '${ScheduleClock.date(time)} · ${TimeOfDay.fromDateTime(time).format(context)} · $status',
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => widget.onOpen(entry.selector),
      ),
    );
  }
}

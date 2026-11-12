import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/teaching_occurrence.dart';
import '../../repositories/daily_attendance_repository.dart';
import '../../repositories/student_portal_repository.dart';
import '../../services/attendance_local_store.dart';
import '../../services/attendance_reminder_history.dart';
import '../../services/desktop_attendance_reminders.dart';
import '../../services/schedule_clock.dart';
import 'quick_attendance_screen.dart';

class AttendanceDayPanel extends StatefulWidget {
  final DailyAttendanceRepository repository;
  final String owner;
  final AttendanceLocalStore store;
  final StudentPortalRepository? portalRepository;
  final ValueChanged<TeachingOccurrence>? onOpenQr;
  final AttendanceAlerts? alerts;
  final AttendanceReminderHistory? reminderHistory;
  final bool withReminders, compact;
  final DateTime Function()? clock;
  const AttendanceDayPanel({
    super.key,
    required this.repository,
    required this.owner,
    required this.store,
    this.portalRepository,
    this.onOpenQr,
    this.alerts,
    this.reminderHistory,
    this.withReminders = true,
    this.compact = false,
    this.clock,
  });
  @override
  State<AttendanceDayPanel> createState() => _AttendanceDayPanelState();
}

class _AttendanceDayPanelState extends State<AttendanceDayPanel> {
  List<TeachingOccurrence> lessons = [];
  bool busy = false, enabled = false;
  String? error, notificationError;
  String? selectedTerm;
  List<TeachingOccurrence> get visible => lessons
      .where((p) => selectedTerm == null || p.semester == selectedTerm)
      .toList();
  Timer? timer;
  DateTime? serverTime, fetchedAt;
  late final alerts = widget.alerts ?? WindowsAttendanceAlerts();
  late final history =
      widget.reminderHistory ??
      AttendanceReminderHistory(widget.store, widget.owner);
  final cursor = AttendanceReminderCursor();
  DateTime get now => widget.clock?.call().toUtc() ?? DateTime.now().toUtc();
  DateTime get authoritativeNow =>
      serverTime == null ? now : serverTime!.add(now.difference(fetchedAt!));
  String get preferenceKey => 'desktop-attendance-reminders/v1/${widget.owner}';
  @override
  void initState() {
    super.initState();
    init();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> init() async {
    if (widget.withReminders) {
      try {
        final value = await widget.store.read(preferenceKey);
        final term = await widget.store.read('$preferenceKey/term');
        if (mounted) {
          setState(() {
            selectedTerm = term;
            enabled = value == 'true' && term != null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => notificationError =
                'Không đọc được cài đặt nhắc. Có thể bật lại bên dưới.',
          );
        }
      }
    }
    if (mounted) await refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(alerts.dispose().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy || !mounted) return;
    setState(() => busy = true);
    try {
      final date = ScheduleClock.date(ScheduleClock.now(authoritativeNow));
      final result = await widget.repository.call('getAttendanceDay', {
        'sessionDate': date,
      });
      if (!mounted) return;
      final latest = (result['lessons'] as List)
          .map((r) => TeachingOccurrence(AttendanceData.from(r as Map)))
          .toList();
      setState(() {
        lessons = latest;
        serverTime = DateTime.fromMillisecondsSinceEpoch(
          (result['serverTime'] as num).toInt(),
          isUtc: true,
        );
        fetchedAt = now;
        error = null;
      });
      if (widget.withReminders) {
        try {
          await alerts.retain(
            enabled
                ? visible
                      .where((p) => !p.completed && p.editable)
                      .map((p) => p.key)
                      .toSet()
                : {},
          );
          final due = cursor.scan(visible, authoritativeNow);
          for (final r in (enabled ? due : <DesktopAttendanceReminder>[])) {
            if (!mounted) return;
            await publishReminder(r);
          }
        } catch (_) {
          if (mounted) {
            setState(
              () => notificationError =
                  'Không cập nhật được thông báo Windows. Dữ liệu điểm danh vẫn đã đồng bộ.',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle(bool value) async {
    if (value && selectedTerm == null) return;
    try {
      await widget.store.write(preferenceKey, '$value');
      if (!mounted) return;
      setState(() {
        enabled = value;
        notificationError = null;
      });
      cursor.previous = authoritativeNow;
      if (!value) await alerts.retain({});
    } catch (_) {
      if (mounted) {
        setState(
          () => notificationError =
              'Không lưu được cài đặt nhắc. Vui lòng thử lại.',
        );
      }
    }
  }

  Future<void> selectTerm(String? term) async {
    setState(() {
      selectedTerm = term;
    });
    cursor.previous = authoritativeNow;
    try {
      if (widget.withReminders) {
        if (term == null) {
          await widget.store.delete('$preferenceKey/term');
          await toggle(false);
        } else {
          await widget.store.write('$preferenceKey/term', term);
        }
        await alerts.retain({});
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => notificationError =
              'Không lưu được học kỳ nhắc. Vui lòng chọn lại.',
        );
      }
    }
  }

  Future<void> testAlert() async {
    if (visible.isEmpty) return;
    final lesson = visible.first;
    await publishReminder(
      DesktopAttendanceReminder(
        'test|${lesson.key}',
        authoritativeNow,
        lesson,
        test: true,
      ),
    );
  }

  Future<void> publishReminder(DesktopAttendanceReminder reminder) async {
    final at = authoritativeNow;
    var sentToWindows = false;
    try {
      await alerts.show(reminder, () {
        if (mounted) openQuick(reminder.lesson);
      });
      sentToWindows = true;
    } catch (_) {
      // Record the attempt even when Windows rejected the request.
    }
    if (!mounted) return;
    try {
      await history.record(reminder, at, sentToWindows: sentToWindows);
    } catch (_) {
      if (mounted) {
        setState(() {
          notificationError = sentToWindows
              ? 'Đã gửi yêu cầu tới Windows nhưng chưa lưu được lịch sử.'
              : 'Gửi tới Windows thất bại và chưa lưu được lịch sử.';
        });
      }
      return;
    }
    if (mounted && (!sentToWindows || reminder.test)) {
      setState(() {
        notificationError = sentToWindows
            ? 'Đã gửi yêu cầu thử tới Windows và lưu vào lịch sử.'
            : 'Gửi tới Windows thất bại. Xem lần nhắc này trong lịch sử.';
      });
    }
  }

  Future<void> openQuick(TeachingOccurrence lesson) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuickAttendanceScreen(
          repository: widget.repository,
          selector: lesson.selector,
          owner: widget.owner,
          store: widget.store,
          portalRepository: widget.portalRepository,
        ),
      ),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pending = visible.where((p) => !p.completed).length;
    final terms = {
      ...lessons.map((p) => p.semester),
      if (selectedTerm != null) selectedTerm!,
    }.toList()..sort();
    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Điểm danh hôm nay · $pending buổi chưa chốt',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : refresh,
                icon: const Icon(Icons.sync),
                label: const Text('Đồng bộ mobile'),
              ),
            ],
          ),
          const Text(
            'Mặc định Có mặt trong bản nháp, chọn sinh viên Vắng rồi xác nhận lưu. Điểm danh nhanh dùng được cả trước và sau giờ học, đến trước 00:00.',
          ),
          DropdownButton<String>(
            value: selectedTerm ?? '',
            hint: const Text('Chọn học kỳ'),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Tất cả học kỳ (chọn một học kỳ để bật nhắc)'),
              ),
              for (final term in terms)
                DropdownMenuItem(value: term, child: Text(term)),
            ],
            onChanged: (value) => selectTerm(value == '' ? null : value),
          ),
          if (widget.withReminders) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nhắc buổi chưa hoàn tất điểm danh'),
              subtitle: const Text(
                'Giữa buổi · trước kết thúc 5 phút · sau kết thúc 10 phút · 21:00. Nhắc khi app đang chạy; tự đồng bộ mỗi 30 giây.',
              ),
              value: enabled,
              onChanged: selectedTerm == null ? null : toggle,
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: visible.isEmpty ? null : testAlert,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Thử thông báo Windows'),
                ),
                if (notificationError != null) Text(notificationError!),
              ],
            ),
          ],
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              'Chưa đồng bộ được: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!busy && error == null && lessons.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Hôm nay chưa có buổi học được ghép lớp. Lịch đổi/hủy/học bù được lấy từ backend chung.',
              ),
            ),
          for (final lesson in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${lesson.subjectCode} · ${lesson.classCode} · Slot ${lesson.slot}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${lesson.data['scheduledStartTime']}–${lesson.data['scheduledEndTime']} · Phòng ${lesson.room} · ${lesson.semester}',
                        ),
                        Text(
                          lesson.completed
                              ? 'Đã hoàn tất điểm danh'
                              : lesson.end.isBefore(authoritativeNow)
                              ? 'Đã hết giờ học · còn có thể điểm danh trước 00:00'
                              : 'Chưa hoàn tất điểm danh',
                          style: TextStyle(
                            color: lesson.completed
                                ? Colors.green
                                : Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (widget.onOpenQr != null &&
                          [
                            'AVAILABLE',
                            'OPEN',
                          ].contains(lesson.data['qrState']))
                        OutlinedButton(
                          onPressed: error != null
                              ? null
                              : () => widget.onOpenQr!(lesson),
                          child: const Text('Mở QR'),
                        ),
                      FilledButton(
                        onPressed: error != null
                            ? null
                            : () => openQuick(lesson),
                        child: Text(
                          lesson.editable
                              ? lesson.completed
                                    ? 'Xem / Điều chỉnh'
                                    : 'Điểm danh nhanh'
                              : 'Xem kết quả',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return Card(
      child: widget.compact
          ? ExpansionTile(
              title: Text('Điểm danh hôm nay · $pending buổi chưa chốt'),
              subtitle: Text(
                error != null
                    ? 'Chưa đồng bộ được. Mở để kiểm tra.'
                    : 'Mở điểm danh nhanh và cài đặt nhắc trước 00:00',
              ),
              children: [content],
            )
          : content,
    );
  }
}

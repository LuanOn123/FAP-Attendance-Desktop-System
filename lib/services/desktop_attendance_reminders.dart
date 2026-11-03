import 'package:local_notifier/local_notifier.dart';
import '../models/teaching_occurrence.dart';
import 'schedule_clock.dart';

class DesktopAttendanceReminder {
  final String key;
  final DateTime at;
  final TeachingOccurrence lesson;
  final bool test;
  DesktopAttendanceReminder(
    this.key,
    this.at,
    this.lesson, {
    this.test = false,
  });
  String get title =>
      test ? 'Thử thông báo điểm danh' : 'Nhắc điểm danh · ${lesson.classCode}';
  String get body => test
      ? 'Thông báo thử của FAP Attendance. Bấm để mở ${lesson.classCode}, ngày ${lesson.date}, slot ${lesson.slot}.'
      : 'Lớp ${lesson.classCode} · Slot ${lesson.slot}${lesson.room.isEmpty ? '' : ' · Phòng ${lesson.room}'} ngày ${lesson.date} chưa hoàn tất điểm danh. Mở điểm danh nhanh trước 00:00.';
}

/// Mirrors Mobile's four bounded reminders, using UTC instants and campus dates.
List<DesktopAttendanceReminder> planDesktopAttendanceReminders(
  List<TeachingOccurrence> lessons,
) {
  final out = <DesktopAttendanceReminder>[], seen = <String>{};
  for (final p in lessons) {
    if (p.completed || !p.editable || !seen.add(p.key)) continue;
    final midnight = DateTime.parse(
      '${p.date}T00:00:00+07:00',
    ).add(const Duration(days: 1));
    final middle = p.start.add(
      Duration(milliseconds: p.end.difference(p.start).inMilliseconds ~/ 2),
    );
    final evening = DateTime.parse('${p.date}T21:00:00+07:00');
    final times = <DateTime>{};
    for (final entry in [
      ('mid', middle),
      if (p.end.subtract(const Duration(minutes: 5)).isAfter(middle))
        ('before-end', p.end.subtract(const Duration(minutes: 5))),
      ('overdue', p.end.add(const Duration(minutes: 10))),
      if (!p.start.isAfter(evening)) ('evening', evening),
    ]) {
      if (!entry.$2.isBefore(midnight) || !times.add(entry.$2)) continue;
      out.add(DesktopAttendanceReminder('${entry.$1}|${p.key}', entry.$2, p));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

class AttendanceReminderCursor {
  DateTime? previous;
  final Set<String> delivered = {};
  List<DesktopAttendanceReminder> scan(
    List<TeachingOccurrence> lessons,
    DateTime now,
  ) {
    final from = previous;
    previous = now;
    delivered.removeWhere(
      (key) => !key.contains(ScheduleClock.date(ScheduleClock.now(now))),
    );
    if (from == null || now.isBefore(from)) return [];
    // On wake/resume show at most the latest due alert for each lesson.
    final latest = <String, DesktopAttendanceReminder>{};
    for (final r in planDesktopAttendanceReminders(lessons)) {
      if (r.lesson.date != ScheduleClock.date(ScheduleClock.now(now))) continue;
      if (r.at.isAfter(from) &&
          !r.at.isAfter(now) &&
          !delivered.contains(r.key)) {
        latest[r.lesson.key] = r;
      }
    }
    for (final r in latest.values) {
      delivered.add(r.key);
    }
    return latest.values.toList();
  }
}

abstract class AttendanceAlerts {
  Future<void> show(
    DesktopAttendanceReminder reminder,
    void Function() onClick,
  );
  Future<void> retain(Set<String> lessonKeys);
  Future<void> dispose();
}

class WindowsAttendanceAlerts implements AttendanceAlerts {
  Future<void>? _setup;
  bool _disposed = false;
  final Map<String, ({String lesson, LocalNotification notification})> _active =
      {};
  @override
  Future<void> show(
    DesktopAttendanceReminder reminder,
    void Function() onClick,
  ) async {
    _setup ??= localNotifier.setup(
      appName: 'FAP Attendance',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    try {
      await _setup;
    } catch (_) {
      _setup = null;
      rethrow;
    }
    if (_disposed) return;
    final previous = _active.remove(reminder.key);
    if (previous != null) await previous.notification.destroy();
    final notification = LocalNotification(
      title: reminder.title,
      body: reminder.body,
    );
    notification.onClick = onClick;
    _active[reminder.key] = (
      lesson: reminder.lesson.key,
      notification: notification,
    );
    await notification.show();
  }

  @override
  Future<void> retain(Set<String> lessonKeys) async {
    for (final key in _active.keys.toList()) {
      if (!lessonKeys.contains(_active[key]!.lesson)) {
        await _active.remove(key)!.notification.destroy();
      }
    }
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return retain({});
  }
}

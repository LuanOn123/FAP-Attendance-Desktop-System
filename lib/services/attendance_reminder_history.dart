import 'dart:convert';

import '../models/teaching_occurrence.dart';
import 'attendance_local_store.dart';
import 'desktop_attendance_reminders.dart';

class AttendanceReminderEntry {
  final String id, title, body;
  final DateTime at;
  final AttendanceData selector;
  final bool sentToWindows;

  const AttendanceReminderEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.selector,
    required this.sentToWindows,
  });

  factory AttendanceReminderEntry.fromJson(Map<String, dynamic> json) =>
      AttendanceReminderEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        at: DateTime.parse(json['at'] as String),
        selector: AttendanceData.from(json['selector'] as Map),
        sentToWindows: json['sentToWindows'] == true,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'at': at.toUtc().toIso8601String(),
    'selector': selector,
    'sentToWindows': sentToWindows,
  };
}

/// Private to the signed-in lecturer and this Windows installation.
class AttendanceReminderHistory {
  final AttendanceLocalStore store;
  final String owner;
  Future<void> _pending = Future.value();

  AttendanceReminderHistory(this.store, this.owner);

  String get _key => 'desktop-attendance-reminder-history/v1/$owner';

  Future<List<AttendanceReminderEntry>> read() async {
    await _pending;
    return _read();
  }

  Future<List<AttendanceReminderEntry>> _read() async {
    final raw = await store.read(_key);
    if (raw == null) return [];
    final rows = jsonDecode(raw) as List;
    return [
      for (final row in rows)
        AttendanceReminderEntry.fromJson(AttendanceData.from(row as Map)),
    ];
  }

  Future<void> record(
    DesktopAttendanceReminder reminder,
    DateTime at, {
    required bool sentToWindows,
  }) {
    final entry = AttendanceReminderEntry(
      id: reminder.test
          ? '${reminder.key}|${at.microsecondsSinceEpoch}'
          : reminder.key,
      title: reminder.title,
      body: reminder.body,
      at: at,
      selector: reminder.lesson.selector,
      sentToWindows: sentToWindows,
    );
    final result = _pending.then((_) async {
      final previous = await _read();
      final entries = [entry, ...previous.where((old) => old.id != entry.id)]
        ..sort((a, b) => b.at.compareTo(a.at));
      await store.write(
        _key,
        jsonEncode(entries.take(100).map((e) => e.toJson()).toList()),
      );
    });
    _pending = result.catchError((Object _) {});
    return result;
  }
}

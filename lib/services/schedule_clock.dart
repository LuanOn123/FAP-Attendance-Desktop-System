import '../models/schedule.dart';

/// Campus time is UTC+7, regardless of the desktop operating system timezone.
class ScheduleClock {
  static DateTime now([DateTime? instant]) =>
      (instant ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
  static String date(DateTime day) => day.toIso8601String().substring(0, 10);
  static int? minutes(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final h = int.parse(match[1]!);
    final m = int.parse(match[2]!);
    return h < 24 && m < 60 ? h * 60 + m : null;
  }

  static bool isCurrent(Schedule s, {DateTime? instant, String? exactDate}) {
    final local = now(instant);
    if (exactDate != null
        ? date(local) != exactDate
        : local.weekday != s.dayOfWeek) {
      return false;
    }
    final start = minutes(s.startTime), end = minutes(s.endTime);
    final minute = local.hour * 60 + local.minute;
    return start != null && end != null && minute >= start && minute < end;
  }

  static DateTime next(Schedule s, {DateTime? instant}) {
    final local = now(instant);
    final start = minutes(s.startTime) ?? 0;
    var day = DateTime.utc(local.year, local.month, local.day).add(
      Duration(days: (s.dayOfWeek - local.weekday + 7) % 7, minutes: start),
    );
    if (day.isBefore(local) && !isCurrent(s, instant: instant)) {
      day = day.add(const Duration(days: 7));
    }
    return day;
  }
}

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../core/app_config.dart';
import '../models/teaching_occurrence.dart';
import '../models/roster.dart';
import '../services/google_sheet_service.dart';
import '../services/schedule_clock.dart';
import 'attendance_repository.dart';
import 'schedule_repository.dart';

abstract class DailyAttendanceRepository {
  Future<AttendanceData> call(String name, AttendanceData input);
}

class SheetDailyAttendanceRepository implements DailyAttendanceRepository {
  final GoogleSheetService sheets;
  SheetDailyAttendanceRepository(this.sheets);
  @override
  Future<AttendanceData> call(String name, AttendanceData input) async {
    try {
      return AttendanceData.from(
        await sheets.request('desktopAttendanceCall', {
              'name': name,
              'input': input,
            })
            as Map,
      );
    } on AppException catch (e) {
      const errors = {
        'QUICK_ATTENDANCE_DAY_EXPIRED':
            'Đã qua 00:00 giờ Việt Nam. Chỉ được xem kết quả ngày trước.',
        'ATTENDANCE_CONFLICT':
            'Mobile hoặc thiết bị khác vừa đổi kết quả. Tải lại trước khi lưu.',
        'ATTENDANCE_ALREADY_FINALIZED':
            'Lần gửi này không còn khớp kết quả hiện tại. Tải lại để kiểm tra.',
        'ROSTER_CHANGED':
            'Danh sách sinh viên đã thay đổi. Tải lại danh sách trước khi lưu.',
        'SESSION_CLOSED': 'Phiên đã thay đổi hoặc reset. Tải lại dữ liệu.',
        'NOT_ENROLLED': 'Danh sách không còn khớp lớp học.',
        'OCCURRENCE_NOT_FOUND':
            'Buổi học không còn hợp lệ. Kiểm tra lịch đổi/hủy trên mobile.',
        'PERMISSION_DENIED': 'Bạn không có quyền điểm danh lớp này.',
        'SHARED_BACKEND_SETUP_REQUIRED':
            'Cần cập nhật backend dùng chung và chạy setupLab2Free.',
      };
      if (e.message.contains('Thao tác chưa được hỗ trợ')) {
        throw const AppException(
          'Backend chưa có API điểm danh nhanh cho desktop. Cập nhật Code.gs và AttendanceSafety.gs của backend dùng chung rồi deploy version mới.',
        );
      }
      throw AppException(errors[e.message] ?? e.message);
    }
  }
}

/// Explicit demo delegates writes to the same in-memory attendance repository
/// used by QR and reports. It is never a fallback for a failed real API call.
class DemoDailyAttendanceRepository implements DailyAttendanceRepository {
  final ScheduleRepository schedules;
  final AttendanceRepository attendance;
  final String lecturerId;
  final DateTime Function() clock;
  final Map<String, AttendanceData> receipts = {};
  DemoDailyAttendanceRepository(
    this.schedules,
    this.attendance,
    this.lecturerId, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  @override
  Future<AttendanceData> call(String name, AttendanceData input) async {
    final now = clock().toUtc(),
        today = ScheduleClock.date(ScheduleClock.now(now));
    final date = '${input['sessionDate']}';
    final classes = await schedules.getClasses(),
        rows = await schedules.getSchedules();
    final lessons = <AttendanceData>[];
    for (final c in classes.where((c) => c.lecturerId == lecturerId)) {
      final sessions = await attendance.getSessionsByClass(c.classId);
      for (final s in rows.where(
        (s) =>
            s.lecturerId == lecturerId &&
            s.key == c.key &&
            s.dayOfWeek == DateTime.parse(date).weekday,
      )) {
        final existing = sessions
            .where(
              (e) => e.date == date && e.slot == s.slot && e.status != 'RESET',
            )
            .firstOrNull;
        final start = DateTime.parse('${date}T${s.startTime}:00+07:00'),
            end = DateTime.parse('${date}T${s.endTime}:00+07:00');
        lessons.add({
          'classId': c.classId,
          'classCode': c.classCode,
          'subjectId': c.subjectCode,
          'semester': c.semester,
          'room': s.room,
          'sessionDate': date,
          'slot': s.slot,
          'scheduleId': s.scheduleId,
          'exceptionId': '',
          'scheduledStartTime': s.startTime,
          'scheduledEndTime': s.endTime,
          'scheduledStartAt': start.millisecondsSinceEpoch,
          'scheduledEndAt': end
              .add(
                end.isBefore(start) ? const Duration(days: 1) : Duration.zero,
              )
              .millisecondsSinceEpoch,
          'sessionId': existing?.sessionId,
          'completed': existing?.status == 'CLOSED',
          'editable': date == today,
          'state': date == today ? 'AVAILABLE' : 'DAY_EXPIRED',
          'qrState': now.isBefore(start)
              ? 'NOT_YET'
              : now.isAfter(end)
              ? 'ENDED'
              : 'AVAILABLE',
        });
      }
    }
    if (name == 'getAttendanceDay') {
      return {
        'serverTime': now.millisecondsSinceEpoch,
        'sessionDate': date,
        'lessons': lessons,
      };
    }
    final lesson = lessons
        .where(
          (o) =>
              o['classId'] == input['classId'] &&
              '${o['slot']}' == '${input['slot']}' &&
              (input['scheduleId'] == null ||
                  input['scheduleId'] == o['scheduleId']),
        )
        .single;
    final cls = classes.singleWhere((c) => c.classId == lesson['classId']);
    final roster = await schedules.getRoster(
      ClassTarget(
        semester: cls.semester,
        subjectCode: cls.subjectCode,
        classCode: cls.classCode,
        classId: cls.classId,
      ),
    );
    final records = lesson['sessionId'] == null
        ? []
        : await attendance.getSessionAttendance(lesson['sessionId'] as String);
    final revision = sha256
        .convert(
          utf8.encode(
            jsonEncode(
              records
                  .map((r) => [r.studentCode, r.status, r.updatedAt])
                  .toList(),
            ),
          ),
        )
        .toString();
    if (name == 'getQuickAttendanceContext') {
      return {
        ...lesson,
        'serverTime': now.millisecondsSinceEpoch,
        'revision': revision,
        'attendanceCompleted': lesson['completed'],
        'students': roster.map((s) {
          final record = records
              .where((r) => r.studentCode == s.studentCode)
              .firstOrNull;
          return {
            'studentId': s.studentCode,
            'studentCode': s.studentCode,
            'displayName': s.fullName,
            'status': record?.status.toLowerCase(),
          };
        }).toList(),
      };
    }
    final requestId = '${input['clientRequestId']}';
    if (receipts.containsKey(requestId)) return receipts[requestId]!;
    if (date != today) throw const AppException('Đã qua 00:00 giờ Việt Nam.');
    if (revision != input['expectedRevision']) {
      throw const AppException('Dữ liệu đã thay đổi. Tải lại trước khi lưu.');
    }
    if (name != 'submitQuickAttendance' || roster.isEmpty) {
      throw const AppException('Lớp chưa có danh sách sinh viên.');
    }
    final ids = List<String>.from(input['studentIds'] as List);
    if (ids.length != roster.length ||
        roster.any((s) => !ids.contains(s.studentCode))) {
      throw const AppException('Danh sách sinh viên đã thay đổi.');
    }
    final session = lesson['sessionId'] == null
        ? await attendance.startSession(
            classId: cls.classId,
            date: date,
            slot: lesson['slot'] as int,
            startTime: lesson['scheduledStartTime'] as String,
            endTime: lesson['scheduledEndTime'] as String,
            lecturerId: lecturerId,
          )
        : (await attendance.getSessionsByClass(
            cls.classId,
          )).singleWhere((s) => s.sessionId == lesson['sessionId']);
    final exceptions = {
      for (final e in input['exceptions'] as List) e['studentId']: e['status'],
    };
    for (final s in roster) {
      final old = records
          .where((r) => r.studentCode == s.studentCode)
          .firstOrNull;
      final status =
          exceptions[s.studentCode] ??
          (old?.status == 'ABSENT' || old?.status == 'EXCUSED'
              ? 'ABSENT'
              : 'PRESENT');
      if (old != null) {
        if (status != old.status) {
          await attendance.updateAttendanceStatus(
            attendanceId: old.attendanceId,
            status: status as String,
            note: 'Điểm danh nhanh demo',
            updatedBy: lecturerId,
          );
        }
      } else if (status == 'PRESENT') {
        await attendance.checkInStudent(
          sessionId: session.sessionId,
          token: session.currentToken,
          secretCode: session.currentSecretCode,
          studentCode: s.studentCode,
          fullName: s.fullName,
          email: s.email,
        );
      }
    }
    await attendance.closeSession(session.sessionId);
    await attendance.markAbsent(
      sessionId: session.sessionId,
      studentCodes: roster.map((s) => s.studentCode).toList(),
      lecturerEmail: lecturerId,
    );
    return receipts[requestId] = {
      'classSessionId': session.sessionId,
      'status': 'CLOSED',
      'savedAt': now.millisecondsSinceEpoch,
    };
  }
}

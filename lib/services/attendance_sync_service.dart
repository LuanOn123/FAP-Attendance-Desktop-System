import '../core/app_config.dart';
import '../models/roster.dart';
import '../models/class_model.dart';
import '../models/session_model.dart';
import '../repositories/schedule_repository.dart';
import '../repositories/attendance_repository.dart';
import 'schedule_clock.dart';

/// Reads a fresh report for one exact teaching session. No stored browser copy.
class AttendanceSyncService {
  final ScheduleRepository schedules;
  final AttendanceRepository attendance;
  final String lecturerId;
  AttendanceSyncService(this.schedules, this.attendance, this.lecturerId);

  Future<Map<String, dynamic>> report(Map<String, dynamic> query) async {
    String value(String key) => '${query[key] ?? ''}'.trim();
    final date = value('date');
    final slot = int.tryParse(value('slot'));
    final start = ScheduleClock.minutes(value('startTime'));
    final end = ScheduleClock.minutes(value('endTime'));
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        slot == null ||
        start == null ||
        end == null ||
        start >= end ||
        value('classCode').isEmpty ||
        value('courseCode').isEmpty) {
      throw const AppException(
        'Trang thiếu môn, lớp, ngày, slot hoặc giờ học. Chưa thể đồng bộ.',
      );
    }
    final classes = (await schedules.getClasses())
        .where(
          (c) =>
              c.lecturerId == lecturerId &&
              c.classCode.toUpperCase() == value('classCode').toUpperCase() &&
              c.subjectCode.toUpperCase() ==
                  value('courseCode').toUpperCase() &&
              (value('semester').isEmpty ||
                  c.semester.toUpperCase() == value('semester').toUpperCase()),
        )
        .toList();
    final matches = <({ClassModel cls, SessionModel session})>[];
    for (final cls in classes) {
      final sessions = (await attendance.getSessionsByClass(cls.classId))
          .where(
            (s) =>
                s.createdBy == lecturerId &&
                s.status != 'RESET' &&
                s.date == date &&
                s.slot == slot &&
                ScheduleClock.minutes(s.startTime) == start &&
                ScheduleClock.minutes(s.endTime) == end,
          )
          .toList();
      for (final session in sessions) {
        matches.add((cls: cls, session: session));
      }
    }
    if (matches.length != 1) {
      throw AppException(
        matches.isEmpty
            ? 'Không có báo cáo khớp chính xác buổi học trên trang.'
            : 'Có nhiều báo cáo trùng buổi học. Kiểm tra học kỳ và dữ liệu phiên.',
      );
    }
    final cls = matches.single.cls;
    final session = matches.single.session;
    if (session.status != 'CLOSED') {
      throw const AppException(
        'Phiên đang mở. Kết thúc phiên trên app để chốt danh sách trước khi đồng bộ.',
      );
    }
    final roster = await schedules.getRoster(
      ClassTarget(
        semester: cls.semester,
        subjectCode: cls.subjectCode,
        classCode: cls.classCode,
        classId: cls.classId,
      ),
    );
    if (roster.isEmpty) {
      throw const AppException('Lớp chưa có danh sách sinh viên.');
    }
    final records = await attendance.getSessionAttendance(session.sessionId);
    final seen = <String>{};
    final entries = <Map<String, String>>[];
    for (final student in roster) {
      final code = student.studentCode.trim().toUpperCase();
      if (code.isEmpty || !seen.add(code)) {
        throw const AppException('Danh sách lớp có MSSV trống hoặc trùng.');
      }
      final found = records
          .where((r) => r.studentCode.trim().toUpperCase() == code)
          .toList();
      if (found.length != 1) {
        throw const AppException(
          'Danh sách chưa chốt đầy đủ hoặc bị trùng. Mở Điểm danh và chốt danh sách vắng trước khi đồng bộ.',
        );
      }
      final status = found.single.status.toUpperCase();
      if (!['PRESENT', 'LATE', 'ABSENT'].contains(status)) {
        throw const AppException('Có trạng thái chưa hỗ trợ đồng bộ.');
      }
      entries.add({
        'studentCode': code,
        'status': status == 'ABSENT' ? 'absent' : 'present',
        'originalStatus': status,
      });
    }
    entries.sort((a, b) => a['studentCode']!.compareTo(b['studentCode']!));
    // Recheck reset/close while loading the roster and attendance snapshot.
    final stillCurrent = await attendance.getSessionsByClass(cls.classId);
    if (!stillCurrent.any(
      (s) => s.sessionId == session.sessionId && s.status == 'CLOSED',
    )) {
      throw const AppException('Phiên vừa thay đổi. Hãy tải lại báo cáo.');
    }
    return {
      'success': true,
      'data': {
        'source': 'desktop',
        'sessionId': session.sessionId,
        'metadata': {
          'semester': cls.semester,
          'courseCode': cls.subjectCode,
          'classCode': cls.classCode,
          'date': date,
          'slot': slot,
          'startTime': session.startTime,
          'endTime': session.endTime,
        },
        'entries': entries,
      },
    };
  }
}

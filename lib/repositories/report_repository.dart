import '../models/attendance_record.dart';
import '../models/class_model.dart';
import '../models/session_model.dart';
import '../services/google_sheet_service.dart';

/// Thống kê tổng quan cho Dashboard
class DashboardStats {
  final int totalClasses;
  final int totalStudents;
  final int todaySessions;
  final int presentCount;
  final int lateCount;
  final int absentCount;

  const DashboardStats({
    required this.totalClasses,
    required this.totalStudents,
    required this.todaySessions,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
  });

  int get totalAttendance => presentCount + lateCount + absentCount;
  double get attendanceRate =>
      totalAttendance == 0 ? 0 : (presentCount + lateCount) / totalAttendance;

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
    totalClasses: (j['totalClasses'] as num?)?.toInt() ?? 0,
    totalStudents: (j['totalStudents'] as num?)?.toInt() ?? 0,
    todaySessions: (j['todaySessions'] as num?)?.toInt() ?? 0,
    presentCount: (j['presentCount'] as num?)?.toInt() ?? 0,
    lateCount: (j['lateCount'] as num?)?.toInt() ?? 0,
    absentCount: (j['absentCount'] as num?)?.toInt() ?? 0,
  );
}

/// Báo cáo điểm danh của một sinh viên trong lớp
class StudentAttendanceSummary {
  final String studentCode;
  final String fullName;
  final int totalSessions;
  final int presentCount;
  final int lateCount;
  final int absentCount;

  const StudentAttendanceSummary({
    required this.studentCode,
    required this.fullName,
    required this.totalSessions,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
  });

  double get attendanceRate =>
      totalSessions == 0 ? 0 : (presentCount + lateCount) / totalSessions;

  bool get isAtRisk => attendanceRate < 0.8;
}

abstract class ReportRepository {
  Future<DashboardStats> getDashboard(String lecturerId);

  /// Tổng hợp điểm danh từng sinh viên trong một lớp
  Future<List<StudentAttendanceSummary>> getClassReport({
    required String classId,
    required List<AttendanceRecord> records,
    required List<SessionModel> sessions,
  });

  /// Lấy danh sách bản ghi để xuất Excel FAP
  Future<List<AttendanceRecord>> getExportRecords({
    required String classId,
    required String semester,
  });
}

class SheetReportRepository implements ReportRepository {
  final GoogleSheetService sheets;
  SheetReportRepository(this.sheets);

  @override
  Future<DashboardStats> getDashboard(String lecturerId) async {
    final result = await sheets.request('getDashboard', {'lecturerId': lecturerId});
    return DashboardStats.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<List<StudentAttendanceSummary>> getClassReport({
    required String classId,
    required List<AttendanceRecord> records,
    required List<SessionModel> sessions,
  }) async {
    return _buildSummaries(records, sessions);
  }

  @override
  Future<List<AttendanceRecord>> getExportRecords({
    required String classId,
    required String semester,
  }) async {
    final result = await sheets.request('getExportRecords', {
      'classId': classId,
      'semester': semester,
    });
    return (result as List)
        .map((item) => AttendanceRecord.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}

class DemoReportRepository implements ReportRepository {
  final Map<String, List<AttendanceRecord>> _demoHistory;
  final Map<String, List<SessionModel>> _demoSessions;
  final List<ClassModel> _demoClasses;

  DemoReportRepository({
    Map<String, List<AttendanceRecord>>? history,
    Map<String, List<SessionModel>>? sessions,
    List<ClassModel>? classes,
  })  : _demoHistory = history ?? _buildDemoHistory(),
        _demoSessions = sessions ?? _buildDemoSessions(),
        _demoClasses = classes ?? _buildDemoClasses();

  @override
  Future<DashboardStats> getDashboard(String lecturerId) async {
    final allRecords = _demoHistory.values.expand((r) => r).toList();
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final todaySessions = _demoSessions.values
        .expand((s) => s)
        .where((s) => s.date == todayStr)
        .length;

    return DashboardStats(
      totalClasses: _demoClasses.length,
      totalStudents: 45,
      todaySessions: todaySessions,
      presentCount: allRecords.where((r) => r.isPresent).length,
      lateCount: allRecords.where((r) => r.isLate).length,
      absentCount: allRecords.where((r) => r.isAbsent).length,
    );
  }

  @override
  Future<List<StudentAttendanceSummary>> getClassReport({
    required String classId,
    required List<AttendanceRecord> records,
    required List<SessionModel> sessions,
  }) async {
    final effectiveRecords = records.isNotEmpty ? records : (_demoHistory[classId] ?? []);
    final effectiveSessions = sessions.isNotEmpty ? sessions : (_demoSessions[classId] ?? []);
    return _buildSummaries(effectiveRecords, effectiveSessions);
  }

  @override
  Future<List<AttendanceRecord>> getExportRecords({
    required String classId,
    required String semester,
  }) async {
    return _demoHistory[classId] ?? [];
  }

  static Map<String, List<AttendanceRecord>> _buildDemoHistory() {
    final now = DateTime.now();
    final sessions = ['demo-ses-001', 'demo-ses-002', 'demo-ses-003'];
    final students = [
      ('SE184001', 'Nguyen Van A'),
      ('SE184002', 'Tran Thi B'),
      ('SE184003', 'Le Van C'),
      ('SE184004', 'Pham Thi D'),
      ('SE184005', 'Hoang Van E'),
    ];
    final statuses = ['PRESENT', 'PRESENT', 'LATE', 'PRESENT', 'ABSENT'];

    final records = <AttendanceRecord>[];
    for (int si = 0; si < sessions.length; si++) {
      for (int i = 0; i < students.length; i++) {
        final (code, name) = students[i];
        final status = (si == 2 && i == 3) ? 'ABSENT' : statuses[i];
        records.add(AttendanceRecord(
          attendanceId: 'att-demo-$si-$i',
          sessionId: sessions[si],
          studentId: 'std-$code',
          studentCode: code,
          fullName: name,
          status: status,
          checkInTime: status != 'ABSENT'
              ? now.subtract(Duration(hours: si * 3)).toIso8601String()
              : '',
          updatedAt: now.toIso8601String(),
          note: '',
          updatedBy: 'system',
        ));
      }
    }
    return {'demo-cls-001': records};
  }

  static Map<String, List<SessionModel>> _buildDemoSessions() {
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final yesterday = today.subtract(const Duration(days: 1));
    final yStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final twoDaysAgo = today.subtract(const Duration(days: 7));
    final twoStr =
        '${twoDaysAgo.year}-${twoDaysAgo.month.toString().padLeft(2, '0')}-${twoDaysAgo.day.toString().padLeft(2, '0')}';

    return {
      'demo-cls-001': [
        SessionModel(
          sessionId: 'demo-ses-001',
          classId: 'demo-cls-001',
          date: twoStr,
          slot: 1,
          startTime: '07:30',
          endTime: '09:00',
          status: 'CLOSED',
          currentToken: '',
          tokenExpiredAt: '',
          createdBy: 'lec-001',
        ),
        SessionModel(
          sessionId: 'demo-ses-002',
          classId: 'demo-cls-001',
          date: yStr,
          slot: 2,
          startTime: '09:15',
          endTime: '10:45',
          status: 'CLOSED',
          currentToken: '',
          tokenExpiredAt: '',
          createdBy: 'lec-001',
        ),
        SessionModel(
          sessionId: 'demo-ses-003',
          classId: 'demo-cls-001',
          date: todayStr,
          slot: 3,
          startTime: '13:00',
          endTime: '14:30',
          status: 'OPEN',
          currentToken: 'DEMO_TKN',
          tokenExpiredAt: DateTime.now().add(const Duration(minutes: 2)).toIso8601String(),
          createdBy: 'lec-001',
        ),
      ],
    };
  }

  static List<ClassModel> _buildDemoClasses() => [
    const ClassModel(
      classId: 'demo-cls-001',
      semester: 'FA26',
      subjectCode: 'PRM393',
      classCode: 'SE1848',
      lecturerId: 'lec-001',
    ),
    const ClassModel(
      classId: 'demo-cls-002',
      semester: 'FA26',
      subjectCode: 'SWE201',
      classCode: 'SE1901',
      lecturerId: 'lec-001',
    ),
  ];
}

/// Hàm tính toán báo cáo dùng chung cho cả Sheet và Demo
List<StudentAttendanceSummary> _buildSummaries(
  List<AttendanceRecord> records,
  List<SessionModel> sessions,
) {
  final totalSessions = sessions.length;
  final grouped = <String, List<AttendanceRecord>>{};
  for (final r in records) {
    grouped.putIfAbsent(r.studentCode, () => []).add(r);
  }
  return grouped.entries.map((entry) {
    final code = entry.key;
    final recs = entry.value;
    final name = recs.first.fullName;
    return StudentAttendanceSummary(
      studentCode: code,
      fullName: name,
      totalSessions: totalSessions,
      presentCount: recs.where((r) => r.isPresent).length,
      lateCount: recs.where((r) => r.isLate).length,
      absentCount: recs.where((r) => r.isAbsent).length,
    );
  }).toList()
    ..sort((a, b) => a.studentCode.compareTo(b.studentCode));
}

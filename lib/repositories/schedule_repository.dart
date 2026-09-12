import '../core/app_config.dart';
import '../models/class_model.dart';
import '../models/schedule.dart';
import '../models/roster.dart';
import '../services/google_sheet_service.dart';

abstract class ScheduleRepository {
  Future<List<Schedule>> getSchedules();
  Future<List<ClassModel>> getClasses();
  Future<void> save(List<Schedule> rows);
  Future<void> delete(String id);
  Future<List<RosterStudent>> getRoster(ClassTarget target);
  Future<RosterImportResult> importRoster(
    ClassTarget target,
    List<RosterStudent> students,
  );
}

class SheetScheduleRepository implements ScheduleRepository {
  final GoogleSheetService sheets;
  SheetScheduleRepository(this.sheets);
  Future<dynamic> _rosterRequest(String action, Map<String, dynamic> payload) async {
    try { return await sheets.request(action, payload); }
    on AppException catch (e) {
      if (e.message.contains('Thao tác chưa được hỗ trợ')) {
        throw const AppException('Apps Script đang dùng bản cũ. Cập nhật Code.gs và deployment để sử dụng danh sách sinh viên.');
      }
      rethrow;
    }
  }
  @override
  Future<List<RosterStudent>> getRoster(ClassTarget target) async =>
      (await _rosterRequest('getRoster', target.toJson()) as List)
          .map(
            (j) => RosterStudent.fromJson(Map<String, dynamic>.from(j as Map)),
          )
          .toList();
  @override
  Future<RosterImportResult> importRoster(
    ClassTarget target,
    List<RosterStudent> students,
  ) async => RosterImportResult.fromJson(
    Map<String, dynamic>.from(
      await _rosterRequest('importRoster', {
            ...target.toJson(),
            'students': students.map((s) => s.toJson()).toList(),
          })
          as Map,
    ),
  );
  @override
  Future<List<Schedule>> getSchedules() async =>
      (await sheets.getRows('Schedules')).map(Schedule.fromJson).toList();
  @override
  Future<List<ClassModel>> getClasses() async =>
      (await sheets.getRows('Classes')).map(ClassModel.fromJson).toList();
  @override
  Future<void> save(List<Schedule> rows) async {
    for (final row in rows) {
      final errors = row.validate();
      if (errors.isNotEmpty) throw AppException(errors.join('\n'));
    }
    await sheets.batchUpdate('Schedules', rows.map((s) => s.toJson()).toList());
  }

  @override
  Future<void> delete(String id) => sheets.deleteRow('Schedules', id);
}

/// Explicit offline demo: in-memory sample data, never a fallback for real login.
class DemoScheduleRepository implements ScheduleRepository {
  final _classes = <ClassModel>[
    const ClassModel(
      classId: 'demo-class',
      semester: 'FA26',
      subjectCode: 'PRM393',
      classCode: 'SE1848',
      lecturerId: 'demo-lecturer',
    ),
  ];
  final _rosters = <String, Map<String, RosterStudent>>{};
  @override
  Future<List<RosterStudent>> getRoster(ClassTarget target) async =>
      _rosters[target.key]?.values.toList() ?? [];
  @override
  Future<RosterImportResult> importRoster(
    ClassTarget target,
    List<RosterStudent> students,
  ) async {
    final matches = classTargets(
      _classes,
      _rows,
      'demo-lecturer',
    ).where((c) => c.key == target.key);
    if (matches.isEmpty) {
      throw const AppException('Lớp chưa có trong lịch dạy.');
    }
    if (students.isEmpty ||
        students.length > 1000 ||
        students.any(
          (s) => normalizeCode(s.classCode) != normalizeCode(target.classCode),
        )) {
      throw const AppException(
        'Danh sách không thuộc lớp đã chọn hoặc quá 1.000 sinh viên.',
      );
    }
    if (!_classes.any((c) => c.key == target.key)) {
      _classes.add(
        ClassModel(
          classId: 'demo-${target.key}',
          semester: target.semester,
          subjectCode: target.subjectCode,
          classCode: target.classCode,
          lecturerId: 'demo-lecturer',
        ),
      );
    }
    final roster = _rosters.putIfAbsent(target.key, () => {});
    var added = 0, existing = 0;
    for (final s in students) {
      final code = normalizeCode(s.studentCode);
      if (roster.containsKey(code)) {
        existing++;
      } else {
        roster[code] = s;
        added++;
      }
    }
    return RosterImportResult(added, existing);
  }

  final List<Schedule> _rows = [
    const Schedule(
      scheduleId: 'demo-schedule',
      lecturerId: 'demo-lecturer',
      semester: 'FA26',
      subjectCode: 'PRM393',
      subjectName: 'Mobile Programming',
      classCode: 'SE1848',
      dayOfWeek: 1,
      slot: 1,
      startTime: '07:30',
      endTime: '09:00',
      room: 'AL-201',
      sourceType: 'MANUAL',
    ),
  ];
  @override
  Future<List<Schedule>> getSchedules() async => List.of(_rows);
  @override
  Future<List<ClassModel>> getClasses() async => List.of(_classes);
  @override
  Future<void> save(List<Schedule> rows) async {
    for (final row in rows) {
      if (row.validate().isNotEmpty) {
        throw AppException(row.validate().join('\n'));
      }
    }
    for (final row in rows) {
      _rows.removeWhere((s) => s.scheduleId == row.scheduleId);
      _rows.add(row);
    }
  }

  @override
  Future<void> delete(String id) async {
    _rows.removeWhere((s) => s.scheduleId == id);
  }
}

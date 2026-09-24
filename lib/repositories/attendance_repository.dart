import 'dart:math';
import '../core/app_config.dart';
import '../models/attendance_record.dart';
import '../models/session_model.dart';
import '../services/google_sheet_service.dart';
import '../models/class_model.dart';

abstract class AttendanceRepository {
  Future<SessionModel> startSession({
    String? date,
    required String classId,
    required int slot,
    required String startTime,
    required String endTime,
    required String lecturerId,
  });

  Future<void> rotateSessionToken({
    required String sessionId,
    required String newToken,
    required String newSecretCode,
    required String tokenExpiredAt,
  });

  Future<SessionModel> resetSession(String sessionId);

  Future<void> closeSession(String sessionId);

  Future<List<AttendanceRecord>> getSessionAttendance(String sessionId);

  Future<Map<String, dynamic>> checkInStudent({
    required String sessionId,
    required String token,
    required String secretCode,
    required String studentCode,
    required String fullName,
    required String email,
  });

  /// Member 4: Cập nhật trạng thái điểm danh thủ công
  Future<void> updateAttendanceStatus({
    required String attendanceId,
    required String status,
    required String note,
    required String updatedBy,
  });

  /// Member 4: Đánh dấu ABSENT cho sinh viên chưa điểm danh khi chốt phiên
  Future<void> markAbsent({
    required String sessionId,
    required List<String> studentCodes,
    required String lecturerEmail,
  });

  /// Member 4: Lấy toàn bộ lịch sử điểm danh của một lớp
  Future<List<AttendanceRecord>> getClassHistory(String classId);

  /// Member 4: Lấy danh sách session của một lớp
  Future<List<SessionModel>> getSessionsByClass(String classId);

  /// Member 4: Lấy danh sách lớp của giảng viên (dùng trong report)
  Future<List<ClassModel>> getLecturerClasses(String lecturerId);
}

class SheetAttendanceRepository implements AttendanceRepository {
  final GoogleSheetService sheets;
  SheetAttendanceRepository(this.sheets);

  @override
  Future<SessionModel> startSession({
    String? date,
    required String classId,
    required int slot,
    required String startTime,
    required String endTime,
    required String lecturerId,
  }) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final token = List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    const secret = '';
    final expiresAt = now
        .toUtc()
        .add(const Duration(seconds: 120))
        .toIso8601String();

    dynamic result;
    try {
      result = await sheets.request('createSession', {
        'classId': classId,
        'date': date ?? today,
        'slot': slot,
        'startTime': startTime,
        'endTime': endTime,
        'currentToken': token,
        'currentSecretCode': secret,
        'tokenExpiredAt': expiresAt,
      });
    } on AppException catch (e) {
      if (e.message.contains('Thao tác chưa được hỗ trợ')) {
        throw const AppException(
          'Apps Script đang dùng bản cũ. Hãy copy Code.gs mới nhất lên Google Apps Script và tạo Deployment mới để sử dụng tính năng Điểm danh.',
        );
      }
      rethrow;
    }

    return SessionModel.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> rotateSessionToken({
    required String sessionId,
    required String newToken,
    required String newSecretCode,
    required String tokenExpiredAt,
  }) async {
    await sheets.request('rotateToken', {
      'sessionId': sessionId,
      'currentToken': newToken,
      'currentSecretCode': newSecretCode,
      'tokenExpiredAt': tokenExpiredAt,
    });
  }

  @override
  Future<SessionModel> resetSession(String sessionId) async {
    final result = await sheets.request('resetSession', {
      'sessionId': sessionId,
    });
    return SessionModel.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> closeSession(String sessionId) async {
    await sheets.request('closeSession', {'sessionId': sessionId});
  }

  @override
  Future<List<AttendanceRecord>> getSessionAttendance(String sessionId) async {
    final result = await sheets.request('getSessionAttendance', {
      'sessionId': sessionId,
    });
    return (result as List)
        .map(
          (item) =>
              AttendanceRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>> checkInStudent({
    required String sessionId,
    required String token,
    required String secretCode,
    required String studentCode,
    required String fullName,
    required String email,
  }) async {
    final result = await sheets.request('studentCheckIn', {
      'sessionId': sessionId,
      'token': token,
      'secretCode': secretCode,
      'studentCode': studentCode.trim().toUpperCase(),
      'fullName': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'checkInTime': DateTime.now().toIso8601String(),
    });
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> updateAttendanceStatus({
    required String attendanceId,
    required String status,
    required String note,
    required String updatedBy,
  }) async {
    await sheets.request('updateAttendance', {
      'attendanceId': attendanceId,
      'status': status,
      'note': note,
      'updatedBy': updatedBy,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> markAbsent({
    required String sessionId,
    required List<String> studentCodes,
    required String lecturerEmail,
  }) async {
    await sheets.request('markAbsent', {
      'sessionId': sessionId,
      'studentCodes': studentCodes,
      'markedBy': lecturerEmail,
      'markedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<List<AttendanceRecord>> getClassHistory(String classId) async {
    try {
      final sessions = await getSessionsByClass(classId);
      final results = await Future.wait(
        sessions.map(
          (s) => getSessionAttendance(
            s.sessionId,
          ).catchError((_) => <AttendanceRecord>[]),
        ),
      );
      return results.expand((list) => list).toList();
    } catch (_) {
      final result = await sheets.request('getClassHistory', {
        'classId': classId,
      });
      return (result as List)
          .map(
            (item) => AttendanceRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    }
  }

  @override
  Future<List<SessionModel>> getSessionsByClass(String classId) async {
    final targetId = classId.trim().toUpperCase();
    if (targetId.isEmpty) return [];
    try {
      final rows = await sheets.getRows('Sessions');
      return rows
          .where((r) {
            final rowClassId = (r['classId']?.toString() ?? '')
                .trim()
                .toUpperCase();
            if (rowClassId.isEmpty) return false;
            return rowClassId == targetId && r['status'] != 'RESET';
          })
          .map((r) => SessionModel.fromJson(r))
          .toList();
    } catch (_) {
      final result = await sheets.request('getSessionsByClass', {
        'classId': classId.trim(),
      });
      return (result as List)
          .map(
            (item) =>
                SessionModel.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    }
  }

  @override
  Future<List<ClassModel>> getLecturerClasses(String lecturerId) async {
    try {
      final rows = await sheets.getRows('Classes');
      return rows
          .where((r) => r['lecturerId']?.toString() == lecturerId)
          .map((r) => ClassModel.fromJson(r))
          .toList();
    } catch (_) {
      final result = await sheets.request('getLecturerClasses', {
        'lecturerId': lecturerId,
      });
      return (result as List)
          .map(
            (item) =>
                ClassModel.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    }
  }
}

class DemoAttendanceRepository implements AttendanceRepository {
  final Map<String, SessionModel> _sessions = {};
  final List<AttendanceRecord> _attendanceRecords = [];

  @override
  Future<SessionModel> startSession({
    String? date,
    required String classId,
    required int slot,
    required String startTime,
    required String endTime,
    required String lecturerId,
  }) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final sessionId = 'demo-session-${now.microsecondsSinceEpoch}';
    final token = 'DEMO_TKN_${now.millisecondsSinceEpoch}';
    const secret = '';
    final expiresAt = now
        .toUtc()
        .add(const Duration(seconds: 120))
        .toIso8601String();

    final session = SessionModel(
      sessionId: sessionId,
      classId: classId,
      date: date ?? today,
      slot: slot,
      startTime: startTime,
      endTime: endTime,
      status: 'OPEN',
      currentToken: token,
      currentSecretCode: secret,
      tokenExpiredAt: expiresAt,
      createdBy: lecturerId,
    );

    _sessions[sessionId] = session;
    return session;
  }

  @override
  Future<void> rotateSessionToken({
    required String sessionId,
    required String newToken,
    required String newSecretCode,
    required String tokenExpiredAt,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const AppException('Phiên điểm danh không tồn tại.');
    }
    _sessions[sessionId] = session.copyWith(
      currentToken: newToken,
      currentSecretCode: newSecretCode,
      tokenExpiredAt: tokenExpiredAt,
    );
  }

  @override
  Future<SessionModel> resetSession(String sessionId) async {
    final old = _sessions[sessionId];
    if (old == null || old.status == 'RESET') {
      throw const AppException('Phiên không còn hiệu lực.');
    }
    _sessions[sessionId] = old.copyWith(status: 'RESET');
    return startSession(
      date: old.date,
      classId: old.classId,
      slot: old.slot,
      startTime: old.startTime,
      endTime: old.endTime,
      lecturerId: old.createdBy,
    );
  }

  @override
  Future<void> closeSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const AppException('Phiên điểm danh không tồn tại.');
    }
    _sessions[sessionId] = session.copyWith(status: 'CLOSED');
  }

  @override
  Future<List<AttendanceRecord>> getSessionAttendance(String sessionId) async {
    return _attendanceRecords.where((r) => r.sessionId == sessionId).toList();
  }

  @override
  Future<Map<String, dynamic>> checkInStudent({
    required String sessionId,
    required String token,
    required String secretCode,
    required String studentCode,
    required String fullName,
    required String email,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const AppException('Phiên điểm danh không tồn tại.');
    }
    if (!session.isOpen) {
      throw const AppException('Phiên điểm danh đã kết thúc.');
    }
    if (secretCode != session.currentSecretCode) {
      throw const AppException('Secret Code không chính xác.');
    }

    // Check duplicate
    final code = studentCode.trim().toUpperCase();
    final already = _attendanceRecords.any(
      (r) => r.sessionId == sessionId && r.studentCode == code,
    );
    if (already) {
      throw const AppException('Sinh viên đã điểm danh trong ca học này.');
    }

    final now = DateTime.now();
    final record = AttendanceRecord(
      attendanceId: 'att-${now.millisecondsSinceEpoch}',
      sessionId: sessionId,
      studentId: 'std-$code',
      studentCode: code,
      fullName: fullName.isEmpty ? 'Sinh viên $code' : fullName,
      status: 'PRESENT',
      checkInTime: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
      note: 'Demo check-in',
      updatedBy: 'Student',
    );

    _attendanceRecords.add(record);
    return {
      'status': record.status,
      'checkInTime': record.checkInTime,
      'studentCode': record.studentCode,
      'fullName': record.fullName,
    };
  }

  @override
  Future<void> updateAttendanceStatus({
    required String attendanceId,
    required String status,
    required String note,
    required String updatedBy,
  }) async {
    final idx = _attendanceRecords.indexWhere(
      (r) => r.attendanceId == attendanceId,
    );
    if (idx == -1) throw const AppException('Bản ghi điểm danh không tồn tại.');
    _attendanceRecords[idx] = _attendanceRecords[idx].copyWith(
      status: status,
      note: note,
      updatedBy: updatedBy,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<void> markAbsent({
    required String sessionId,
    required List<String> studentCodes,
    required String lecturerEmail,
  }) async {
    final now = DateTime.now();
    for (final code in studentCodes) {
      if (_attendanceRecords.any(
        (r) => r.sessionId == sessionId && r.studentCode == code,
      )) {
        continue;
      }
      _attendanceRecords.add(
        AttendanceRecord(
          attendanceId: 'absent-${now.millisecondsSinceEpoch}-$code',
          sessionId: sessionId,
          studentId: 'std-$code',
          studentCode: code,
          fullName: 'Sinh viên $code',
          status: 'ABSENT',
          checkInTime: '',
          updatedAt: now.toIso8601String(),
          note: 'Tự động đánh vắng khi chốt phiên',
          updatedBy: lecturerEmail,
        ),
      );
    }
  }

  @override
  Future<List<AttendanceRecord>> getClassHistory(String classId) async {
    final sessionIds = _sessions.values
        .where((s) => s.classId == classId)
        .map((s) => s.sessionId)
        .toSet();
    return _attendanceRecords
        .where((r) => sessionIds.contains(r.sessionId))
        .toList();
  }

  @override
  Future<List<SessionModel>> getSessionsByClass(String classId) async {
    final targetId = classId.trim();
    if (targetId.isEmpty) return [];
    return _sessions.values
        .where((s) => s.classId == targetId && s.status != 'RESET')
        .toList();
  }

  @override
  Future<List<ClassModel>> getLecturerClasses(String lecturerId) async {
    // Demo: trả về danh sách lớp mẫu
    return [
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
}

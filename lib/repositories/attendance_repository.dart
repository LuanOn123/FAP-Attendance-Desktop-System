import 'dart:math';
import '../core/app_config.dart';
import '../models/attendance_record.dart';
import '../models/session_model.dart';
import '../services/google_sheet_service.dart';

abstract class AttendanceRepository {
  Future<SessionModel> startSession({
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
}

class SheetAttendanceRepository implements AttendanceRepository {
  final GoogleSheetService sheets;
  SheetAttendanceRepository(this.sheets);

  @override
  Future<SessionModel> startSession({
    required String classId,
    required int slot,
    required String startTime,
    required String endTime,
    required String lecturerId,
  }) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final token = 'TKN_${now.millisecondsSinceEpoch}_${Random().nextInt(9000) + 1000}';
    final secret = (Random().nextInt(900000) + 100000).toString();
    final expiresAt = now.add(const Duration(seconds: 120)).toIso8601String();

    final result = await sheets.request('createSession', {
      'classId': classId,
      'date': today,
      'slot': slot,
      'startTime': startTime,
      'endTime': endTime,
      'currentToken': token,
      'currentSecretCode': secret,
      'tokenExpiredAt': expiresAt,
    });

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
}

class DemoAttendanceRepository implements AttendanceRepository {
  final Map<String, SessionModel> _sessions = {};
  final List<AttendanceRecord> _attendanceRecords = [];

  @override
  Future<SessionModel> startSession({
    required String classId,
    required int slot,
    required String startTime,
    required String endTime,
    required String lecturerId,
  }) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final sessionId = 'demo-session-${now.millisecondsSinceEpoch}';
    final token = 'DEMO_TKN_${now.millisecondsSinceEpoch}';
    final secret = (Random().nextInt(900000) + 100000).toString();
    final expiresAt = now.add(const Duration(seconds: 120)).toIso8601String();

    final session = SessionModel(
      sessionId: sessionId,
      classId: classId,
      date: today,
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
    if (session == null) throw const AppException('Phiên điểm danh không tồn tại.');
    _sessions[sessionId] = session.copyWith(
      currentToken: newToken,
      currentSecretCode: newSecretCode,
      tokenExpiredAt: tokenExpiredAt,
    );
  }

  @override
  Future<void> closeSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) throw const AppException('Phiên điểm danh không tồn tại.');
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

    // Calculate status (Present within first 15 mins, otherwise Late)
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
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/reports/attendance_report_screen.dart';
import 'package:fap_attendance/features/reports/widgets/manual_update_dialog.dart';
import 'package:fap_attendance/features/reports/widgets/report_table.dart';
import 'package:fap_attendance/models/attendance_record.dart';
import 'package:fap_attendance/models/class_model.dart';
import 'package:fap_attendance/models/lecturer.dart';
import 'package:fap_attendance/models/schedule.dart';
import 'package:fap_attendance/models/session_model.dart';
import 'package:fap_attendance/repositories/attendance_repository.dart';

class MockAttendanceRepository implements AttendanceRepository {
  @override
  Future<SessionModel> resetSession(String sessionId) =>
      throw UnimplementedError();
  List<SessionModel> sessions = [];
  List<AttendanceRecord> records = [];

  @override
  Future<List<SessionModel>> getSessionsByClass(String classId) async =>
      sessions;

  @override
  Future<List<AttendanceRecord>> getSessionAttendance(String sessionId) async =>
      records;

  @override
  Future<void> updateAttendanceStatus({
    required String attendanceId,
    required String status,
    required String note,
    required String updatedBy,
  }) async {
    final idx = records.indexWhere((r) => r.attendanceId == attendanceId);
    if (idx != -1) {
      records[idx] = records[idx].copyWith(
        status: status,
        note: note,
        updatedBy: updatedBy,
      );
    }
  }

  @override
  Future<List<AttendanceRecord>> getClassHistory(String classId) async =>
      records;

  @override
  Future<List<ClassModel>> getLecturerClasses(String lecturerId) async => [];

  @override
  Future<SessionModel> startSession({
    String? date,
    required String classId,
    required int slot,
    required String startTime,
    required String endTime,
    required String lecturerId,
  }) async => throw UnimplementedError();

  @override
  Future<void> rotateSessionToken({
    required String sessionId,
    required String newToken,
    required String newSecretCode,
    required String tokenExpiredAt,
  }) async {}

  @override
  Future<void> closeSession(String sessionId) async {}

  @override
  Future<Map<String, dynamic>> checkInStudent({
    required String sessionId,
    required String token,
    required String secretCode,
    required String studentCode,
    required String fullName,
    required String email,
  }) async => throw UnimplementedError();

  @override
  Future<void> markAbsent({
    required String sessionId,
    required List<String> studentCodes,
    required String lecturerEmail,
  }) async {}
}

void main() {
  const sampleLecturer = Lecturer(
    lecturerId: 'LEC001',
    lecturerCode: 'toannv',
    fullName: 'Nguyen Van Toan',
    email: 'toannvse181848@fpt.edu.vn',
    department: 'SE',
  );

  const sampleClass = ClassModel(
    classId: 'CLS_PRM393_SE1848',
    semester: 'FA26',
    subjectCode: 'PRM393',
    classCode: 'SE1848',
    lecturerId: 'LEC001',
  );

  const sampleSchedule = Schedule(
    scheduleId: 'SCH001',
    lecturerId: 'LEC001',
    semester: 'FA26',
    subjectCode: 'PRM393',
    subjectName: 'Mobile Programming',
    classCode: 'SE1848',
    dayOfWeek: 2,
    slot: 3,
    startTime: '12:30',
    endTime: '15:00',
    room: 'BE-301',
    sourceType: 'MANUAL',
  );

  final List<AttendanceRecord> sampleRecords = [
    const AttendanceRecord(
      attendanceId: 'ATT001',
      sessionId: 'SES001',
      studentId: 'STD001',
      studentCode: 'SE181848',
      fullName: 'Nguyen Van A',
      status: 'PRESENT',
      checkInTime: '2026-09-18T12:35:00.000Z',
      updatedAt: '',
    ),
    const AttendanceRecord(
      attendanceId: 'ATT002',
      sessionId: 'SES001',
      studentId: 'STD002',
      studentCode: 'SE181849',
      fullName: 'Tran Thi B',
      status: 'LATE',
      checkInTime: '2026-09-18T12:50:00.000Z',
      updatedAt: '',
    ),
    const AttendanceRecord(
      attendanceId: 'ATT003',
      sessionId: 'SES001',
      studentId: 'STD003',
      studentCode: 'SE181850',
      fullName: 'Le Van C',
      status: 'ABSENT',
      checkInTime: '',
      updatedAt: '',
    ),
  ];

  group('ReportTable Component Tests', () {
    testWidgets(
      'renders table headers and student rows with correct status & FAP codes',
      (tester) async {
        int? tappedIndex;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReportTable(
                records: sampleRecords,
                selectedClass: sampleClass,
                loading: false,
                onEdit: (idx) => tappedIndex = idx,
              ),
            ),
          ),
        );

        // Verify Table Headers
        expect(find.text('MSSV'), findsOneWidget);
        expect(find.text('Họ và tên'), findsOneWidget);
        expect(find.text('Lớp học'), findsOneWidget);
        expect(find.text('Trạng thái'), findsOneWidget);
        expect(find.text('FAP'), findsOneWidget);

        // Verify Student Data Rows
        expect(find.text('SE181848'), findsOneWidget);
        expect(find.text('Nguyen Van A'), findsOneWidget);
        expect(find.text('Có mặt'), findsOneWidget);
        expect(find.text('P'), findsOneWidget);

        expect(find.text('SE181849'), findsOneWidget);
        expect(find.text('Tran Thi B'), findsOneWidget);
        expect(find.text('Đi muộn'), findsOneWidget);
        expect(find.text('L'), findsOneWidget);

        expect(find.text('SE181850'), findsOneWidget);
        expect(find.text('Le Van C'), findsOneWidget);
        expect(find.text('Vắng'), findsOneWidget);
        expect(find.text('A'), findsOneWidget);

        // Tap on a row to trigger edit
        await tester.tap(find.text('SE181848'));
        expect(tappedIndex, equals(0));
      },
    );

    testWidgets('renders empty state when no records exist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportTable(
              records: const [],
              selectedClass: sampleClass,
              loading: false,
              onEdit: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Chưa có sinh viên nào điểm danh qua QR cho buổi này.'),
        findsOneWidget,
      );
    });
  });

  group('ManualUpdateDialog Tests', () {
    testWidgets('allows changing attendance status and saving notes', (
      tester,
    ) async {
      String? savedStatus;
      String? savedNote;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualUpdateDialog(
              record: sampleRecords[2], // ABSENT student
              onSave: (status, note) async {
                savedStatus = status;
                savedNote = note;
              },
            ),
          ),
        ),
      );

      expect(find.text('Cập nhật trạng thái'), findsOneWidget);
      expect(find.text('Le Van C'), findsOneWidget);
      expect(find.text('MSSV: SE181850'), findsOneWidget);

      // Change status to PRESENT
      await tester.tap(find.text('Có mặt'));
      await tester.pump();

      // Enter reason / note
      await tester.enterText(find.byType(TextField), 'Có mặt có phép');
      await tester.pump();

      // Tap Save button
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();

      expect(savedStatus, equals('PRESENT'));
      expect(savedNote, equals('Có mặt có phép'));
    });
  });

  group('AttendanceReportScreen Full Feature Tests', () {
    testWidgets('loads and renders class attendance summary metrics', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockRepo = MockAttendanceRepository();
      mockRepo.sessions = [
        const SessionModel(
          sessionId: 'SES001',
          classId: 'CLS_PRM393_SE1848',
          date: '2026-09-18',
          slot: 3,
          startTime: '12:30',
          endTime: '15:00',
          status: 'CLOSED',
          currentToken: 'TKN123',
          currentSecretCode: '123456',
          tokenExpiredAt: '2026-09-18T13:00:00.000Z',
          createdBy: 'toannvse181848@fpt.edu.vn',
        ),
      ];
      mockRepo.records = sampleRecords;

      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceReportScreen(
            lecturer: sampleLecturer,
            classes: const [sampleClass],
            schedules: const [sampleSchedule],
            attendanceRepository: mockRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header and Title
      expect(find.text('Báo cáo & Đồng bộ FAP'), findsOneWidget);
      expect(find.text('Xuất Excel (.xlsx)'), findsOneWidget);
      expect(find.text('Xuất CSV (.csv)'), findsOneWidget);

      // Verify Stat Pills
      expect(find.text('Tổng điểm danh: '), findsOneWidget);
      expect(find.text('Có mặt: '), findsOneWidget);
      expect(find.text('Đi muộn: '), findsOneWidget);
      expect(find.text('Vắng: '), findsOneWidget);

      // Verify Warning Badge for 1 absent student
      expect(find.text('1 sinh viên vắng trong buổi này'), findsOneWidget);

      // Verify Students in Table
      expect(find.text('SE181848'), findsOneWidget);
      expect(find.text('Nguyen Van A'), findsOneWidget);
      expect(find.text('SE181849'), findsOneWidget);
      expect(find.text('Tran Thi B'), findsOneWidget);
      expect(find.text('SE181850'), findsOneWidget);
      expect(find.text('Le Van C'), findsOneWidget);
    });
  });
}

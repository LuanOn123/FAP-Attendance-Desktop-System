import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/attendance/attendance_screen.dart';
import 'package:fap_attendance/features/attendance/session_qr_widget.dart';
import 'package:fap_attendance/features/attendance/student_checkin_screen.dart';
import 'package:fap_attendance/features/schedule/schedule_screen.dart';
import 'package:fap_attendance/models/class_model.dart';
import 'package:fap_attendance/models/lecturer.dart';
import 'package:fap_attendance/models/schedule.dart';
import 'package:fap_attendance/repositories/attendance_repository.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  const testLecturer = Lecturer(
    lecturerId: 'toan-se181848',
    lecturerCode: 'TOANNV',
    fullName: 'Nguyen Van Toan',
    email: 'toannvse181848@fpt.edu.vn',
    department: 'Software Engineering',
  );

  const testSchedule = Schedule(
    scheduleId: 'sch-001',
    lecturerId: 'toan-se181848',
    semester: 'FA26',
    subjectCode: 'PRM393',
    subjectName: 'Mobile Programming',
    classCode: 'SE1818',
    dayOfWeek: 2,
    slot: 1,
    startTime: '07:30',
    endTime: '09:00',
    room: 'BE-302',
    sourceType: 'MANUAL',
  );

  const testClass = ClassModel(
    classId: 'cls-001',
    semester: 'FA26',
    subjectCode: 'PRM393',
    classCode: 'SE1818',
    lecturerId: 'toan-se181848',
  );

  group('Teacher QR Attendance Tests for toannvse181848@fpt.edu.vn', () {
    testWidgets('Unmapped schedule blocks session creation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final attendanceRepo = DemoAttendanceRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceScreen(
            lecturer: testLecturer,
            schedules: const [testSchedule],
            classes: const [], // No classes mapped
            repository: attendanceRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bắt đầu phiên điểm danh'), findsOneWidget);
      expect(find.text('Chưa ghép lớp'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Tạo phiên'),
      );
      expect(button.onPressed, isNull); // Disabled when not mapped
    });

    testWidgets('Mapped schedule starts session and generates dynamic QR code with Secret Code', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final attendanceRepo = DemoAttendanceRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceScreen(
            lecturer: testLecturer,
            schedules: const [testSchedule],
            classes: const [testClass],
            repository: attendanceRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đã ghép lớp'), findsOneWidget);
      final createButton = find.widgetWithText(FilledButton, 'Tạo phiên');
      expect(createButton, findsOneWidget);

      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Verify active session UI
      expect(find.text('ĐANG ĐIỂM DANH'), findsOneWidget);
      expect(find.text('QUÉT MÃ QR ĐIỂM DANH'), findsOneWidget);
      expect(find.text('SECRET CODE (NHẬP TRÊN ĐIỆN THOẠI):'), findsOneWidget);

      // Verify QR Code image is generated
      expect(find.byType(QrImageView), findsOneWidget);

      // Verify Secret Code is 6 digits
      final secretFinder = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d{6}$').hasMatch(w.data ?? ''),
      );
      expect(secretFinder, findsOneWidget);
      final initialSecret = (tester.widget(secretFinder) as Text).data!;

      // Verify timer countdown is displayed
      expect(find.textContaining('Đổi mã sau:'), findsOneWidget);

      // Advance 5 seconds and check countdown decrement
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Đổi mã sau: 115s'), findsOneWidget);

      // Test manual token rotation button "Đổi mã ngay"
      final refreshButton = find.byTooltip('Đổi mã ngay');
      expect(refreshButton, findsOneWidget);
      await tester.tap(refreshButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // QR widget still rendered and timer reset
      expect(find.byType(QrImageView), findsOneWidget);

      final newSecretFinder = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d{6}$').hasMatch(w.data ?? ''),
      );
      final newSecret = (tester.widget(newSecretFinder) as Text).data!;
      expect(newSecret, isNotNull);
      expect(find.text('Đổi mã sau: 120s'), findsOneWidget);

      // Test Pause / Resume timer
      final pauseButton = find.byTooltip('Tạm dừng');
      expect(pauseButton, findsOneWidget);
      await tester.tap(pauseButton);
      await tester.pump();
      expect(find.text('Đang tạm dừng'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      // Countdown stays frozen while paused
      expect(find.text('Đang tạm dừng'), findsOneWidget);

      // Resume
      final resumeButton = find.byTooltip('Tiếp tục');
      await tester.tap(resumeButton);
      await tester.pump();
      expect(find.text('Đổi mã sau: 120s'), findsOneWidget);

      // Test Ending session
      final endButton = find.widgetWithText(FilledButton, 'Kết thúc phiên');
      await tester.tap(endButton);
      await tester.pumpAndSettle();

      expect(find.text('Kết thúc điểm danh?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Kết thúc ngay'));
      await tester.pumpAndSettle();

      expect(find.text('ĐÃ ĐÓNG PHIÊN'), findsOneWidget);
      expect(find.text('Phiên điểm danh đã kết thúc.\nMã QR đã bị vô hiệu hóa.'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('Full ScheduleScreen navigation to Attendance tab for lecturer toannvse181848', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final schedRepo = DemoScheduleRepository();
      final attendRepo = DemoAttendanceRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            lecturer: testLecturer,
            repository: schedRepo,
            attendanceRepository: attendRepo,
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigation rail - click tab 2 (Điểm danh)
      final attendanceTab = find.text('Điểm danh');
      expect(attendanceTab, findsOneWidget);
      await tester.tap(attendanceTab);
      await tester.pumpAndSettle();

      expect(find.text('Bắt đầu phiên điểm danh'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/attendance/attendance_screen.dart';
import 'package:fap_attendance/features/attendance/session_qr_widget.dart';
import 'package:fap_attendance/models/class_model.dart';
import 'package:fap_attendance/models/lecturer.dart';
import 'package:fap_attendance/models/schedule.dart';
import 'package:fap_attendance/models/session_model.dart';
import 'package:fap_attendance/repositories/attendance_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fap_attendance/features/schedule/schedule_screen.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';

const lecturer = Lecturer(
  lecturerId: 'l1',
  lecturerCode: 'L1',
  fullName: 'Teacher',
  email: 'teacher@fpt.edu.vn',
  department: 'SE',
);
const schedule = Schedule(
  scheduleId: 's1',
  lecturerId: 'l1',
  semester: 'FA26',
  subjectCode: 'PRN232',
  subjectName: '',
  classCode: 'SE1917',
  dayOfWeek: 2,
  slot: 1,
  startTime: '07:00',
  endTime: '09:15',
  room: '602',
  sourceType: 'MANUAL',
);
const cls = ClassModel(
  classId: 'c1',
  semester: 'FA26',
  subjectCode: 'PRN232',
  classCode: 'SE1917',
  lecturerId: 'l1',
);

class CurrentScheduleRepository extends DemoScheduleRepository {
  @override
  Future<List<Schedule>> getSchedules() async => [schedule];
  @override
  Future<List<ClassModel>> getClasses() async => [cls];
}

void main() {
  test('Sheets localized dates and statuses identify the same closed slot', () {
    final session = SessionModel.fromJson({
      'date': '22/9/2026',
      'status': ' closed ',
    });
    expect(session.date, '2026-09-22');
    expect(session.status, 'CLOSED');
    expect(session.isOpen, false);
  });
  for (final entry in ['slot', 'tab']) {
    testWidgets('current timetable opens QR by $entry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = DemoAttendanceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            lecturer: lecturer,
            repository: CurrentScheduleRepository(),
            attendanceRepository: repo,
            onLogout: () async {},
            clock: () => DateTime.parse('2026-09-22T00:30:00Z'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('● ĐANG DẠY'), findsOneWidget);
      await tester.tap(
        find.text(entry == 'slot' ? 'PRN232 · SE1917 · Slot 1' : 'Điểm danh'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(await repo.getSessionsByClass('c1'), hasLength(1));
      final original = (await repo.getSessionsByClass('c1')).single;
      expect(original.date, '2026-09-22');
      await tester.tap(find.text('Kết thúc phiên'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kết thúc ngay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lịch dạy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Điểm danh'));
      await tester.pumpAndSettle();
      final closed = (await repo.getSessionsByClass('c1')).single;
      expect(closed.sessionId, original.sessionId);
      expect(closed.status, 'CLOSED');
      expect(find.byType(QrImageView), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('unmapped class cannot create a session', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          lecturer: lecturer,
          schedules: const [schedule],
          classes: const [],
          repository: DemoAttendanceRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Tạo phiên'))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'current slot automatically opens QR, secret opt in and reset clears session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = DemoAttendanceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceScreen(
            lecturer: lecturer,
            schedules: const [schedule],
            classes: const [cls],
            repository: repo,
            currentScheduleId: 's1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      final old = (await repo.getSessionsByClass('c1')).single;
      expect(old.currentSecretCode, isEmpty);
      await repo.checkInStudent(
        sessionId: old.sessionId,
        token: old.currentToken,
        secretCode: '',
        studentCode: 'SE123456',
        fullName: 'A',
        email: 'a@fpt.edu.vn',
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        (await repo.getSessionsByClass('c1')).single.currentSecretCode,
        matches(RegExp(r'^\d{6}$')),
      );
      await tester.tap(find.text('Điểm danh lại từ đầu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bắt đầu lại'));
      await tester.pumpAndSettle();
      final fresh = (await repo.getSessionsByClass('c1')).single;
      expect(fresh.sessionId, isNot(old.sessionId));
      expect(await repo.getSessionAttendance(fresh.sessionId), isEmpty);
      expect(await repo.getSessionAttendance(old.sessionId), hasLength(1));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('Kết thúc phiên'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kết thúc ngay'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect((await repo.getSessionsByClass('c1')).single.isOpen, isFalse);
    },
  );
  testWidgets(
    'failed QR rotation hides unconfirmed QR until successful retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      bool fail = true;
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionQrDisplayWidget(
              sessionId: 's1',
              initialToken: 'old',
              initialSecretCode: '',
              onRotateToken: (token, secret) async {
                if (fail) throw Exception('offline');
                saved = token;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đổi mã ngay'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Thử lại'), findsOneWidget);
      await tester.pump(const Duration(seconds: 125));
      expect(saved, isNull);
      fail = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(saved, isNot('old'));
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

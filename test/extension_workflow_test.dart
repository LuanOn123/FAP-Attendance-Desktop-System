import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/schedule/schedule_screen.dart';
import 'package:fap_attendance/models/lecturer.dart';
import 'package:fap_attendance/repositories/attendance_repository.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';
import 'package:fap_attendance/services/integration_server.dart';
import 'fap_import_test.dart' show sampleImport;

class ExportPicker extends FilePicker {
  final String target;
  ExportPicker(this.target);
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => target;
}

class LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  testWidgets(
    'extension POST -> current class -> attendance -> report -> actual XLSX',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1050));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final schedules = DemoScheduleRepository();
      final attendance = DemoAttendanceRepository();
      final bridge = IntegrationServer();
      final temp = Directory.systemTemp.createTempSync('fap-export-test-');
      final target = File('${temp.path}/attendance.xlsx');
      FilePicker.platform = ExportPicker(target.path);
      addTearDown(() {
        temp.deleteSync(recursive: true);
      });
      await tester.runAsync(
        () => bridge.start(schedules, 'demo-lecturer', port: 0),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            lecturer: const Lecturer(
              lecturerId: 'demo-lecturer',
              lecturerCode: 'DEMO',
              fullName: 'Demo teacher',
              email: 'demo@fpt.edu.vn',
              department: 'SE',
            ),
            repository: schedules,
            attendanceRepository: attendance,
            integrationServer: bridge,
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final client = LoopbackHttpOverrides().createHttpClient(null);
        try {
          final request = await client.postUrl(
            Uri.parse(
              'http://127.0.0.1:${bridge.port}/api/integration/fap/session',
            ),
          );
          request.headers.contentType = ContentType.json;
          request.headers.set('X-FAP-Attendance-Client', 'browser-extension');
          request.write(jsonEncode(sampleImport()));
          final response = await request.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Hiện tại'), findsOneWidget);
      expect(find.text('Ngày: 2026-09-18'), findsOneWidget);
      final cards = find.widgetWithText(Card, 'SWE102 - SE1701');
      expect(cards, findsOneWidget);
      expect(
        tester.getTopLeft(find.text('SWE102 - SE1701')).dy,
        lessThan(tester.getTopLeft(find.text('PRM393 - SE1848')).dy),
      );
      await tester.tap(
        find.descendant(of: cards, matching: find.text('Tạo phiên')),
      );
      await tester.pumpAndSettle();
      expect(find.text('ĐANG ĐIỂM DANH'), findsOneWidget);
      final cls = (await schedules.getClasses()).firstWhere(
        (c) => c.classCode == 'SE1701',
      );
      final session = (await attendance.getSessionsByClass(cls.classId)).single;
      expect(session.date, '2026-09-18');
      await attendance.checkInStudent(
        sessionId: session.sessionId,
        token: session.currentToken,
        secretCode: session.currentSecretCode,
        studentCode: 'SE123456',
        fullName: 'Nguyen Van A',
        email: 'a@fpt.edu.vn',
      );
      await tester.tap(find.byTooltip('Làm mới danh sách'));
      await tester.pumpAndSettle();
      expect(find.text('Nguyen Van A'), findsOneWidget);
      // Navigation must preserve an open session and its QR state.
      await tester.tap(find.text('Lịch dạy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Điểm danh'));
      await tester.pumpAndSettle();
      expect(find.text('ĐANG ĐIỂM DANH'), findsOneWidget);
      expect(await attendance.getSessionsByClass(cls.classId), hasLength(1));
      await tester.tap(find.text('Kết thúc phiên'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kết thúc ngay'));
      await tester.pumpAndSettle();
      final records = await attendance.getSessionAttendance(session.sessionId);
      expect(records.where((r) => r.status == 'PRESENT'), hasLength(1));
      expect(records.where((r) => r.status == 'ABSENT'), hasLength(1));
      await tester.tap(find.text('Báo cáo / Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Báo cáo & Xuất file'), findsOneWidget);
      expect(find.text('Le Thi B'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Xuất Excel (.xlsx)'));
        for (var i = 0; i < 100 && !target.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(target.existsSync(), isTrue);
      final zip = ZipDecoder().decodeBytes(target.readAsBytesSync());
      final sheet = utf8.decode(
        zip.findFile('xl/worksheets/sheet1.xml')!.content,
      );
      expect(sheet, contains('SE123456'));
      expect(sheet, contains('SE123457'));
      expect(sheet, contains('PRESENT'));
      expect(sheet, contains('ABSENT'));
      expect(sheet, contains('Nguyen Van A'));
      expect(sheet, contains('Le Thi B'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    },
  );
}

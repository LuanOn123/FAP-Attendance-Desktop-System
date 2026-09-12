import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/schedule/ocr_review_screen.dart';
import 'package:fap_attendance/features/schedule/schedule_screen.dart';
import 'package:fap_attendance/models/lecturer.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';

void main() {
  testWidgets('Manual schedule validates before saving and appears in list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = DemoScheduleRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          lecturer: const Lecturer(
            lecturerId: 'demo-lecturer',
            lecturerCode: 'GV',
            fullName: 'Demo',
            email: 'demo@fpt.edu.vn',
            department: 'IT',
          ),
          repository: repo,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập lịch thủ công'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu lịch dạy'));
    await tester.pumpAndSettle();
    expect(find.text('Bắt buộc'), findsNWidgets(9));
    expect((await repo.getSchedules()).length, 1);
    final fields = find.byType(TextFormField);
    final values = [
      'FA26',
      'SWE201',
      'Software Engineering',
      'SE1901',
      '3',
      '2',
      '09:15',
      '10:45',
      'BE-301',
    ];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.tap(find.text('Lưu lịch dạy'));
    await tester.pumpAndSettle();
    expect((await repo.getSchedules()).length, 2);
    expect(find.text('SWE201  •  SE1901'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'OCR parsing does not save and confirmation is disabled until review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = DemoScheduleRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: OcrReviewScreen(lecturerId: 'demo-lecturer', repository: repo),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('ocrText')),
        'FA26 PRM393 SE1848 Thu 2 Slot 1 07:30-09:00 Room AL-201',
      );
      await tester.pump();
      await tester.tap(find.text('Phân tích lại văn bản'));
      await tester.pumpAndSettle();
      expect(find.text('Dòng 1'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Xác nhận & lưu'),
      );
      expect(save.onPressed, isNull);
      expect((await repo.getSchedules()).length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

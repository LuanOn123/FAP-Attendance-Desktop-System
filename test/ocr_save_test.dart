import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/core/app_config.dart';
import 'package:fap_attendance/features/schedule/ocr_review_screen.dart';
import 'package:fap_attendance/features/schedule/schedule_screen.dart';
import 'package:fap_attendance/models/class_model.dart';
import 'package:fap_attendance/models/lecturer.dart';
import 'package:fap_attendance/models/schedule.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';

class TestRepository extends DemoScheduleRepository {
  bool failClasses = false, failSave = false, failSchedules = false;
  int saves = 0;
  @override
  Future<List<Schedule>> getSchedules() async {
    if (failSchedules) {
      throw const AppException('Không kết nối được Google Sheets.');
    }
    return super.getSchedules();
  }

  @override
  Future<List<ClassModel>> getClasses() async {
    if (failClasses) throw const AppException('Thiếu sheet Classes.');
    return super.getClasses();
  }

  @override
  Future<void> save(List<Schedule> rows) async {
    saves++;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (failSave) throw const AppException('Lịch dạy bị trùng.');
    await super.save(rows);
  }
}

Future<void> openImport(WidgetTester tester, TestRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
  await tester.enterText(find.byType(TextField).first, 'NO_MATCH');
  await tester.tap(find.text('Nhập ảnh OCR'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('ocrText')),
    'FA26 PRN232 SE1917 MON Slot 1 07:00-09:15 Room NVH602',
  );
  await tester.pump();
  await tester.tap(find.text('Phân tích lại văn bản'));
  await tester.pumpAndSettle();
  final name = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Tên môn',
  );
  await tester.ensureVisible(name);
  await tester.enterText(name, 'Application Development');
  final confirm = find.text(
    'Tôi đã đối chiếu và chỉnh sửa tất cả các dòng trước khi lưu.',
  );
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pump();
}

void main() {
  testWidgets(
    'Successful save followed by read failure is distinguished from failed save',
    (tester) async {
      final repo = TestRepository();
      await openImport(tester, repo);
      repo.failSchedules = true;
      await tester.tap(find.text('Xác nhận & lưu'));
      await tester.pumpAndSettle();
      expect(find.byType(OcrReviewScreen), findsNothing);
      expect(
        find.textContaining('Đã lưu lịch nhưng chưa tải lại'),
        findsOneWidget,
      );
      repo.failSchedules = false;
      await tester.tap(find.byTooltip('Tải lại và ghép lớp'));
      await tester.pumpAndSettle();
      expect(find.text('PRN232  •  SE1917'), findsOneWidget);
      expect(repo.saves, 1);
    },
  );
  testWidgets('Filled but invalid time produces visible error without saving', (
    tester,
  ) async {
    final repo = TestRepository();
    await openImport(tester, repo);
    final end = find.byWidgetPredicate(
      (w) =>
          w is TextField && w.decoration?.labelText == 'Giờ kết thúc (HH:mm)',
    );
    await tester.ensureVisible(end);
    await tester.enterText(end, '06:00');
    await tester.pump();
    final confirm = find.text(
      'Tôi đã đối chiếu và chỉnh sửa tất cả các dòng trước khi lưu.',
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    await tester.tap(find.text('Xác nhận & lưu'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(find.byType(OcrReviewScreen), findsOneWidget);
    expect(
      find.widgetWithText(
        SnackBar,
        'Dòng 1: Giờ kết thúc phải sau giờ bắt đầu.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('OCR save returns and shows new schedule despite old search', (
    tester,
  ) async {
    final repo = TestRepository();
    await openImport(tester, repo);
    await tester.tap(find.text('Xác nhận & lưu'));
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect((await repo.getSchedules()).length, 2);
    expect(find.byType(OcrReviewScreen), findsNothing);
    expect(find.text('PRN232  •  SE1917'), findsOneWidget);
  });
  testWidgets('Class lookup failure does not hide saved schedules', (
    tester,
  ) async {
    final repo = TestRepository();
    await openImport(tester, repo);
    repo.failClasses = true;
    await tester.tap(find.text('Xác nhận & lưu'));
    await tester.pumpAndSettle();
    expect(find.text('PRN232  •  SE1917'), findsOneWidget);
  });
  testWidgets(
    'Save failure is visible and preserves editable draft for retry',
    (tester) async {
      final repo = TestRepository()..failSave = true;
      await openImport(tester, repo);
      await tester.tap(find.text('Xác nhận & lưu'));
      await tester.pumpAndSettle();
      expect(find.byType(OcrReviewScreen), findsOneWidget);
      expect(find.textContaining('Lịch dạy bị trùng.'), findsWidgets);
      expect((await repo.getSchedules()).length, 1);
      repo.failSave = false;
      await tester.tap(find.text('Xác nhận & lưu'));
      await tester.pumpAndSettle();
      expect((await repo.getSchedules()).length, 2);
      expect(find.text('PRN232  •  SE1917'), findsOneWidget);
    },
  );
}

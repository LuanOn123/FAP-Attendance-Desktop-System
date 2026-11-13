import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/student_portal/excel_grade_import_dialog.dart';
import 'package:fap_attendance/repositories/student_portal_repository.dart';
import 'grade_excel_import_test.dart' as fixtures;

void main() {
  Future<void> open(
    WidgetTester tester, {
    String code = 'SE001',
    List<String> headers = const ['MSSV', 'Quiz'],
    List<String>? row,
    required void Function(PortalRow?) completed,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => completed(
                await showDialog<PortalRow>(
                  context: context,
                  builder: (_) => ExcelGradeImportDialog(
                    sheets: [
                      fixtures.sheet([
                        headers,
                        row ?? [code, '0'],
                      ]),
                    ],
                    target: fixtures.target,
                    current: fixtures.gradebook(),
                    fileName: 'diem.xlsx',
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder apply() => find.byType(FilledButton);
  const overwrite = 'Xác nhận ghi đè vào bản nháp';

  testWidgets('shows the preview immediately and applies on one confirmation', (
    tester,
  ) async {
    PortalRow? result;
    await open(
      tester,
      headers: [
        'Học kỳ',
        'Mã môn',
        'Mã lớp',
        'MSSV',
        'Họ tên',
        'Quiz',
        'Nhận xét',
      ],
      row: ['FA26', 'PRM393', 'SE1848', 'SE001', 'Sinh viên A', '0', ''],
      completed: (v) => result = v,
    );
    expect(find.text('Sheet dữ liệu'), findsNothing);
    expect(
      find.text('1/2 sinh viên khớp · 1 ô thay đổi · 0 cột mới'),
      findsOneWidget,
    );
    expect(find.text('6 → 0'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text(overwrite));
    await tester.pumpAndSettle();
    expect(result!['students'][0]['grades']['quiz'], 0);
    expect(result!['students'][1]['grades']['quiz'], 5);
    expect(result!['version'], 7);
    expect(result!['activePublicationId'], 'published-before-import');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing options refreshes the preview and cancel returns no draft',
    (tester) async {
      var cancelled = false;
      await open(
        tester,
        row: ['SE001', ''],
        completed: (v) => cancelled = v == null,
      );
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      await tester.tap(find.text('Tùy chọn đọc Excel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text(overwrite), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
    },
  );

  testWidgets('unmatched column can be added after reviewing the mapping', (
    tester,
  ) async {
    PortalRow? result;
    await open(
      tester,
      headers: ['MSSV', 'Assigment'],
      completed: (value) => result = value,
    );
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
    expect(find.text('Bỏ qua cột này'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm cột điểm mới').last);
    await tester.pumpAndSettle();
    expect(find.text('Tên cột mới'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Xác nhận thêm cột'));
    await tester.pumpAndSettle();
    expect(result!['components'].last['name'], 'Assigment');
    expect(result!['students'][0]['grades']['quiz'], 6);
  });

  testWidgets('duplicate Excel headers require manual selection', (
    tester,
  ) async {
    await open(
      tester,
      headers: ['MSSV', 'Quiz', 'QUIZ'],
      row: ['SE001', '0', '1'],
      completed: (_) => fail('Must not apply'),
    );
    expect(find.textContaining('Tên cột lặp trong Excel'), findsNWidgets(2));
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
  });

  testWidgets('wrong-class student is blocked immediately', (tester) async {
    await open(tester, code: 'SE999', completed: (_) => fail('Must not apply'));
    expect(find.textContaining('không thuộc lớp đang chọn'), findsOneWidget);
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
  });
}

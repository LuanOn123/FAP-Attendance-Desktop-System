import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/student_portal/excel_grade_import_dialog.dart';
import 'package:fap_attendance/repositories/student_portal_repository.dart';
import 'grade_excel_import_test.dart' as fixtures;

void main() {
  Future<void> open(
    WidgetTester tester, {
    String code = 'SE001',
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
                        ['MSSV', 'Quiz'],
                        [code, '0'],
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

  Finder apply() => find.widgetWithText(FilledButton, 'Đưa vào bảng nháp');
  Future<void> check(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Kiểm tra / Xem trước'));
    await tester.tap(find.text('Kiểm tra / Xem trước'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'preview and class confirmation required before returning draft; no publication change',
    (tester) async {
      PortalRow? result;
      await open(tester, completed: (v) => result = v);
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      await check(tester);
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      final confirmation = find.text(
        'Tôi xác nhận file điểm thuộc FA26 · PRM393 · SE1848',
      );
      await tester.ensureVisible(confirmation);
      await tester.tap(confirmation);
      await tester.pumpAndSettle();
      await tester.tap(apply());
      await tester.pumpAndSettle();
      expect(result!['students'][0]['grades']['quiz'], 0);
      expect(result!['students'][1]['grades']['quiz'], 5);
      expect(result!['version'], 7);
      expect(result!['activePublicationId'], 'published-before-import');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing import options invalidates confirmed preview; cancel returns no draft',
    (tester) async {
      PortalRow? result;
      var returned = false;
      await open(
        tester,
        completed: (v) {
          returned = true;
          result = v;
        },
      );
      await check(tester);
      final confirmation = find.text(
        'Tôi xác nhận file điểm thuộc FA26 · PRM393 · SE1848',
      );
      await tester.ensureVisible(confirmation);
      await tester.tap(confirmation);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      expect(confirmation, findsNothing);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('wrong-class student cannot apply even after preview', (
    tester,
  ) async {
    await open(tester, code: 'SE999', completed: (_) => fail('Must not apply'));
    await check(tester);
    expect(find.textContaining('không thuộc lớp đang chọn'), findsOneWidget);
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/features/classes/classes_screen.dart';
import 'package:fap_attendance/models/roster.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';
import 'package:fap_attendance/services/markbook_reader.dart';

const target = ClassTarget(
  semester: 'FA26',
  subjectCode: 'PRM393',
  classCode: 'SE1848',
  classId: 'demo-class',
);
const student = RosterStudent(
  classCode: 'SE1848',
  studentCode: 'SE000001',
  fullName: 'Student A',
);
void main() {
  Future<void> open(
    WidgetTester tester,
    DemoScheduleRepository repo,
    Markbook book,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RosterImportScreen(
                    targets: const [target],
                    repository: repo,
                    pickBook: () async => book,
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
    await tester.tap(find.text('Chọn file Excel / ODS'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Matching sheet selects class; import adds roster, repeated import skips duplicates',
    (tester) async {
      final repo = DemoScheduleRepository();
      const book = Markbook('FA26', [
        MarkbookSheet('PRM393_SE1848', 'PRM393', [student], [], 0),
      ]);
      await open(tester, repo, book);
      expect(find.textContaining('Sẽ thêm vào SE1848'), findsOneWidget);
      await tester.tap(find.text('Thêm 1 sinh viên vào lớp'));
      await tester.pumpAndSettle();
      expect((await repo.getRoster(target)).length, 1);
      expect(find.byType(RosterImportScreen), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chọn file Excel / ODS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm 1 sinh viên vào lớp'));
      await tester.pumpAndSettle();
      expect((await repo.getRoster(target)).length, 1);
      expect(find.textContaining('1 đã có'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Conflicting subject does not auto-import into a similarly named class',
    (tester) async {
      final repo = DemoScheduleRepository();
      await open(
        tester,
        repo,
        const Markbook('FA26', [
          MarkbookSheet('PRM232', 'PRM232', [student], [], 0),
        ]),
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Thêm 1 sinh viên vào lớp'),
      );
      expect(button.onPressed, isNull);
      expect((await repo.getRoster(target)), isEmpty);
      final field = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Lớp / môn đích trong lịch đã nhập',
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(target.label).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('khác mã PRM232'), findsOneWidget);
      await tester.tap(find.text('Thêm 1 sinh viên vào lớp'));
      await tester.pumpAndSettle();
      expect((await repo.getRoster(target)).length, 1);
    },
  );
  testWidgets('Wrong class and malformed sheet prevent enrollment', (
    tester,
  ) async {
    final repo = DemoScheduleRepository();
    await open(
      tester,
      repo,
      const Markbook('FA26', [
        MarkbookSheet(
          'Sheet1',
          'PRM393',
          [
            RosterStudent(
              classCode: 'SE9999',
              studentCode: 'SE000001',
              fullName: 'Student A',
            ),
          ],
          [],
          0,
        ),
      ]),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Thêm 1 sinh viên vào lớp'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Chưa có lớp khớp'), findsOneWidget);
    expect((await repo.getRoster(target)), isEmpty);
  });
}

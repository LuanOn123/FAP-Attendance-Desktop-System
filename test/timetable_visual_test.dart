import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/core/app_theme.dart';
import 'package:fap_attendance/features/schedule/schedule_screen.dart';
import 'package:fap_attendance/features/schedule/ocr_review_screen.dart';
import 'package:fap_attendance/features/classes/classes_screen.dart';
import 'package:fap_attendance/models/lecturer.dart';
import 'package:fap_attendance/models/schedule.dart';
import 'package:fap_attendance/models/roster.dart';
import 'package:fap_attendance/services/ocr_layout.dart';
import 'package:fap_attendance/services/schedule_parser.dart';
import 'package:fap_attendance/services/markbook_reader.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';

class _VisualRepo extends DemoScheduleRepository {
  @override
  Future<List<Schedule>> getSchedules() async {
    final data =
        jsonDecode(
              File(
                'test/fixtures/weekly_ocr.json',
              ).readAsStringSync().replaceFirst('\uFEFF', ''),
            )
            as Map<String, dynamic>;
    final drafts = ScheduleParser().parse(
      OcrLayout.reconstruct(data),
      useNvhTimes: true,
    );
    return [
      for (var i = 0; i < drafts.length; i++)
        Schedule.fromJson({
          ...drafts[i].fields,
          'scheduleId': 's$i',
          'lecturerId': 'demo-lecturer',
          'semester': 'FA26',
          'sourceType': 'IMAGE',
          'subjectName': {
            'PRM393': 'Lập trình di động',
            'PRN232': 'Application Development',
            'SWD392': 'Kiến trúc phần mềm',
          }[drafts[i].fields['subjectCode']],
        }),
    ];
  }
}

void main() {
  testWidgets('Weekly timetable and import preview render without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final capture = Platform.environment['CAPTURE_UI'] == '1';
    if (capture) {
      await tester.runAsync(() async {
        final bytes = File('C:/Windows/Fonts/segoeui.ttf').readAsBytesSync();
        await (FontLoader(
          'Segoe UI',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        final icons = File(
          'D:/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytesSync();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
        await (FontLoader(
          'ReviewFont',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
    }
    final boundary = GlobalKey();
    final repo = _VisualRepo();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme().copyWith(
            textTheme: buildTheme().textTheme.apply(
              fontFamily: capture ? 'ReviewFont' : null,
            ),
          ),
          home: ScheduleScreen(
            lecturer: const Lecturer(
              lecturerId: 'demo-lecturer',
              lecturerCode: 'GV',
              fullName: 'Giảng viên',
              email: 'demo@fpt.edu.vn',
              department: 'IT',
            ),
            repository: repo,
            onLogout: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CHỦ NHẬT'), findsOneWidget);
    expect(find.textContaining('SE1917'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    Future<void> snapshot(String name) async {
      if (!capture) return;
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/ui-review/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await snapshot('timetable');
    final rows = List.generate(
      35,
      (i) => RosterStudent(
        classCode: 'SE1848',
        studentCode: 'SE${(i + 1).toString().padLeft(6, '0')}',
        fullName: 'Sinh viên mẫu ${i + 1}',
        email: 'student${i + 1}@example.com',
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme().copyWith(
            textTheme: buildTheme().textTheme.apply(
              fontFamily: capture ? 'ReviewFont' : null,
            ),
          ),
          home: RosterImportScreen(
            targets: const [
              ClassTarget(
                semester: 'FA26',
                subjectCode: 'PRM393',
                classCode: 'SE1848',
              ),
            ],
            repository: repo,
            pickBook: () async => Markbook('FA26', [
              MarkbookSheet('12_PRM393_SE1848', 'PRM393', rows, [], 0),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chọn file Excel / ODS'));
    await tester.pumpAndSettle();
    expect(find.text('35 sinh viên thuộc SE1848'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await snapshot('import-preview');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: OcrReviewScreen(lecturerId: 'demo-lecturer', repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'FA26');
    await tester.enterText(
      find.byKey(const ValueKey('ocrText')),
      'PRM393 SE1917 MON Slot 1 Room NVH602',
    );
    await tester.pump();
    await tester.tap(find.text('Phân tích lại văn bản'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await snapshot('ocr-review');
  });
}

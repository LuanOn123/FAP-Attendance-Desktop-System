import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/services/ocr_layout.dart';
import 'package:fap_attendance/services/schedule_parser.dart';

void main() {
  List<ScheduleDraft> fixture(String name) {
    final data =
        jsonDecode(
              File(
                'test/fixtures/${name}_ocr.json',
              ).readAsStringSync().replaceFirst('\uFEFF', ''),
            )
            as Map<String, dynamic>;
    expect(data['ok'], true);
    return ScheduleParser().parse(
      OcrLayout.reconstruct(data),
      useNvhTimes: true,
    );
  }

  test('Actual weekly screenshot preserves all 20 occupied cells', () {
    final rows = fixture('weekly');
    expect(rows.length, 20);
    for (final row in rows) {
      expect(row.fields['dayOfWeek'], isNotEmpty);
      expect(row.fields['slot'], isNotEmpty);
      expect(row.fields['classCode'], matches(r'^SE\d{4}$'));
      expect(row.fields['startTime'], isNotEmpty);
      expect(row.fields['endTime'], isNotEmpty);
      expect(row.fields['room'], startsWith('NVH '));
    }
    final swd = rows.where((r) => r.fields['subjectCode'] == 'SWD392');
    expect(swd.map((r) => r.fields['dayOfWeek']), ['2', '5']);
    expect(swd.every((r) => r.fields['slot'] == '2'), true);
    expect(
      rows
          .where((r) => r.fields['slot'] == '3')
          .map((r) => r.fields['dayOfWeek']),
      ['1', '2', '3', '4', '5', '6'],
    );
    expect(
      rows
          .where((r) => r.fields['slot'] == '4')
          .map((r) => r.fields['dayOfWeek']),
      ['1', '2', '3', '4', '5', '6'],
    );
  });

  test(
    'Missing assignment OCR codes stay blank; reviewed transcription expands',
    () {
      final rows = fixture('assignment');
      expect(rows.length, 10);
      expect(rows.every((r) => r.fields['slot']!.isEmpty), true);
      expect(rows.every((r) => r.fields['classCode']!.isEmpty), true);
      final reviewed = ScheduleParser().parse(
        File('docs/FA26_assignment_review.txt').readAsStringSync(),
        useNvhTimes: true,
      );
      expect(reviewed.length, 20);
      expect(reviewed.first.fields['dayOfWeek'], '2');
      expect(reviewed.first.fields['startTime'], '12:30');
      expect(reviewed.every((r) => r.fields['classCode']!.isEmpty), true);
    },
  );

  test('Every A/P code expands with correct weekday pair and slot', () {
    for (final prefix in ['A', 'P']) {
      for (var n = 1; n <= 6; n++) {
        final rows = ScheduleParser().parse('PRM393 $prefix$n NVH');
        expect(rows.map((r) => r.fields['dayOfWeek']), [
          '${(n - 1) ~/ 2 + 1}',
          '${(n - 1) ~/ 2 + 4}',
        ]);
        expect(
          rows.first.fields['slot'],
          '${(n - 1) % 2 + (prefix == 'A' ? 1 : 3)}',
        );
        expect(rows.first.fields['startTime'], isEmpty);
      }
    }
    expect(ScheduleParser().parse('PRM393 A7').single.fields['slot'], isEmpty);
    expect(
      ScheduleParser().parse('MON Slot 2 PRM393 A5').single.fields['slot'],
      '2',
    );
  });
}

import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/core/app_config.dart';
import 'package:fap_attendance/services/excel_export_service.dart';
import 'package:fap_attendance/services/grade_excel_import.dart';
import 'package:fap_attendance/repositories/student_portal_repository.dart';

const target = {
  'semester': 'FA26',
  'subjectCode': 'PRM393',
  'classCode': 'SE1848',
};
const mapping = GradeColumnMapping(
  column: 1,
  id: 'quiz',
  name: 'Quiz',
  maxScore: 10,
);
PortalRow gradebook() => {
  'version': 7,
  'activePublicationId': 'published-before-import',
  'components': <PortalRow>[
    {'id': 'quiz', 'name': 'Quiz', 'maxScore': 10},
  ],
  'students': <PortalRow>[
    {
      'studentId': 's1',
      'studentCode': 'SE001',
      'fullName': 'A',
      'grades': {'quiz': 6, 'lab': 9},
      'comment': 'Giữ',
    },
    {
      'studentId': 's2',
      'studentCode': 'SE002',
      'fullName': 'B',
      'grades': {'quiz': 5},
      'comment': '',
    },
  ],
};
GradeExcelSheet sheet(List<List<String>> data) => GradeExcelSheet('Điểm', [
  for (var i = 0; i < data.length; i++)
    GradeExcelRow(i + 1, data[i].map((v) => GradeExcelCell(v)).toList()),
]);
ExcelGradePreview preview(
  GradeExcelSheet data, {
  PortalRow? current,
  bool clear = false,
  bool formulas = false,
  int? end,
}) => prepareExcelGradeImport(
  sheet: data,
  headerIndex: data.headerIndex,
  rollColumn: 0,
  mappings: [mapping],
  target: target,
  current: current ?? gradebook(),
  clearBlanks: clear,
  allowCachedFormulas: formulas,
  endRow: end,
);
List<int> workbookXml(String rows, {String styles = '', String shared = ''}) {
  final zip = Archive();
  void add(String path, String xml) =>
      zip.addFile(ArchiveFile(path, utf8.encode(xml).length, utf8.encode(xml)));
  add(
    'xl/workbook.xml',
    '<workbook xmlns:r="r"><sheets><sheet name="Điểm" r:id="a"/><sheet name="Hidden" state="hidden" r:id="b"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships><Relationship Id="a" Target="worksheets/sheet1.xml"/></Relationships>',
  );
  add(
    'xl/worksheets/sheet1.xml',
    '<worksheet><sheetData>$rows</sheetData></worksheet>',
  );
  if (styles.isNotEmpty) add('xl/styles.xml', styles);
  if (shared.isNotEmpty) add('xl/sharedStrings.xml', shared);
  return ZipEncoder().encode(zip);
}

void main() {
  test(
    'new grade component merges alongside existing scores and optional comments',
    () {
      final data = sheet([
        ['MSSV', 'Assignment', 'Nhận xét'],
        ['SE001', '95', 'Tiến bộ'],
      ]);
      final result = prepareExcelGradeImport(
        sheet: data,
        headerIndex: 0,
        rollColumn: 0,
        mappings: [
          const GradeColumnMapping(
            column: 1,
            id: 'asm',
            name: 'Assignment',
            maxScore: 100,
          ),
        ],
        commentColumn: 2,
        target: target,
        current: gradebook(),
      );
      expect(result.canApply, isTrue);
      expect(result.newComponents, 1);
      expect(result.book['components'].length, 2);
      expect(result.book['students'][0]['grades'], {
        'quiz': 6,
        'lab': 9,
        'asm': 95,
      });
      expect(result.book['students'][0]['comment'], 'Tiến bộ');
      expect(result.book['students'][1]['grades'], {'quiz': 5});
    },
  );
  test(
    'zero and comma decimal merge by MSSV without mutating draft or publication',
    () {
      final book = gradebook(), before = jsonEncode(gradebook());
      final result = preview(
        sheet([
          ['MSSV', 'Quiz'],
          [' se001 ', '0'],
          ['SE002', '8,5'],
        ]),
        current: book,
      );
      expect(result.canApply, isTrue);
      expect(result.changes.length, 2);
      expect(result.book['students'][0]['grades'], {'quiz': 0, 'lab': 9});
      expect(result.book['students'][1]['grades']['quiz'], 8.5);
      expect(result.book['students'][0]['studentId'], 's1');
      expect(result.book['activePublicationId'], 'published-before-import');
      expect(result.book['version'], 7);
      expect(jsonEncode(book), before);
    },
  );
  test(
    'partial roster and blank values keep old grades unless explicitly cleared',
    () {
      final data = sheet([
        ['MSSV', 'Quiz'],
        ['SE001', ''],
      ]);
      final kept = preview(data);
      expect(kept.blankCellsKept, 1);
      expect(kept.untouchedStudents, 1);
      expect(kept.canApply, isFalse);
      final cleared = preview(data, clear: true);
      expect(cleared.book['students'][0]['grades']['quiz'], '');
      expect(cleared.book['students'][1]['grades']['quiz'], 5);
      expect(cleared.canApply, isTrue);
    },
  );
  test('unknown, missing and duplicate MSSV block the entire import', () {
    for (final rows in [
      [
        ['SE001', '1'],
        ['se001', '2'],
      ],
      [
        ['SE999', '1'],
      ],
      [
        ['', '1'],
      ],
    ]) {
      final result = preview(
        sheet([
          ['MSSV', 'Quiz'],
          ...rows,
        ]),
      );
      expect(result.errors, isNotEmpty);
      expect(result.canApply, isFalse);
    }
  });
  test('invalid and out-of-range scores are rejected', () {
    for (final value in ['-1', '10.1', 'NaN', 'Infinity', 'tám', '8/10']) {
      expect(
        preview(
          sheet([
            ['MSSV', 'Quiz'],
            ['SE001', value],
          ]),
        ).canApply,
        isFalse,
        reason: value,
      );
    }
  });
  test('footer can be excluded explicitly; header detection skips title', () {
    final data = sheet([
      ['BẢNG ĐIỂM'],
      ['MSSV', 'Quiz'],
      ['SE001', '8'],
      ['Tổng', '8'],
    ]);
    expect(data.headerIndex, 1);
    expect(preview(data).canApply, isFalse);
    expect(preview(data, end: 3).canApply, isTrue);
  });
  test(
    'cached formulas require opt-in, and missing cached value always fails',
    () {
      GradeExcelSheet data(String value) => GradeExcelSheet('Điểm', [
        const GradeExcelRow(1, [
          GradeExcelCell('MSSV'),
          GradeExcelCell('Quiz'),
        ]),
        GradeExcelRow(2, [
          const GradeExcelCell('SE001'),
          GradeExcelCell(value, formula: true, numeric: true),
        ]),
      ]);
      expect(preview(data('8')).canApply, isFalse);
      expect(preview(data('8'), formulas: true).canApply, isTrue);
      expect(preview(data('8'), formulas: true).cachedFormulas, 1);
      expect(preview(data(''), formulas: true).canApply, isFalse);
    },
  );
  test('numeric NaN/Infinity and typed errors never become valid grades', () {
    for (final cell in [
      const GradeExcelCell('NaN', numeric: true),
      const GradeExcelCell('Infinity', numeric: true),
      const GradeExcelCell('1', numeric: true, invalidType: true),
    ]) {
      final data = GradeExcelSheet('Điểm', [
        const GradeExcelRow(1, [
          GradeExcelCell('MSSV'),
          GradeExcelCell('Quiz'),
        ]),
        GradeExcelRow(2, [const GradeExcelCell('SE001'), cell]),
      ]);
      expect(preview(data).canApply, isFalse);
    }
  });
  test('template XLSX roundtrip validates Vietnamese class metadata', () {
    final bytes = ExcelExportService.generateXlsx(
      sheetName: 'Điểm',
      headers: [
        'Học kỳ',
        'Mã môn',
        'Mã lớp',
        'MSSV',
        'Họ tên',
        'Quiz',
        'Nhận xét',
      ],
      rows: [
        ['FA26', 'PRM393', 'SE1848', 'SE001', 'Nguyễn A', '8,5', 'Tốt'],
      ],
    );
    final data = GradeExcelReader.decode(bytes).single;
    ExcelGradePreview check(PortalRow selected) => prepareExcelGradeImport(
      sheet: data,
      headerIndex: 0,
      rollColumn: 3,
      mappings: [
        const GradeColumnMapping(
          column: 5,
          id: 'quiz',
          name: 'Quiz',
          maxScore: 10,
        ),
      ],
      commentColumn: 6,
      target: selected,
      current: gradebook(),
    );
    expect(check(target).canApply, isTrue);
    expect(check(target).book['students'][0]['comment'], 'Tốt');
    for (final key in target.keys) {
      expect(check({...target, key: 'OTHER'}).canApply, isFalse, reason: key);
    }
  });
  test(
    'reader handles shared strings, sparse cells and cached formulas; hides hidden sheets',
    () {
      final data = GradeExcelReader.decode(
        workbookXml(
          '<row r="3"><c r="A3" t="s"><v>0</v></c><c r="C3"><f>4+4</f><v>8</v></c></row>',
          shared: '<sst><si><r><t>SE</t></r><r><t>001</t></r></si></sst>',
        ),
      ).single;
      expect(data.rows.single.number, 3);
      expect(data.rows.single.cell(0).text, 'SE001');
      expect(data.rows.single.cell(1).text, '');
      expect(data.rows.single.cell(2).formula, isTrue);
      expect(data.rows.single.cell(2).text, '8');
    },
  );
  test(
    'reader flags date, percentage, boolean and error cells, allows plain colored number',
    () {
      final data = GradeExcelReader.decode(
        workbookXml(
          '<row r="1"><c r="A1" s="1"><v>8</v></c><c r="B1" s="2"><v>0.8</v></c>'
          '<c r="C1" t="b"><v>1</v></c><c r="D1" t="e"><v>#REF!</v></c>'
          '<c r="E1" s="3"><v>8</v></c><c r="F1" s="1" t="inlineStr"><is><t>SE001</t></is></c></row>',
          styles:
              '<styleSheet><numFmts><numFmt numFmtId="164" formatCode="[Red]0.00"/></numFmts>'
              '<cellXfs><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="9"/><xf numFmtId="164"/></cellXfs></styleSheet>',
        ),
      ).single.rows.single;
      expect(data.cells.take(4).every((c) => c.invalidType), isTrue);
      expect(data.cell(4).invalidType, isFalse);
      expect(data.cell(5).invalidType, isFalse);
    },
  );
  test('reader reports malformed files and oversized worksheet bounds', () {
    expect(
      () => GradeExcelReader.decode([1, 2, 3]),
      throwsA(isA<AppException>()),
    );
    expect(
      () => GradeExcelReader.decode(
        workbookXml('<row r="20001"><c r="A20001"><v>1</v></c></row>'),
      ),
      throwsA(isA<AppException>()),
    );
  });
  test('mapping collisions and changes to existing scale are rejected', () {
    final data = sheet([
      ['MSSV', 'Quiz', 'Lab'],
      ['SE001', '8', '9'],
    ]);
    for (final mappings in [
      [
        mapping,
        const GradeColumnMapping(
          column: 2,
          id: 'quiz',
          name: 'Quiz',
          maxScore: 10,
        ),
      ],
      [
        const GradeColumnMapping(
          column: 1,
          id: 'quiz',
          name: 'Quiz',
          maxScore: 100,
        ),
      ],
      [
        const GradeColumnMapping(
          column: 1,
          id: 'new',
          name: 'Quiz',
          maxScore: 10,
        ),
      ],
    ]) {
      expect(
        () => prepareExcelGradeImport(
          sheet: data,
          headerIndex: 0,
          rollColumn: 0,
          mappings: mappings,
          target: target,
          current: gradebook(),
        ),
        throwsA(isA<AppException>()),
      );
    }
  });
}

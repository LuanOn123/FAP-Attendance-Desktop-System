import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/services/markbook_reader.dart';

List<int> zipped(Map<String, String> parts) {
  final archive = Archive();
  for (final e in parts.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  test(
    'ODS reads class column independently of incomplete sheet name and skips grades',
    () {
      final bytes = zipped({
        'content.xml':
            '''<office:document xmlns:office="o" xmlns:table="t" xmlns:text="x">
      <table:table table:name="23_PRM232"><table:table-row>
      <table:table-cell><text:p>Class</text:p></table:table-cell><table:table-cell><text:p>RollNumber</text:p></table:table-cell>
      <table:table-cell><text:p>Email</text:p></table:table-cell><table:table-cell><text:p>MemberCode</text:p></table:table-cell>
      <table:table-cell><text:p>FullName</text:p></table:table-cell><table:table-cell><text:p>Grade</text:p></table:table-cell>
      </table:table-row><table:table-row>
      <table:table-cell><text:p> se1922 </text:p></table:table-cell><table:table-cell><text:p>se000001</text:p></table:table-cell>
      <table:table-cell table:number-columns-repeated="2"/><table:table-cell><text:p>Nguyễn Văn A</text:p></table:table-cell>
      <table:table-cell><text:p>9.5</text:p></table:table-cell></table:table-row>
      <table:table-row table:number-rows-repeated="999999"><table:table-cell table:number-columns-repeated="999999"/></table:table-row>
      </table:table></office:document>''',
      });
      final book = MarkbookReader.decode(bytes, 'FA26_Markbook.ods');
      expect(book.semesterHint, 'FA26');
      expect(book.sheets.single.subjectHint, 'PRM232');
      final s = book.sheets.single.students.single;
      expect(s.classCode, 'SE1922');
      expect(s.studentCode, 'SE000001');
      expect(s.fullName, 'Nguyễn Văn A');
      expect(s.email, '');
      expect(book.sheets.single.errors, isEmpty);
    },
  );
  test(
    'XLSX supports relationships, shared strings, inline strings and sparse cells',
    () {
      final bytes = zipped({
        'xl/workbook.xml':
            '<workbook xmlns:r="r"><sheets><sheet name="11_PRN232_SE1917" r:id="r1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>',
        'xl/sharedStrings.xml':
            '<sst><si><t>Class</t></si><si><t>RollNumber</t></si><si><t>FullName</t></si><si><t>SE1917</t></si></sst>',
        'xl/worksheets/sheet1.xml': '''<worksheet><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="E1" t="s"><v>2</v></c></row>
        <row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="inlineStr"><is><t>SE000001</t></is></c>
        <c r="E2" t="inlineStr"><is><r><t>Nguyễn </t></r><r><t>Văn A</t></r></is></c></row>
        </sheetData></worksheet>''',
      });
      final sheet = MarkbookReader.decode(bytes, 'FA26.xlsx').sheets.single;
      expect(sheet.errors, isEmpty);
      expect(sheet.subjectHint, 'PRN232');
      expect(sheet.students.single.fullName, 'Nguyễn Văn A');
      expect(sheet.students.single.studentCode, 'SE000001');
    },
  );
  test(
    'Duplicate rows are consolidated, conflicting identities block import',
    () {
      const header = ['Class', 'RollNumber', 'FullName', 'Email'];
      const row = ['SE1917', 'SE000001', 'A', 'a@example.com'];
      var sheet = MarkbookReader.parseRows('Sheet1', [header, row, row]);
      expect(sheet.students.length, 1);
      expect(sheet.duplicates, 1);
      expect(sheet.errors, isEmpty);
      sheet = MarkbookReader.parseRows('Sheet1', [
        header,
        row,
        ['SE1917', 'SE000001', 'B', 'b@example.com'],
      ]);
      expect(sheet.errors, isNotEmpty);
      expect(
        MarkbookReader.parseRows('No students', [
          ['Grade'],
        ]).errors,
        isNotEmpty,
      );
      expect(
        MarkbookReader.parseRows('Invalid', [
          header,
          ['SE1917', '', 'A', ''],
        ]).errors,
        isNotEmpty,
      );
    },
  );
}

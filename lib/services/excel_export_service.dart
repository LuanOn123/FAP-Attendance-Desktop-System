import 'dart:convert';
import 'package:archive/archive.dart';

class ExcelExportService {
  /// Generates a valid standard Excel (.xlsx) file bytes from headers and row data.
  static List<int> generateXlsx({
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';
    _addFile(archive, '[Content_Types].xml', contentTypesXml);

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
    _addFile(archive, '_rels/.rels', rootRelsXml);

    // 3. xl/_rels/workbook.xml.rels
    const wbRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';
    _addFile(archive, 'xl/_rels/workbook.xml.rels', wbRelsXml);

    // 4. xl/workbook.xml
    final escapedSheetName = _escapeXml(
      sheetName.replaceAll(RegExp(r'[\\/?*\[\]:]'), '_'),
    );
    final wbXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="$escapedSheetName" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''';
    _addFile(archive, 'xl/workbook.xml', wbXml);

    // 5. xl/styles.xml
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill fillType="none"/></fill>
    <fill><patternFill fillType="gray125"/></fill>
    <fill><patternFill fillType="solid"><fgColor rgb="FFE05615"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD3D3D3"/></left>
      <right style="thin"><color rgb="FFD3D3D3"/></right>
      <top style="thin"><color rgb="FFD3D3D3"/></top>
      <bottom style="thin"><color rgb="FFD3D3D3"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
  </cellXfs>
</styleSheet>''';
    _addFile(archive, 'xl/styles.xml', stylesXml);

    // 6. xl/worksheets/sheet1.xml
    final sheetBuf = StringBuffer();
    sheetBuf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sheetBuf.writeln('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    sheetBuf.writeln('  <sheetData>');

    // Header row (row 1, style 1: bold white on orange, border)
    sheetBuf.writeln('    <row r="1">');
    for (int col = 0; col < headers.length; col++) {
      final colLetter = _colToLetter(col);
      final val = _escapeXml(headers[col]);
      sheetBuf.writeln('      <c r="${colLetter}1" s="1" t="inlineStr"><is><t>$val</t></is></c>');
    }
    sheetBuf.writeln('    </row>');

    // Data rows (row 2+, style 2: normal with border)
    for (int rIdx = 0; rIdx < rows.length; rIdx++) {
      final rowNum = rIdx + 2;
      final rowData = rows[rIdx];
      sheetBuf.writeln('    <row r="$rowNum">');
      for (int col = 0; col < rowData.length; col++) {
        final colLetter = _colToLetter(col);
        final val = _escapeXml(rowData[col]);
        sheetBuf.writeln('      <c r="$colLetter$rowNum" s="2" t="inlineStr"><is><t>$val</t></is></c>');
      }
      sheetBuf.writeln('    </row>');
    }

    sheetBuf.writeln('  </sheetData>');
    sheetBuf.writeln('</worksheet>');

    _addFile(archive, 'xl/worksheets/sheet1.xml', sheetBuf.toString());

    return ZipEncoder().encode(archive);
  }

  static void _addFile(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static String _colToLetter(int colIndex) {
    var result = '';
    var c = colIndex;
    while (c >= 0) {
      result = String.fromCharCode((c % 26) + 65) + result;
      c = (c ~/ 26) - 1;
    }
    return result;
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

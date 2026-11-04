import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../core/app_config.dart';
import '../repositories/student_portal_repository.dart';

class GradeExcelCell {
  final String text;
  final bool formula, numeric, invalidType;
  const GradeExcelCell(
    this.text, {
    this.formula = false,
    this.numeric = false,
    this.invalidType = false,
  });
}

class GradeExcelRow {
  final int number;
  final List<GradeExcelCell> cells;
  const GradeExcelRow(this.number, this.cells);
  GradeExcelCell cell(int index) => index >= 0 && index < cells.length
      ? cells[index]
      : const GradeExcelCell('');
}

class GradeExcelSheet {
  final String name;
  final List<GradeExcelRow> rows;
  const GradeExcelSheet(this.name, this.rows);
  int get headerIndex {
    final found = rows
        .take(50)
        .toList()
        .indexWhere(
          (r) => r.cells.any(
            (c) => gradeRollHeaders.contains(gradeHeader(c.text)),
          ),
        );
    return found < 0 ? 0 : found;
  }
}

String gradeHeader(String value) {
  var text = value.trim().toLowerCase();
  const accents = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  for (final entry in accents.entries) {
    for (final rune in entry.value.runes) {
      text = text.replaceAll(String.fromCharCode(rune), entry.key);
    }
  }
  return text.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

const gradeRollHeaders = {
  'mssv',
  'masinhvien',
  'studentcode',
  'studentid',
  'rollnumber',
  'rollno',
  'roll',
};
const gradeMetadataHeaders = {
  'semester': 'semester',
  'term': 'semester',
  'hocky': 'semester',
  'subjectcode': 'subjectCode',
  'subject': 'subjectCode',
  'coursecode': 'subjectCode',
  'mamon': 'subjectCode',
  'monhoc': 'subjectCode',
  'classcode': 'classCode',
  'class': 'classCode',
  'malop': 'classCode',
  'lop': 'classCode',
};

class GradeExcelReader {
  static Future<List<GradeExcelSheet>> read(String path) async {
    try {
      if (!path.toLowerCase().endsWith('.xlsx')) {
        throw const AppException(
          'Chọn file .xlsx. Với .xls, dùng Save As → .xlsx trong Excel.',
        );
      }
      if (await File(path).length() > 20 * 1024 * 1024) {
        throw const AppException('File Excel tối đa 20 MB.');
      }
      return await Isolate.run(() => decode(File(path).readAsBytesSync()));
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Không đọc được Excel. Lưu và đóng file, bỏ mật khẩu rồi chọn lại bản .xlsx.',
      );
    }
  }

  static List<GradeExcelSheet> decode(List<int> bytes) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const AppException('File Excel tối đa 20 MB.');
    }
    try {
      final zip = ZipDecoder().decodeBytes(bytes);
      if (zip.files.fold<int>(0, (n, f) => n + f.size) > 100 * 1024 * 1024) {
        throw const AppException(
          'Nội dung Excel quá lớn. Tách từng lớp thành file riêng.',
        );
      }
      XmlDocument xml(String path) {
        final file = zip.findFile(path);
        if (file == null) {
          throw const AppException('Excel thiếu dữ liệu workbook hoặc sheet.');
        }
        return XmlDocument.parse(utf8.decode(file.content));
      }

      final strings = zip.findFile('xl/sharedStrings.xml') == null
          ? <String>[]
          : _elements(xml('xl/sharedStrings.xml'), 'si')
                .map((s) => _elements(s, 't').map((t) => t.innerText).join())
                .toList();
      final forbiddenStyles = <int>{};
      if (zip.findFile('xl/styles.xml') != null) {
        final styles = xml('xl/styles.xml');
        final formats = {
          for (final f in _elements(styles, 'numFmt'))
            int.tryParse(_attr(f, 'numFmtId')): _attr(f, 'formatCode'),
        };
        final xfs =
            _elements(styles, 'cellXfs').firstOrNull?.childElements
                .where((e) => e.name.local == 'xf')
                .toList() ??
            <XmlElement>[];
        for (var i = 0; i < xfs.length; i++) {
          final id = int.tryParse(_attr(xfs[i], 'numFmtId')) ?? 0;
          final format = (formats[id] ?? '')
              .replaceAll(RegExp(r'"[^"]*"|\\.'), '')
              .replaceAll(
                RegExp(r'\[(?![hms]+\])[^\]]*\]', caseSensitive: false),
                '',
              );
          if ((id >= 14 && id <= 22) ||
              (id >= 27 && id <= 36) ||
              (id >= 45 && id <= 47) ||
              (id >= 50 && id <= 58) ||
              id == 9 ||
              id == 10 ||
              RegExp(r'[dymhs%]', caseSensitive: false).hasMatch(format)) {
            forbiddenStyles.add(i);
          }
        }
      }
      final relations = {
        for (final r in _elements(
          xml('xl/_rels/workbook.xml.rels'),
          'Relationship',
        ))
          _attr(r, 'Id'): r,
      };
      final result = <GradeExcelSheet>[];
      for (final sheet in _elements(xml('xl/workbook.xml'), 'sheet')) {
        if (['hidden', 'veryHidden'].contains(_attr(sheet, 'state'))) continue;
        final rel = relations[_attr(sheet, 'id')];
        if (rel == null || _attr(rel, 'TargetMode') == 'External') continue;
        final target = Uri.parse(
          'xl/workbook.xml',
        ).resolve(_attr(rel, 'Target')).path.replaceFirst(RegExp(r'^/'), '');
        if (!target.startsWith('xl/worksheets/')) continue;
        final rows = <GradeExcelRow>[];
        var previousRow = 0;
        for (final row in _elements(xml(target), 'row')) {
          final number = int.tryParse(_attr(row, 'r')) ?? previousRow + 1;
          previousRow = number;
          if (number < 1 || number > 20000 || rows.length >= 20000) {
            throw const AppException('Sheet vượt giới hạn 20000 dòng.');
          }
          final cells = <GradeExcelCell>[];
          for (final cell in row.childElements.where(
            (e) => e.name.local == 'c',
          )) {
            final letters =
                RegExp(r'^[A-Za-z]+').stringMatch(_attr(cell, 'r')) ?? '';
            var column = 0;
            for (final c in letters.toUpperCase().codeUnits) {
              column = column * 26 + c - 64;
            }
            if (column == 0) column = cells.length + 1;
            if (column > 256) {
              throw const AppException('Sheet vượt giới hạn 256 cột.');
            }
            while (cells.length < column) {
              cells.add(const GradeExcelCell(''));
            }
            final type = _attr(cell, 't'),
                raw = _elements(cell, 'v').map((v) => v.innerText).join();
            String value = raw;
            if (type == 's') {
              final index = int.tryParse(raw);
              if (index == null || index < 0 || index >= strings.length) {
                throw const AppException(
                  'Excel có shared string không hợp lệ.',
                );
              }
              value = strings[index];
            } else if (type == 'inlineStr') {
              value = _elements(cell, 't').map((t) => t.innerText).join();
            }
            cells[column - 1] = GradeExcelCell(
              value.trim(),
              formula: _elements(cell, 'f').isNotEmpty,
              numeric: type.isEmpty || type == 'n',
              invalidType:
                  ['e', 'b', 'd'].contains(type) ||
                  ((type.isEmpty || type == 'n') &&
                      forbiddenStyles.contains(
                        int.tryParse(_attr(cell, 's')) ?? 0,
                      )),
            );
          }
          if (cells.any((c) => c.text.isNotEmpty || c.formula)) {
            rows.add(GradeExcelRow(number, cells));
          }
        }
        if (rows.isNotEmpty) {
          result.add(GradeExcelSheet(_attr(sheet, 'name'), rows));
        }
      }
      if (result.isEmpty) {
        throw const AppException(
          'Không có sheet dữ liệu hiển thị trong Excel.',
        );
      }
      return result;
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'File Excel lỗi hoặc có mật khẩu. Lưu lại dưới dạng .xlsx rồi chọn lại.',
      );
    }
  }

  static Iterable<XmlElement> _elements(XmlNode node, String name) => node
      .descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);
  static String _attr(XmlElement element, String name) =>
      element.attributes
          .where((a) => a.name.local == name)
          .map((a) => a.value)
          .firstOrNull ??
      '';
}

class GradeColumnMapping {
  final int column;
  final String id, name;
  final num maxScore;
  const GradeColumnMapping({
    required this.column,
    required this.id,
    required this.name,
    required this.maxScore,
  });
}

class ExcelGradePreview {
  final PortalRow book;
  final List<String> errors;
  final List<PortalRow> changes;
  final int matchedStudents,
      untouchedStudents,
      blankCellsKept,
      cachedFormulas,
      newComponents;
  const ExcelGradePreview({
    required this.book,
    required this.errors,
    required this.changes,
    required this.matchedStudents,
    required this.untouchedStudents,
    required this.blankCellsKept,
    required this.cachedFormulas,
    required this.newComponents,
  });
  bool get canApply =>
      errors.isEmpty &&
      (changes.isNotEmpty || newComponents > 0) &&
      matchedStudents > 0;
}

ExcelGradePreview prepareExcelGradeImport({
  required GradeExcelSheet sheet,
  required int headerIndex,
  required int rollColumn,
  required List<GradeColumnMapping> mappings,
  required PortalRow target,
  required PortalRow current,
  int? endRow,
  int? commentColumn,
  bool clearBlanks = false,
  bool allowCachedFormulas = false,
}) {
  if (headerIndex < 0 ||
      headerIndex >= sheet.rows.length ||
      rollColumn < 0 ||
      mappings.isEmpty) {
    throw const AppException(
      'Chọn dòng tiêu đề, cột MSSV và ít nhất một cột điểm.',
    );
  }
  final headers = sheet.rows[headerIndex],
      components = (current['components'] as List)
          .map((c) => PortalRow.from(c as Map))
          .toList();
  if (rollColumn >= headers.cells.length) {
    throw const AppException('Cột MSSV không hợp lệ.');
  }
  final ids = components.map((c) => c['id']).toSet(),
      targets = <String>{},
      columns = <int>{};
  var newComponents = 0;
  for (final m in mappings) {
    if (m.column < 0 ||
        m.column >= headers.cells.length ||
        m.column == rollColumn ||
        m.column == commentColumn ||
        !columns.add(m.column) ||
        !targets.add(m.id)) {
      throw const AppException(
        'Cột điểm bị trùng hoặc trùng cột MSSV/nhận xét.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(m.id) ||
        ['__proto__', 'prototype', 'constructor'].contains(m.id) ||
        m.name.trim().isEmpty ||
        m.name.length > 100 ||
        !m.maxScore.isFinite ||
        m.maxScore <= 0 ||
        m.maxScore > 1000) {
      throw const AppException('Tên hoặc thang điểm của cột không hợp lệ.');
    }
    if (ids.contains(m.id)) {
      final existing = components.singleWhere((c) => c['id'] == m.id);
      if (existing['maxScore'] != m.maxScore || existing['name'] != m.name) {
        throw const AppException(
          'Thang điểm đã thay đổi. Chọn lại cột điểm hiện tại.',
        );
      }
    } else {
      if (components.any(
        (c) => gradeHeader('${c['name']}') == gradeHeader(m.name),
      )) {
        throw const AppException('Tên cột điểm mới trùng với cột hiện tại.');
      }
      components.add({
        'id': m.id,
        'name': m.name.trim(),
        'maxScore': m.maxScore,
      });
      ids.add(m.id);
      newComponents++;
    }
  }
  if (components.length > 30) {
    throw const AppException('Bảng điểm tối đa 30 cột.');
  }
  if (commentColumn != null &&
      (commentColumn < 0 ||
          commentColumn >= headers.cells.length ||
          commentColumn == rollColumn)) {
    throw const AppException('Cột nhận xét không hợp lệ.');
  }
  if (endRow != null &&
      (endRow <= headers.number || endRow > sheet.rows.last.number)) {
    throw const AppException(
      'Dòng kết thúc phải sau tiêu đề và nằm trong sheet.',
    );
  }
  final students = (current['students'] as List)
      .map(
        (s) => {
          ...PortalRow.from(s as Map),
          'grades': PortalRow.from(s['grades'] as Map),
        },
      )
      .toList();
  final roster = <String, PortalRow>{};
  for (final student in students) {
    final code = '${student['studentCode']}'.trim().toUpperCase();
    if (code.isEmpty || roster.containsKey(code)) {
      throw const AppException(
        'Danh sách lớp có MSSV trống hoặc trùng. Kiểm tra roster trước khi nhập điểm.',
      );
    }
    roster[code] = student;
  }
  final metadata = <int, String>{};
  for (var i = 0; i < headers.cells.length; i++) {
    final key = gradeMetadataHeaders[gradeHeader(headers.cell(i).text)];
    if (key != null) {
      if (metadata.containsValue(key)) {
        throw const AppException('Cột lớp/môn/học kỳ bị trùng trong file.');
      }
      metadata[i] = key;
    }
  }
  if (columns.any(metadata.containsKey) || metadata.containsKey(rollColumn)) {
    throw const AppException(
      'Cột thông tin lớp/môn/học kỳ không phải cột điểm hoặc MSSV.',
    );
  }
  final errors = <String>[], changes = <PortalRow>[], seen = <String>{};
  var matched = 0, blankKept = 0, formulas = 0;
  void error(String message) {
    if (errors.length < 100) errors.add(message);
  }

  for (final row
      in sheet.rows
          .skip(headerIndex + 1)
          .where((r) => endRow == null || r.number <= endRow)) {
    final codeCell = row.cell(rollColumn),
        code = codeCell.text.trim().toUpperCase();
    if (row.cells.every((c) => c.text.isEmpty && !c.formula)) continue;
    final label = 'Dòng ${row.number}${code.isEmpty ? '' : ' · $code'}';
    if (codeCell.formula || codeCell.invalidType || code.isEmpty) {
      error('$label: MSSV trống hoặc không phải giá trị cố định.');
      continue;
    }
    if (!seen.add(code)) {
      error('$label: MSSV bị lặp trong file.');
      continue;
    }
    final student = roster[code];
    if (student == null) {
      error('$label: không thuộc lớp đang chọn.');
      continue;
    }
    var wrongClass = false;
    for (final entry in metadata.entries) {
      final cell = row.cell(entry.key);
      if (cell.formula ||
          cell.text.trim().toUpperCase() !=
              '${target[entry.value]}'.trim().toUpperCase()) {
        error(
          '$label: ${headers.cell(entry.key).text} không khớp lớp/môn/học kỳ đang chọn.',
        );
        wrongClass = true;
      }
    }
    if (wrongClass) continue;
    matched++;
    for (final mapping in mappings) {
      final cell = row.cell(mapping.column), value = cell.text.trim();
      if (cell.formula) {
        if (!allowCachedFormulas || value.isEmpty) {
          error(
            '$label / ${mapping.name}: có công thức; cần lưu kết quả trong Excel và cho phép dùng giá trị đã lưu.',
          );
          continue;
        }
        formulas++;
      }
      final grades = student['grades'] as Map, old = grades[mapping.id] ?? '';
      if (value.isEmpty) {
        if (!clearBlanks) {
          blankKept++;
          continue;
        }
        if (old != '') {
          grades[mapping.id] = '';
          changes.add({
            'studentCode': code,
            'column': mapping.name,
            'old': old,
            'new': '',
          });
        }
        continue;
      }
      if (cell.invalidType) {
        error(
          '$label / ${mapping.name}: ô lỗi, ngày, phần trăm hoặc boolean; đổi sang điểm số.',
        );
        continue;
      }
      final valid =
          cell.numeric || RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(value);
      final number = valid
          ? num.tryParse(cell.numeric ? value : value.replaceAll(',', '.'))
          : null;
      if (number == null ||
          !number.isFinite ||
          number < 0 ||
          number > mapping.maxScore) {
        error(
          '$label / ${mapping.name}: "$value" ngoài thang 0–${mapping.maxScore}.',
        );
        continue;
      }
      if (old != number) {
        grades[mapping.id] = number;
        changes.add({
          'studentCode': code,
          'column': mapping.name,
          'old': old,
          'new': number,
        });
      }
    }
    if (commentColumn != null) {
      final cell = row.cell(commentColumn), value = cell.text;
      if (cell.formula || cell.invalidType || value.length > 1000) {
        error('$label: nhận xét không hợp lệ hoặc quá 1000 ký tự.');
      } else if ((value.isNotEmpty || clearBlanks) &&
          value != (student['comment'] ?? '')) {
        changes.add({
          'studentCode': code,
          'column': 'Nhận xét',
          'old': student['comment'] ?? '',
          'new': value,
        });
        student['comment'] = value;
      }
    }
  }
  if (matched == 0) error('Không có sinh viên hợp lệ để nhập.');
  return ExcelGradePreview(
    book: {...current, 'components': components, 'students': students},
    errors: errors,
    changes: changes,
    matchedStudents: matched,
    untouchedStudents: students.length - matched,
    blankCellsKept: blankKept,
    cachedFormulas: formulas,
    newComponents: newComponents,
  );
}

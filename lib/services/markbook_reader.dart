import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../core/app_config.dart';
import '../models/roster.dart';
import '../models/schedule.dart';

class MarkbookSheet {
  final String name, subjectHint;
  final List<RosterStudent> students;
  final List<String> errors;
  final int duplicates;
  const MarkbookSheet(
    this.name,
    this.subjectHint,
    this.students,
    this.errors,
    this.duplicates,
  );
}

class Markbook {
  final String semesterHint;
  final List<MarkbookSheet> sheets;
  const Markbook(this.semesterHint, this.sheets);
}

class MarkbookReader {
  static Future<Markbook> read(String path) async {
    try {
      final file = File(path);
      if (await file.length() > 20 * 1024 * 1024) {
        throw const AppException('File lớn hơn 20 MB.');
      }
      return await Isolate.run(
        () => decode(File(path).readAsBytesSync(), path),
      );
    } on AppException {
      rethrow;
    } on FileSystemException {
      throw const AppException(
        'Không đọc được file. Hãy lưu và đóng file trong Excel rồi chọn lại.',
      );
    } catch (_) {
      throw const AppException(
        'File không hợp lệ hoặc có mật khẩu. Hãy lưu lại dưới dạng .xlsx hoặc .ods.',
      );
    }
  }

  static Markbook decode(List<int> bytes, String filename) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const AppException('File lớn hơn 20 MB.');
    }
    final sheets = <MarkbookSheet>[];
    try {
      final zip = ZipDecoder().decodeBytes(bytes);
      if (zip.files.fold<int>(0, (sum, f) => sum + f.size) > 100 * 1024 * 1024) {
        throw const AppException(
          'Nội dung file quá lớn. Hãy tách từng lớp thành file riêng.',
        );
      }
      XmlDocument xml(String name) {
        final f = zip.findFile(name);
        if (f == null) throw AppException('Thiếu dữ liệu bảng tính: $name');
        return XmlDocument.parse(utf8.decode(f.content));
      }

      if (zip.findFile('content.xml') != null) {
        for (final table in elements(xml('content.xml'), 'table')) {
          final rows = <List<String>>[];
          for (final row in elements(table, 'table-row')) {
            final cells = <String>[];
            for (final cell in row.childElements.where(
              (c) => ['table-cell', 'covered-table-cell'].contains(c.name.local),
            )) {
              final value = elements(
                cell,
                'p',
              ).map((p) => p.innerText).join(' ').trim();
              final count =
                  int.tryParse(attr(cell, 'number-columns-repeated')) ?? 1;
              for (var n = 0; n < count && cells.length < 256; n++) {
                cells.add(value);
              }
            }
            if (cells.every((v) => v.isEmpty)) continue;
            final repeats = int.tryParse(attr(row, 'number-rows-repeated')) ?? 1;
            if (rows.length + repeats > 20000) {
              throw const AppException('Sheet có quá nhiều dòng.');
            }
            for (var n = 0; n < repeats; n++) {
              rows.add(cells);
            }
          }
          sheets.add(parseRows(attr(table, 'name'), rows));
        }
      } else if (zip.findFile('xl/workbook.xml') != null) {
        final strings = zip.findFile('xl/sharedStrings.xml') == null
            ? <String>[]
            : elements(xml('xl/sharedStrings.xml'), 'si')
                  .map((s) => elements(s, 't').map((t) => t.innerText).join())
                  .toList();
        final rels = {
          for (final r in elements(
            xml('xl/_rels/workbook.xml.rels'),
            'Relationship',
          ))
            attr(r, 'Id'): attr(r, 'Target'),
        };
        for (final sheet in elements(xml('xl/workbook.xml'), 'sheet')) {
          final target = rels[attr(sheet, 'id')];
          if (target == null) {
            throw const AppException('Không tìm thấy sheet trong Excel.');
          }
          final name = Uri.parse(
            'xl/workbook.xml',
          ).resolve(target).path.replaceFirst(RegExp(r'^/'), '');
          final rows = <List<String>>[];
          for (final row in elements(xml(name), 'row')) {
            final cells = <String>[];
            for (final c in row.childElements.where((e) => e.name.local == 'c')) {
              var col = 0;
              final ref = RegExp(r'^[A-Z]+').stringMatch(attr(c, 'r')) ?? '';
              for (final char in ref.codeUnits) {
                col = col * 26 + char - 64;
              }
              if (col == 0) col = cells.length + 1;
              if (col > 256) continue;
              while (cells.length < col) {
                cells.add('');
              }
              final value = elements(c, 'v').map((e) => e.innerText).join();
              final type = attr(c, 't');
              final idx = int.tryParse(value);
              cells[col - 1] = type == 's'
                  ? (idx != null && idx >= 0 && idx < strings.length
                        ? strings[idx]
                        : '')
                  : type == 'inlineStr'
                  ? elements(c, 't').map((e) => e.innerText).join()
                  : value;
            }
            if (cells.any((v) => v.trim().isNotEmpty)) rows.add(cells);
            if (rows.length > 20000) {
              throw const AppException('Sheet có quá nhiều dòng.');
            }
          }
          sheets.add(parseRows(attr(sheet, 'name'), rows));
        }
      } else {
        throw const AppException(
          'Chỉ hỗ trợ Excel .xlsx, OpenDocument .ods và .csv. Với .xls hãy Save As .xlsx.',
        );
      }
    } catch (e) {
      if (e is AppException) rethrow;
      if (filename.toLowerCase().endsWith('.csv') ||
          !filename.toLowerCase().endsWith('.xlsx') &&
              !filename.toLowerCase().endsWith('.ods')) {
        try {
          final content = utf8.decode(bytes, allowMalformed: true);
          final lines = const LineSplitter().convert(content);
          final rows = <List<String>>[];
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            final delimiter = line.contains(';') && !line.contains(',') ? ';' : ',';
            final cells = line.split(delimiter).map((c) => c.trim().replaceAll(RegExp(r'^"|"€'), '')).toList();
            if (cells.any((v) => v.isNotEmpty)) rows.add(cells);
          }
          if (rows.isNotEmpty) {
            final sheetName = filename.replaceAll('\\', '/').split('/').last;
            sheets.add(parseRows(sheetName, rows));
          }
        } catch (_) {
          throw const AppException('File CSV không hợp lệ hoặc lỗi mã hóa UTF-8.');
        }
      } else {
        throw const AppException(
          'Chỉ hỗ trợ Excel .xlsx, OpenDocument .ods và .csv. Với .xls hãy Save As .xlsx.',
        );
      }
    }
    if (sheets.isEmpty) throw const AppException('File không có sheet.');
    final base = filename.replaceAll('\\', '/').split('/').last.toUpperCase();
    return Markbook(
      RegExp(r'(?:FA|SP|SU)\d{2,4}').stringMatch(base) ?? '',
      sheets,
    );
  }

  static Iterable<XmlElement> elements(XmlNode node, String name) => node
      .descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);
  static String attr(XmlElement node, String name) =>
      node.attributes
          .where((a) => a.name.local == name)
          .map((a) => a.value)
          .firstOrNull ??
      '';

  static MarkbookSheet parseRows(String name, List<List<String>> rows) {
    String header(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '');
    final index = rows.indexWhere(
      (r) =>
          r.map(header).contains('class') &&
          r.map(header).contains('rollnumber') &&
          r.map(header).contains('fullname'),
    );
    final hint =
        RegExp(
          r'(?:^|_)([A-Z]{2,6}\d{3})(?:_|$)',
        ).firstMatch(name.toUpperCase())?.group(1) ??
        '';
    if (index < 0) {
      return MarkbookSheet(name, hint, [], [
        'Thiếu cột Class, RollNumber hoặc FullName.',
      ], 0);
    }
    final headers = rows[index].map(header).toList();
    final ci = headers.indexOf('class'),
        si = headers.indexOf('rollnumber'),
        ni = headers.indexOf('fullname'),
        ei = headers.indexOf('email');
    final students = <String, RosterStudent>{};
    final errors = <String>[];
    var duplicates = 0;
    for (var i = index + 1; i < rows.length; i++) {
      String value(int c) =>
          c < 0 || c >= rows[i].length ? '' : rows[i][c].trim();
      if ([value(ci), value(si), value(ni)].every((v) => v.isEmpty)) continue;
      if (header(value(si)) == 'rollnumber') continue;
      final classCode = normalizeCode(value(ci)),
          code = normalizeCode(value(si));
      if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]{1,39}$').hasMatch(classCode) ||
          !RegExp(r'^[A-Z0-9][A-Z0-9._-]{1,39}$').hasMatch(code) ||
          value(ni).isEmpty ||
          value(ni).length > 200) {
        errors.add(
          'Dòng ${i + 1}: mã lớp, mã sinh viên hoặc họ tên không hợp lệ.',
        );
        continue;
      }
      final email = value(ei).toLowerCase();
      if (email.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        errors.add('Dòng ${i + 1}: email không hợp lệ.');
        continue;
      }
      final student = RosterStudent(
        classCode: classCode,
        studentCode: code,
        fullName: value(ni),
        email: email,
      );
      final key = '$classCode|$code';
      if (students.containsKey(key)) {
        final old = students[key]!;
        if (old.fullName != student.fullName || old.email != student.email) {
          errors.add('Dòng ${i + 1}: cùng mã sinh viên nhưng khác thông tin.');
        } else {
          duplicates++;
        }
      } else {
        students[key] = student;
      }
    }
    return MarkbookSheet(
      name,
      hint,
      students.values.toList(),
      errors,
      duplicates,
    );
  }
}

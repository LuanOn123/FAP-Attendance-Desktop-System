import '../core/app_config.dart';
import '../repositories/student_portal_repository.dart';

/// Pure validation/mapping. Never writes or publishes imported grades.
PortalRow preparePortalGradeImport(
  PortalRow input,
  PortalRow target,
  PortalRow current,
) {
  if (input['schemaVersion'] != 1 || input['classes'] is! List) {
    throw const AppException(
      'File không đúng định dạng portal schemaVersion 1.',
    );
  }
  String code(dynamic v) => '$v'.trim().toUpperCase();
  final matches = (input['classes'] as List)
      .whereType<Map>()
      .where(
        (c) => [
          'semester',
          'subjectCode',
          'classCode',
        ].every((k) => code(c[k]) == code(target[k])),
      )
      .toList();
  if (matches.length != 1) {
    throw const AppException(
      'Không tìm thấy duy nhất lớp/môn/học kỳ đang chọn trong file.',
    );
  }
  final source = matches.single;
  if (source['components'] is! List || source['students'] is! List) {
    throw const AppException('File thiếu cột điểm hoặc sinh viên.');
  }
  final components = (source['components'] as List)
      .map((c) => PortalRow.from(c as Map))
      .toList();
  if (components.isEmpty || components.length > 30) {
    throw const AppException('Cần từ 1 đến 30 cột điểm.');
  }
  final ids = <String>{}, names = <String>{};
  for (final c in components) {
    if (c['id'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(c['id'] as String) ||
        !ids.add(c['id'] as String) ||
        c['name'] is! String ||
        (c['name'] as String).trim().isEmpty ||
        (c['name'] as String).length > 100 ||
        !names.add((c['name'] as String).trim()) ||
        c['maxScore'] is! num ||
        !(c['maxScore'] as num).isFinite ||
        (c['maxScore'] as num) <= 0 ||
        (c['maxScore'] as num) > 1000) {
      throw const AppException(
        'Cột điểm không hợp lệ, trùng tên hoặc trùng ID.',
      );
    }
  }
  final byCode = <String, PortalRow>{};
  for (final item in source['students'] as List) {
    final row = PortalRow.from(item as Map), roll = code(item['studentCode']);
    if (roll.isEmpty || byCode.containsKey(roll)) {
      throw const AppException('File có MSSV trống hoặc trùng.');
    }
    byCode[roll] = row;
  }
  final roster = (current['students'] as List)
      .map((s) => PortalRow.from(s as Map))
      .toList();
  final rosterCodes = roster.map((s) => code(s['studentCode'])).toSet();
  final missing = rosterCodes.difference(byCode.keys.toSet()),
      unknown = byCode.keys.toSet().difference(rosterCodes);
  if (missing.isNotEmpty || unknown.isNotEmpty) {
    throw AppException(
      'Danh sách chưa khớp. Thiếu trong file: ${missing.take(5).join(', ')}. Không thuộc lớp: ${unknown.take(5).join(', ')}. Cập nhật danh sách hoặc file rồi nhập lại.',
    );
  }
  final students = roster.map((s) {
    final row = byCode[code(s['studentCode'])]!;
    if (row['grades'] is! Map ||
        row['comment'] is! String ||
        (row['comment'] as String).length > 1000) {
      throw const AppException('Điểm hoặc nhận xét không hợp lệ.');
    }
    final raw = row['grades'] as Map;
    if (raw.keys.any((k) => !ids.contains(k))) {
      throw const AppException('File có điểm thuộc cột không xác định.');
    }
    final grades = <String, dynamic>{};
    for (final c in components) {
      final value = raw[c['id']];
      if (value != null &&
          value != '' &&
          (value is! num ||
              !value.isFinite ||
              value < 0 ||
              value > (c['maxScore'] as num))) {
        throw AppException(
          'Điểm ngoài thang: ${s['studentCode']} / ${c['name']}',
        );
      }
      grades[c['id'] as String] = value ?? '';
    }
    return {...s, 'grades': grades, 'comment': row['comment']};
  }).toList();
  return {...current, 'components': components, 'students': students};
}

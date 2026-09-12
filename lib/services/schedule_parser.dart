import '../models/schedule.dart';

class ScheduleDraft {
  final String rawLine;
  final Map<String, String> fields;
  final List<String> warnings;
  ScheduleDraft(this.rawLine, this.fields, this.warnings);
}

/// Parses reviewed text and the lecturer's A/P recurrence convention.
class ScheduleParser {
  List<ScheduleDraft> parse(String raw, {bool useNvhTimes = false}) {
    final result = <ScheduleDraft>[];
    for (final source in raw.split(RegExp(r'[\r\n]+'))) {
      final line = source.replaceAllMapped(
        RegExp(
          r'\b(SE|AI|IA|IS|HE|HS|GD|MC|IB|SB)\s*([0-9IOl ]{4,8})(?=\s*[-–])',
          caseSensitive: false,
        ),
        (m) =>
            '${m[1]}${m[2]!.replaceAll(' ', '').replaceAll(RegExp('[Il]', caseSensitive: false), '1').replaceAll(RegExp('O', caseSensitive: false), '0')}',
      );
      if (line.trim().isEmpty) continue;
      final upper = line.toUpperCase();
      final subject =
          RegExp(r'\b[A-Z]{2,6}\d{3}[A-Z]?\b').firstMatch(upper)?.group(0) ??
          '';
      final classCode =
          RegExp(
            r'\b(?:SE|AI|IA|IS|HE|HS|GD|MC|IB|SB)\d{4,6}[A-Z0-9]*\b',
          ).firstMatch(upper)?.group(0) ??
          '';
      if (subject.isEmpty && classCode.isEmpty) continue;
      final times = RegExp(
        r'\b([01]?\d|2[0-3])[:.]([0-5]\d)\b',
      ).allMatches(line).toList();
      String time(int index) => times.length <= index
          ? ''
          : '${times[index].group(1)!.padLeft(2, '0')}:${times[index].group(2)}';
      var day = '';
      final vn = RegExp(r'\b(?:THỨ|THU|T)\s*([2-7])\b').firstMatch(upper);
      if (vn != null) day = '${int.parse(vn.group(1)!) - 1}';
      const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      for (var i = 0; i < days.length; i++) {
        if (RegExp(
              '\\b${days[i]}(?:DAY|SDAY|NESDAY|RSDAY|URDAY)?\\b',
            ).hasMatch(upper) &&
            vn == null) {
          day = '${i + 1}';
        }
      }
      if (upper.contains('CHỦ NHẬT') || RegExp(r'\bCN\b').hasMatch(upper)) {
        day = '7';
      }
      final fields = <String, String>{
        'semester':
            RegExp(r'\b(?:FA|SP|SU)\d{2,4}\b').firstMatch(upper)?.group(0) ??
            '',
        'subjectCode': normalizeCode(subject),
        'subjectName': '',
        'classCode': classCode,
        'dayOfWeek': day,
        'slot':
            RegExp(
              r'(?:SLOT|TIẾT|TIET)\s*[:=]?\s*(\d{1,2})\b',
            ).firstMatch(upper)?.group(1) ??
            '',
        'startTime': time(0),
        'endTime': time(1),
        'room':
            RegExp(
              r'(?:ROOM|PHÒNG|PHONG)\s*[:=]?\s*([A-Z0-9][A-Z0-9.-]*)',
            ).firstMatch(upper)?.group(1) ??
            '',
      };
      final campus = RegExp(r'\bNVH\s+(\d{3,4})\b').firstMatch(upper);
      if (fields['room']!.isEmpty && campus != null) {
        fields['room'] = 'NVH ${campus.group(1)}';
      }
      final code = RegExp(r'\b([AP])([1-6])\b').firstMatch(upper);
      final expanded = <Map<String, String>>[];
      if (code != null && day.isEmpty && fields['slot']!.isEmpty) {
        final n = int.parse(code.group(2)!);
        final firstDay = (n - 1) ~/ 2 + 1;
        final slot = (n - 1) % 2 + (code.group(1) == 'A' ? 1 : 3);
        for (final d in [firstDay, firstDay + 3]) {
          expanded.add({...fields, 'dayOfWeek': '$d', 'slot': '$slot'});
        }
      } else {
        expanded.add(fields);
      }
      for (final values in expanded) {
        const nvhTimes = {
          '1': ['07:00', '09:15'],
          '2': ['09:30', '11:45'],
          '3': ['12:30', '14:45'],
          '4': ['15:00', '17:15'],
        };
        final defaults = useNvhTimes ? nvhTimes[values['slot']] : null;
        final fillTimes =
            defaults != null &&
            values['endTime']!.isEmpty &&
            (values['startTime']!.isEmpty ||
                defaults.contains(values['startTime']));
        if (fillTimes) {
          values['startTime'] = defaults[0];
          values['endTime'] = defaults[1];
        }
        final missing = values.entries
            .where((e) => e.value.isEmpty)
            .map((e) => e.key)
            .join(', ');
        result.add(
          ScheduleDraft(line, values, [
            if (fillTimes)
              'Giờ được điền theo khung NVH đã chọn, không phải chữ OCR.',
            if (code != null)
              'Quy đổi ${code.group(0)} theo quy ước A/P; kiểm tra với lịch tuần. Giờ học cần đối chiếu ảnh.',
            if (missing.isNotEmpty) 'Cần bổ sung: $missing',
            'Đối chiếu ảnh gốc trước khi xác nhận.',
          ]),
        );
      }
    }
    return result;
  }
}

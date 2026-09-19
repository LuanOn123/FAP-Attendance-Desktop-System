import 'schedule.dart';

class FapImportDto {
  final String courseCode,
      courseName,
      classCode,
      date,
      room,
      startTime,
      endTime;
  final int slot;
  final List<FapStudentDto> students;
  FapImportDto._(
    this.courseCode,
    this.courseName,
    this.classCode,
    this.date,
    this.room,
    this.slot,
    this.startTime,
    this.endTime,
    this.students,
  );

  factory FapImportDto.fromJson(Map<String, dynamic> json) {
    if (json['source'] != 'FAP_WEB_DOM') {
      throw const FormatException('Nguồn dữ liệu không hợp lệ.');
    }
    Map<String, dynamic> object(String key) {
      final value = json[key];
      if (value is! Map<String, dynamic>) throw FormatException('Thiếu $key.');
      return value;
    }

    String text(Map<String, dynamic> obj, String key) {
      final value = obj[key];
      if (value is! String || value.trim().isEmpty || value.length > 200) {
        throw FormatException('Thiếu hoặc sai $key.');
      }
      return value.trim();
    }

    final course = object('course'),
        group = object('class'),
        session = object('session');
    final courseCode = text(course, 'courseCode').toUpperCase();
    final classCode = text(group, 'classCode').toUpperCase();
    final date = text(session, 'date');
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Ngày phải hợp lệ theo YYYY-MM-DD.');
    }
    final slot = int.tryParse(session['slot'].toString());
    if (slot == null || slot < 1 || slot > 12) {
      throw const FormatException('Slot phải từ 1 đến 12.');
    }
    final room = text(session, 'room');
    final start = text(session, 'startTime'), end = text(session, 'endTime');
    final clock = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    if (!clock.hasMatch(start) ||
        !clock.hasMatch(end) ||
        start.compareTo(end) >= 0) {
      throw const FormatException('Giờ kết thúc phải sau giờ bắt đầu (HH:mm).');
    }
    if (!RegExp(r'^[A-Z]{2,6}\d{3}[A-Z0-9]*$').hasMatch(courseCode) ||
        !RegExp(r'^[A-Z0-9][A-Z0-9._-]{1,39}$').hasMatch(classCode)) {
      throw const FormatException('Mã môn hoặc mã lớp không hợp lệ.');
    }
    final rows = json['students'];
    if (rows is! List || rows.isEmpty || rows.length > 1000) {
      throw const FormatException(
        'Danh sách phải có từ 1 đến 1.000 sinh viên.',
      );
    }
    final students = <String, FapStudentDto>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Dòng sinh viên không hợp lệ.');
      }
      final code = text(row, 'studentCode').toUpperCase();
      final name = text(row, 'fullName');
      final email = (row['email'] ?? '').toString().trim().toLowerCase();
      if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]{1,39}$').hasMatch(code) ||
          email.length > 254 ||
          (email.isNotEmpty &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))) {
        throw FormatException('MSSV/email không hợp lệ: $code.');
      }
      final previous = students[code];
      if (previous != null &&
          (previous.fullName != name || previous.email != email)) {
        throw FormatException('MSSV $code bị trùng với thông tin khác nhau.');
      }
      students[code] = FapStudentDto(code, name, email);
    }
    return FapImportDto._(
      courseCode,
      (course['courseName'] ?? courseCode).toString().trim(),
      classCode,
      date,
      room,
      slot,
      start,
      end,
      students.values.toList(),
    );
  }
}

class FapStudentDto {
  final String studentCode, fullName, email;
  const FapStudentDto(this.studentCode, this.fullName, this.email);
}

class FapImportResult {
  final Schedule schedule;
  final String date;
  final int studentCount, added, existing;
  const FapImportResult(
    this.schedule,
    this.date,
    this.studentCount,
    this.added,
    this.existing,
  );
  Map<String, dynamic> toJson() => {
    'success': true,
    'scheduleId': schedule.scheduleId,
    'date': date,
    'studentCount': studentCount,
    'added': added,
    'existing': existing,
    'message': 'Đã nhập buổi học. Mở tab Điểm danh để tạo phiên.',
  };
}

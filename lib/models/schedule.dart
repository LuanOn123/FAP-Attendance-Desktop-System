String normalizeCode(String value) => value.trim().toUpperCase();
String mappingKey(String semester, String subjectCode, String classCode) =>
    [semester, subjectCode, classCode].map(normalizeCode).join('_');

class Schedule {
  final String scheduleId,
      lecturerId,
      semester,
      subjectCode,
      subjectName,
      classCode,
      startTime,
      endTime,
      room,
      sourceType;
  final int dayOfWeek, slot;
  const Schedule({
    required this.scheduleId,
    required this.lecturerId,
    required this.semester,
    required this.subjectCode,
    required this.subjectName,
    required this.classCode,
    required this.dayOfWeek,
    required this.slot,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.sourceType,
  });
  String get key => mappingKey(semester, subjectCode, classCode);
  Map<String, dynamic> toJson() => {
    'scheduleId': scheduleId,
    'lecturerId': lecturerId,
    'semester': normalizeCode(semester),
    'subjectCode': normalizeCode(subjectCode),
    'subjectName': subjectName.trim(),
    'classCode': normalizeCode(classCode),
    'dayOfWeek': dayOfWeek,
    'slot': slot,
    'startTime': startTime,
    'endTime': endTime,
    'room': room.trim(),
    'sourceType': sourceType,
  };
  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
    scheduleId: '${j['scheduleId']}',
    lecturerId: '${j['lecturerId']}',
    semester: '${j['semester']}',
    subjectCode: '${j['subjectCode']}',
    subjectName: '${j['subjectName']}',
    classCode: '${j['classCode']}',
    dayOfWeek: int.parse('${j['dayOfWeek']}'),
    slot: int.parse('${j['slot']}'),
    startTime: '${j['startTime']}',
    endTime: '${j['endTime']}',
    room: '${j['room']}',
    sourceType: '${j['sourceType']}',
  );

  List<String> validate() {
    final errors = <String>[];
    if ([
      semester,
      subjectCode,
      subjectName,
      classCode,
      room,
    ].any((s) => s.trim().isEmpty)) {
      errors.add('Điền đầy đủ học kỳ, môn học, tên môn, lớp và phòng.');
    }
    if (!RegExp(
      r'^[A-Z]{2,6}\d{3}[A-Z0-9]*$',
    ).hasMatch(normalizeCode(subjectCode))) {
      errors.add('Mã môn không hợp lệ (ví dụ PRM393).');
    }
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      errors.add('Thứ phải từ 1 (Thứ 2) đến 7 (Chủ nhật).');
    }
    if (slot < 1 || slot > 12) errors.add('Slot phải từ 1 đến 12.');
    final time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    if (!time.hasMatch(startTime) || !time.hasMatch(endTime)) {
      errors.add('Giờ phải theo HH:mm (00:00–23:59).');
    } else if (startTime.compareTo(endTime) >= 0) {
      errors.add('Giờ kết thúc phải sau giờ bắt đầu.');
    }
    if (!['IMAGE', 'MANUAL'].contains(sourceType)) {
      errors.add('Nguồn không hợp lệ.');
    }
    return errors;
  }
}

typedef AttendanceData = Map<String, dynamic>;

class TeachingOccurrence {
  final AttendanceData data;
  TeachingOccurrence(this.data);
  String get classId => '${data['classId']}';
  String get date => '${data['sessionDate']}';
  String get classCode => '${data['classCode'] ?? ''}';
  String get subjectCode => '${data['subjectId'] ?? ''}';
  String get room => '${data['room'] ?? ''}';
  String get semester => '${data['semester'] ?? ''}';
  int get slot => int.parse('${data['slot']}');
  DateTime get start => DateTime.fromMillisecondsSinceEpoch(
    (data['scheduledStartAt'] as num).toInt(),
    isUtc: true,
  );
  DateTime get end => DateTime.fromMillisecondsSinceEpoch(
    (data['scheduledEndAt'] as num).toInt(),
    isUtc: true,
  );
  bool get completed => data['completed'] == true;
  bool get editable => data['editable'] == true;
  String get key =>
      '$classId|$date|$slot|${data['scheduleId'] ?? ''}|${data['exceptionId'] ?? ''}';
  AttendanceData get selector => {
    'classId': classId,
    'sessionDate': date,
    'slot': slot,
    if (data['scheduleId'] != null) 'scheduleId': data['scheduleId'],
    if (data['exceptionId'] != null) 'exceptionId': data['exceptionId'],
    if (data['sessionId'] != null) 'sessionId': data['sessionId'],
  };
}

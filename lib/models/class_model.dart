import 'schedule.dart';

class ClassModel {
  final String classId, semester, subjectCode, classCode, lecturerId;
  const ClassModel({
    required this.classId,
    required this.semester,
    required this.subjectCode,
    required this.classCode,
    required this.lecturerId,
  });
  String get key => mappingKey(semester, subjectCode, classCode);
  factory ClassModel.fromJson(Map<String, dynamic> j) {
    final rawId = '${j['classId'] ?? ''}'.trim();
    final semester = '${j['semester'] ?? ''}'.trim();
    final subjectCode = '${j['subjectCode'] ?? ''}'.trim();
    final classCode = '${j['classCode'] ?? ''}'.trim();
    final lecturerId = '${j['lecturerId'] ?? ''}'.trim();
    final fallbackId = mappingKey(semester, subjectCode, classCode);
    return ClassModel(
      classId: (rawId.isNotEmpty && rawId != 'null') ? rawId : fallbackId,
      semester: semester,
      subjectCode: subjectCode,
      classCode: classCode,
      lecturerId: lecturerId,
    );
  }
}


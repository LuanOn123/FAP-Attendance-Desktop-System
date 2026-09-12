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
  factory ClassModel.fromJson(Map<String, dynamic> j) => ClassModel(
    classId: '${j['classId']}',
    semester: '${j['semester']}',
    subjectCode: '${j['subjectCode']}',
    classCode: '${j['classCode']}',
    lecturerId: '${j['lecturerId']}',
  );
}

import 'class_model.dart';
import 'schedule.dart';

class RosterStudent {
  final String classCode, studentCode, fullName, email;
  const RosterStudent({
    required this.classCode,
    required this.studentCode,
    required this.fullName,
    this.email = '',
  });
  Map<String, dynamic> toJson() => {
    'classCode': normalizeCode(classCode),
    'studentCode': normalizeCode(studentCode),
    'fullName': fullName.trim(),
    'schoolEmail': email.trim(),
  };
  factory RosterStudent.fromJson(Map<String, dynamic> j) => RosterStudent(
    classCode: '${j['classCode'] ?? ''}',
    studentCode: '${j['studentCode'] ?? ''}',
    fullName: '${j['fullName'] ?? ''}',
    email: '${j['schoolEmail'] ?? ''}',
  );
}

class ClassTarget {
  final String semester, subjectCode, classCode, subjectName;
  final String? classId;
  const ClassTarget({
    required this.semester,
    required this.subjectCode,
    required this.classCode,
    this.subjectName = '',
    this.classId,
  });
  String get key => mappingKey(semester, subjectCode, classCode);
  String get label => '$classCode · $subjectCode · $semester';
  Map<String, dynamic> toJson() => {
    'semester': semester,
    'subjectCode': subjectCode,
    'classCode': classCode,
  };
}

List<ClassTarget> classTargets(
  List<ClassModel> classes,
  List<Schedule> schedules,
  String owner,
) {
  final targets = <String, ClassTarget>{};
  for (final s in schedules.where((s) => s.lecturerId == owner)) {
    targets[s.key] = ClassTarget(
      semester: normalizeCode(s.semester),
      subjectCode: normalizeCode(s.subjectCode),
      classCode: normalizeCode(s.classCode),
      subjectName: s.subjectName,
    );
  }
  for (final c in classes.where((c) => c.lecturerId == owner)) {
    targets[c.key] = ClassTarget(
      semester: normalizeCode(c.semester),
      subjectCode: normalizeCode(c.subjectCode),
      classCode: normalizeCode(c.classCode),
      subjectName: targets[c.key]?.subjectName ?? '',
      classId: c.classId,
    );
  }
  return targets.values.toList()..sort((a, b) => a.label.compareTo(b.label));
}

class RosterImportResult {
  final int added, existing;
  const RosterImportResult(this.added, this.existing);
  factory RosterImportResult.fromJson(Map<String, dynamic> j) =>
      RosterImportResult(
        (j['added'] as num).toInt(),
        (j['existing'] as num).toInt(),
      );
}

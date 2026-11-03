import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/services/portal_grade_import.dart';
import 'package:fap_attendance/core/app_config.dart';

void main() {
  final target = <String, dynamic>{
    'semester': 'FA26',
    'subjectCode': 'PRM393',
    'classCode': 'SE1',
  };
  final current = <String, dynamic>{
    'version': 0,
    'students': [
      {
        'studentId': 's1',
        'studentCode': 'SE001',
        'fullName': 'Student',
        'grades': {},
        'comment': '',
      },
    ],
  };
  Map<String, dynamic> source({
    String roll = 'SE001',
    dynamic grade = 0,
    String semester = 'FA26',
  }) => {
    'schemaVersion': 1,
    'classes': [
      {
        'semester': semester,
        'subjectCode': 'PRM393',
        'classCode': 'SE1',
        'components': [
          {'id': 'p', 'name': 'PE', 'maxScore': 10},
        ],
        'students': [
          {
            'studentCode': roll,
            'grades': {'p': grade},
            'comment': 'Imported',
          },
        ],
      },
    ],
  };
  test(
    'import matches exact semester/subject/class and student; zero stays zero',
    () {
      final result = preparePortalGradeImport(source(), target, current);
      expect(result['students'][0]['studentId'], 's1');
      expect(result['students'][0]['grades']['p'], 0);
      expect(current['students'][0]['grades'], isEmpty);
    },
  );
  test(
    'wrong semester, unknown roll, invalid range never partially import',
    () {
      for (final value in [
        source(semester: 'SP26'),
        source(roll: 'SE999'),
        source(grade: 11),
        source(grade: '5'),
      ]) {
        expect(
          () => preparePortalGradeImport(value, target, current),
          throwsA(isA<AppException>()),
        );
      }
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/core/app_config.dart';
import 'package:fap_attendance/models/class_model.dart';
import 'package:fap_attendance/models/schedule.dart';
import 'package:fap_attendance/services/class_mapping_service.dart';
import 'package:fap_attendance/services/schedule_parser.dart';

Schedule sample({String start = '07:30', String end = '09:00'}) => Schedule(
  scheduleId: 's1',
  lecturerId: 'l1',
  semester: 'fa26 ',
  subjectCode: 'prm393',
  subjectName: 'Mobile',
  classCode: 'se1848',
  dayOfWeek: 1,
  slot: 1,
  startTime: start,
  endTime: end,
  room: 'AL201',
  sourceType: 'IMAGE',
);
ClassModel klass(String id, {String owner = 'l1', String semester = 'FA26'}) =>
    ClassModel(
      classId: id,
      semester: semester,
      subjectCode: 'PRM393',
      classCode: 'SE1848',
      lecturerId: owner,
    );

void main() {
  test('School email uses exact domain and rejects spoofing', () {
    expect(isSchoolEmail(' User@FPT.EDU.VN ', 'fpt.edu.vn,fe.edu.vn'), isTrue);
    for (final email in [
      'x@fpt.edu.vn.evil.com',
      'x@evilfpt.edu.vn',
      '@fpt.edu.vn',
      'x@@fpt.edu.vn',
      'x@gmail.com',
    ]) {
      expect(isSchoolEmail(email, 'fpt.edu.vn,fe.edu.vn'), isFalse);
    }
  });
  test(
    'Mapping normalizes codes, scopes owner and rejects ambiguous matches',
    () {
      final service = ClassMappingService();
      expect(sample().key, 'FA26_PRM393_SE1848');
      expect(service.map(sample(), [klass('c1')]).mappedClass?.classId, 'c1');
      expect(
        service.map(sample(), [
          klass('c1', owner: 'other'),
          klass('c2', semester: 'SP26'),
        ]).matches,
        isEmpty,
      );
      expect(
        service.map(sample(), [klass('c1'), klass('c2')]).mappedClass,
        isNull,
      );
    },
  );
  test('OCR extracts fields but keeps unknown values blank', () {
    final rows = ScheduleParser().parse(
      'Header\nFA26 PRM393 SE1848 Thứ 2 Slot 1 7:30-09:00 Room AL-201\nSWE201 SE1901',
    );
    expect(rows.length, 2);
    expect(rows.first.fields['dayOfWeek'], '1');
    expect(rows.first.fields['startTime'], '07:30');
    expect(rows.first.fields['endTime'], '09:00');
    expect(rows.first.fields['slot'], '1');
    expect(rows.first.fields['room'], 'AL-201');
    expect(rows.last.fields['startTime'], isEmpty);
    expect(rows.first.fields['subjectName'], isEmpty);
    expect(rows.last.warnings, isNotEmpty);
    expect(ScheduleParser().parse(''), isEmpty);
  });
  test(
    'Invalid times and reverse ranges are rejected; Sheets rows roundtrip',
    () {
      expect(sample().validate(), isEmpty);
      expect(sample(start: '24:00').validate(), isNotEmpty);
      expect(sample(start: '09:00').validate(), isNotEmpty);
      expect(sample(start: '10:00').validate(), isNotEmpty);
      expect(Schedule.fromJson(sample().toJson()).key, sample().key);
    },
  );
}

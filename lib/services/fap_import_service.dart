import 'package:uuid/uuid.dart';
import '../models/fap_import_dto.dart';
import '../models/schedule.dart';
import '../models/roster.dart';
import '../repositories/schedule_repository.dart';

class FapImportService {
  final ScheduleRepository repository;
  final String lecturerId;
  FapImportService(this.repository, this.lecturerId);

  Future<FapImportResult> importSession(FapImportDto data) async {
    final date = DateTime.parse(data.date);
    final year = date.year.toString().substring(2);
    final semester =
        (date.month <= 4
            ? 'SP'
            : date.month <= 8
            ? 'SU'
            : 'FA') +
        year;
    final key = mappingKey(semester, data.courseCode, data.classCode);
    final schedules = await repository.getSchedules();
    final matches = schedules.where(
      (s) =>
          s.lecturerId == lecturerId &&
          s.key == key &&
          s.dayOfWeek == date.weekday &&
          s.slot == data.slot,
    );
    final schedule = Schedule(
      scheduleId: matches.isEmpty
          ? const Uuid().v4()
          : matches.first.scheduleId,
      lecturerId: lecturerId,
      semester: semester,
      subjectCode: data.courseCode,
      subjectName: data.courseName.isEmpty ? data.courseCode : data.courseName,
      classCode: data.classCode,
      dayOfWeek: date.weekday,
      slot: data.slot,
      startTime: data.startTime,
      endTime: data.endTime,
      room: data.room,
      sourceType: 'MANUAL',
    );
    // importRoster authorizes new classes against the lecturer's schedule.
    // Retrying reuses the schedule ID and deduplicates enrollments.
    await repository.save([schedule]);
    final roster = await repository.importRoster(
      ClassTarget(
        semester: semester,
        subjectCode: data.courseCode,
        classCode: data.classCode,
        subjectName: schedule.subjectName,
      ),
      data.students
          .map(
            (s) => RosterStudent(
              classCode: data.classCode,
              studentCode: s.studentCode,
              fullName: s.fullName,
              email: s.email,
            ),
          )
          .toList(),
    );
    return FapImportResult(
      schedule,
      data.date,
      data.students.length,
      roster.added,
      roster.existing,
    );
  }
}

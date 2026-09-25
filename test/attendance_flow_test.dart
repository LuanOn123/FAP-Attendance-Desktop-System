import 'dart:io';
import 'dart:convert';
import 'package:fap_attendance/services/integration_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/models/schedule.dart';
import 'package:fap_attendance/models/fap_import_dto.dart';
import 'package:fap_attendance/repositories/attendance_repository.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';
import 'package:fap_attendance/services/fap_import_service.dart';
import 'package:fap_attendance/services/attendance_sync_service.dart';
import 'package:fap_attendance/services/schedule_clock.dart';
import 'fap_import_test.dart' show sampleImport;

void main() {
  const schedule = Schedule(
    scheduleId: 's1',
    lecturerId: 'l1',
    semester: 'FA26',
    subjectCode: 'PRN232',
    subjectName: '',
    classCode: 'SE1917',
    dayOfWeek: 2,
    slot: 1,
    startTime: '07:00',
    endTime: '09:15',
    room: '602',
    sourceType: 'MANUAL',
  );
  test(
    'campus current slot includes start, excludes end and ignores OS timezone',
    () {
      expect(
        ScheduleClock.isCurrent(
          schedule,
          instant: DateTime.parse('2026-09-22T00:00:00Z'),
        ),
        isTrue,
      );
      expect(
        ScheduleClock.isCurrent(
          schedule,
          instant: DateTime.parse('2026-09-22T02:14:59Z'),
        ),
        isTrue,
      );
      expect(
        ScheduleClock.isCurrent(
          schedule,
          instant: DateTime.parse('2026-09-22T02:15:00Z'),
        ),
        isFalse,
      );
      expect(
        ScheduleClock.isCurrent(
          schedule,
          instant: DateTime.parse('2026-09-21T23:59:59Z'),
        ),
        isFalse,
      );
      expect(
        ScheduleClock.isCurrent(
          schedule,
          instant: DateTime.parse('2026-09-29T00:30:00Z'),
          exactDate: '2026-09-22',
        ),
        isFalse,
      );
      expect(
        ScheduleClock.date(
          ScheduleClock.now(DateTime.parse('2026-09-21T20:00:00Z')),
        ),
        '2026-09-22',
      );
    },
  );
  test('next occurrence advances after slot, retains current teaching day', () {
    expect(
      ScheduleClock.date(
        ScheduleClock.next(
          schedule,
          instant: DateTime.parse('2026-09-22T01:00:00Z'),
        ),
      ),
      '2026-09-22',
    );
    expect(
      ScheduleClock.date(
        ScheduleClock.next(
          schedule,
          instant: DateTime.parse('2026-09-22T02:15:00Z'),
        ),
      ),
      '2026-09-29',
    );
  });
  test(
    'sync matches all session dimensions, requires finalized roster, excludes reset',
    () async {
      final schedules = DemoScheduleRepository();
      final attendance = DemoAttendanceRepository();
      final imported = await FapImportService(
        schedules,
        'demo-lecturer',
      ).importSession(FapImportDto.fromJson(sampleImport()));
      final cls = (await schedules.getClasses()).firstWhere(
        (c) => c.key == imported.schedule.key,
      );
      final session = await attendance.startSession(
        date: imported.date,
        classId: cls.classId,
        slot: 1,
        startTime: '07:30',
        endTime: '09:50',
        lecturerId: 'demo-lecturer',
      );
      final sync = AttendanceSyncService(
        schedules,
        attendance,
        'demo-lecturer',
      );
      final query = <String, dynamic>{
        'courseCode': 'SWE102',
        'classCode': 'SE1701',
        'date': imported.date,
        'slot': 1,
        'startTime': '07:30',
        'endTime': '09:50',
      };
      await expectLater(sync.report(query), throwsA(anything));
      await attendance.checkInStudent(
        sessionId: session.sessionId,
        token: session.currentToken,
        secretCode: '',
        studentCode: 'SE123456',
        fullName: 'A',
        email: 'a@fpt.edu.vn',
      );
      await attendance.closeSession(session.sessionId);
      await expectLater(sync.report(query), throwsA(anything));
      await expectLater(
        sync.report({'selectedReport': true}),
        throwsA(anything),
      );
      final selected = await sync.report(
        {'selectedReport': true, 'date': '2000-01-01', 'slot': 12},
        selectedClassId: cls.classId,
        selectedSessionId: session.sessionId,
      );
      final selectedData = selected['data'] as Map;
      expect(selectedData['matchMode'], 'selectedReport');
      expect(selectedData['metadata']['date'], imported.date);
      expect((selectedData['entries'] as List).map((e) => e['status']), [
        'present',
        'absent',
      ]);
      expect(
        (selectedData['entries'] as List).every(
          (e) => (e['fullName'] as String).isNotEmpty,
        ),
        true,
      );
      await attendance.markAbsent(
        sessionId: session.sessionId,
        studentCodes: ['SE123457'],
        lecturerEmail: 'demo@fpt.edu.vn',
      );
      final result = await sync.report(query);
      final entries = (result['data'] as Map)['entries'] as List;
      final bridge = IntegrationServer();
      await bridge.start(
        schedules,
        'demo-lecturer',
        port: 0,
        attendanceRepository: attendance,
      );
      final client = HttpClient();
      try {
        for (final origin in [
          'chrome-extension://${'a' * 32}',
          'https://fap.fpt.edu.vn',
        ]) {
          final request = await client.postUrl(
            Uri.parse(
              'http://127.0.0.1:${bridge.port}/api/integration/fap/report',
            ),
          );
          request.headers.contentType = ContentType.json;
          request.headers.set('Origin', origin);
          request.headers.set('X-FAP-Attendance-Client', 'browser-extension');
          request.write(jsonEncode(query));
          final response = await request.close();
          expect(
            response.statusCode,
            origin.startsWith('chrome-extension:') ? 200 : 403,
          );
          final body =
              jsonDecode(await utf8.decoder.bind(response).join()) as Map;
          if (response.statusCode == 200) {
            expect(body['data']['sessionId'], session.sessionId);
          }
        }
      } finally {
        client.close(force: true);
        await bridge.stop();
      }

      expect(entries.map((e) => e['status']), ['present', 'absent']);
      for (final mismatch in [
        {'slot': 2},
        {'date': '2026-09-19'},
        {'startTime': '07:00'},
        {'classCode': 'SE9999'},
      ]) {
        await expectLater(
          sync.report({...query, ...mismatch}),
          throwsA(anything),
        );
      }
      final withoutCourse = Map<String, dynamic>.from(query)
        ..remove('courseCode');
      expect((await sync.report(withoutCourse))['success'], true);
      expect(
        (await sync.report({
          ...query,
          'courseCode': 'OTHER',
          'semester': 'OTHER',
        }))['success'],
        true,
      );
      final reset = await attendance.resetSession(session.sessionId);
      expect(reset.currentSecretCode, isEmpty);
      expect(
        await attendance.getSessionAttendance(session.sessionId),
        hasLength(2),
      );
      expect(await attendance.getSessionAttendance(reset.sessionId), isEmpty);
      expect(await attendance.getSessionsByClass(cls.classId), hasLength(1));
      await expectLater(sync.report(query), throwsA(anything));
    },
  );
}

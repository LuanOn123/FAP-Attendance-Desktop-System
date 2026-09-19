import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/models/fap_import_dto.dart';
import 'package:fap_attendance/models/roster.dart';
import 'package:fap_attendance/repositories/schedule_repository.dart';
import 'package:fap_attendance/services/fap_import_service.dart';
import 'package:fap_attendance/services/integration_server.dart';

Map<String, dynamic> sampleImport() => {
  'source': 'FAP_WEB_DOM',
  'course': {'courseCode': 'SWE102', 'courseName': 'Lập Trình Web'},
  'class': {'classCode': 'SE1701'},
  'session': {
    'date': '2026-09-18',
    'slot': 1,
    'room': 'AL-201',
    'startTime': '07:30',
    'endTime': '09:50',
  },
  'students': [
    {
      'studentCode': 'SE123456',
      'fullName': 'Nguyen Van A',
      'email': 'a@fpt.edu.vn',
    },
    {
      'studentCode': 'SE123457',
      'fullName': 'Le Thi B',
      'email': 'b@fpt.edu.vn',
    },
  ],
};

void main() {
  test(
    'invalid date/slot/empty roster/conflicting identities rejected before save',
    () {
      for (final date in ['2026-02-30', '', '18/09/2026']) {
        final json = sampleImport();
        (json['session'] as Map)['date'] = date;
        expect(() => FapImportDto.fromJson(json), throwsFormatException);
      }
      final json = sampleImport();
      (json['session'] as Map)['slot'] = 0;
      expect(() => FapImportDto.fromJson(json), throwsFormatException);
      json['students'] = [];
      expect(() => FapImportDto.fromJson(json), throwsFormatException);
      final duplicate = sampleImport();
      (duplicate['students'] as List).add({
        'studentCode': 'SE123456',
        'fullName': 'Other name',
      });
      expect(() => FapImportDto.fromJson(duplicate), throwsFormatException);
    },
  );

  test(
    'reimport deduplicates schedules and roster but new semester stays separate',
    () async {
      final repo = DemoScheduleRepository();
      final service = FapImportService(repo, 'demo-lecturer');
      final first = await service.importSession(
        FapImportDto.fromJson(sampleImport()),
      );
      final second = await service.importSession(
        FapImportDto.fromJson(sampleImport()),
      );
      expect(second.schedule.scheduleId, first.schedule.scheduleId);
      expect(second.added, 0);
      expect(second.existing, 2);
      expect(first.date, '2026-09-18');
      expect(first.schedule.dayOfWeek, DateTime.friday);
      expect(
        await repo.getRoster(
          const ClassTarget(
            semester: 'FA26',
            subjectCode: 'SWE102',
            classCode: 'SE1701',
          ),
        ),
        hasLength(2),
      );
      final nextYear = sampleImport();
      (nextYear['session'] as Map)['date'] = '2027-09-17';
      final next = await service.importSession(FapImportDto.fromJson(nextYear));
      expect(next.schedule.scheduleId, isNot(first.schedule.scheduleId));
      expect(next.schedule.semester, 'FA27');
    },
  );

  test(
    'loopback bridge health, import event, invalid origin/header and shutdown',
    () async {
      final server = IntegrationServer();
      final repo = DemoScheduleRepository();
      await server.start(repo, 'demo-lecturer', port: 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final health = await (await client.getUrl(
        Uri.parse('$base/api/integration/health'),
      )).close();
      final data = jsonDecode(await utf8.decoder.bind(health).join());
      expect(data['protocolVersion'], 1);

      Future<int> send({
        String? origin,
        bool header = true,
        Map<String, dynamic>? payload,
      }) async {
        final request = await client.postUrl(
          Uri.parse('$base/api/integration/fap/session'),
        );
        request.headers.contentType = ContentType.json;
        if (header) {
          request.headers.set('X-FAP-Attendance-Client', 'browser-extension');
        }
        if (origin != null) request.headers.set('Origin', origin);
        request.write(jsonEncode(payload ?? sampleImport()));
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await send(origin: 'https://untrusted.example'), 403);
      expect(await send(header: false), 403);
      expect(await send(payload: {}), 400);
      final event = server.onImportComplete.first;
      expect(
        await send(
          origin: 'chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        200,
      );
      expect((await event).schedule.classCode, 'SE1701');
      expect(await send(), 200);
      expect(
        (await repo.getSchedules()).where((s) => s.classCode == 'SE1701'),
        hasLength(1),
      );
    },
  );
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fap_attendance/models/teaching_occurrence.dart';
import 'package:fap_attendance/models/quick_attendance_draft.dart';
import 'package:fap_attendance/repositories/daily_attendance_repository.dart';
import 'package:fap_attendance/services/google_sheet_service.dart';
import 'package:fap_attendance/services/attendance_local_store.dart';
import 'package:fap_attendance/services/desktop_attendance_reminders.dart';
import 'package:fap_attendance/features/attendance/quick_attendance_screen.dart';
import 'package:fap_attendance/features/attendance/attendance_day_panel.dart';

final selector = <String, dynamic>{
  'classId': 'c1',
  'sessionDate': '2026-10-30',
  'slot': 1,
  'scheduleId': 's1',
  'exceptionId': '',
};
AttendanceData lesson({bool completed = false, int start = 9, int end = 10}) =>
    {
      ...selector,
      'classCode': 'SE1',
      'subjectId': 'PRM393',
      'room': 'A201',
      'semester': 'FA26',
      'scheduledStartTime': '${start.toString().padLeft(2, '0')}:00',
      'scheduledEndTime': '${end.toString().padLeft(2, '0')}:00',
      'scheduledStartAt': DateTime.parse(
        '2026-10-30T${start.toString().padLeft(2, '0')}:00:00+07:00',
      ).millisecondsSinceEpoch,
      'scheduledEndAt': DateTime.parse(
        '2026-10-30T${end.toString().padLeft(2, '0')}:00:00+07:00',
      ).millisecondsSinceEpoch,
      'completed': completed,
      'editable': true,
      'qrState': 'ENDED',
    };

class QuickFixture extends DailyAttendanceRepository {
  final List<AttendanceData> calls = [];
  bool saved = false, failOnce = false, editable = true;
  final List<AttendanceData> submissions = [];
  AttendanceData get context => {
    ...lesson(completed: saved),
    'serverTime': DateTime.parse('2026-10-30T15:00:00Z').millisecondsSinceEpoch,
    'editable': editable,
    'revision': saved ? 'v2' : 'v1',
    'attendanceCompleted': saved,
    'students': [
      {
        'studentId': 's1',
        'studentCode': 'SE001',
        'displayName': 'Nguyễn An',
        'status': saved ? 'present' : null,
      },
      {
        'studentId': 's2',
        'studentCode': 'SE002',
        'displayName': 'Trần Bình',
        'status': saved ? 'absent' : null,
      },
    ],
  };
  @override
  Future<AttendanceData> call(String name, AttendanceData input) async {
    calls.add({'name': name, 'input': input});
    if (name == 'getAttendanceDay') {
      return {
        'lessons': [lesson(completed: saved)],
        'serverTime': DateTime.parse(
          '2026-10-30T15:00:00Z',
        ).millisecondsSinceEpoch,
      };
    }
    if (name == 'getQuickAttendanceContext') return context;
    submissions.add(Map.from(input));
    if (failOnce) {
      failOnce = false;
      throw Exception('network timeout');
    }
    saved = true;
    return {
      'status': 'CLOSED',
      'savedAt': DateTime.parse('2026-10-30T15:00:00Z').millisecondsSinceEpoch,
    };
  }
}

class AlertFixture extends AttendanceAlerts {
  final shown = <DesktopAttendanceReminder>[];
  final retained = <Set<String>>[];
  @override
  Future<void> show(
    DesktopAttendanceReminder r,
    void Function() onClick,
  ) async {
    shown.add(r);
  }

  @override
  Future<void> retain(Set<String> ids) async {
    retained.add(ids);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'quick draft defaults PRESENT, preserves saved baseline, sends only explicit differences',
    () {
      final d = QuickAttendanceDraft(const [
        QuickStudent(id: 's1', code: 'SE1', name: 'An'),
        QuickStudent(id: 's2', code: 'SE2', name: 'Bình', existing: 'absent'),
      ], revision: 'v1');
      expect(d.counts, {'present': 1, 'absent': 1});
      expect(d.payload(selector, 'request')['exceptions'], isEmpty);
      d.set('s1', 'absent');
      expect(d.payload(selector, 'request')['exceptions'], [
        {'studentId': 's1', 'status': 'ABSENT'},
      ]);
      expect(d.visible(QuickFilter.exceptions, 'binh').single.id, 's2');
      d.undo();
      expect(d.statusOf('s1'), 'present');
      final restored = QuickAttendanceDraft(d.students, revision: 'v1');
      expect(restored.restore(d.encode()), true);
      expect(
        QuickAttendanceDraft(d.students, revision: 'v2').restore(d.encode()),
        false,
      );
    },
  );
  test('reminder schedule matches mobile and stops for completed lessons', () {
    final p = TeachingOccurrence(lesson());
    final plan = planDesktopAttendanceReminders([p, p]);
    expect(plan.map((r) => r.at), [
      DateTime.utc(2026, 10, 30, 2, 30),
      DateTime.utc(2026, 10, 30, 2, 55),
      DateTime.utc(2026, 10, 30, 3, 10),
      DateTime.utc(2026, 10, 30, 14),
    ]);
    expect(plan.every((r) => r.lesson.selector['classId'] == 'c1'), true);
    expect(
      planDesktopAttendanceReminders([
        TeachingOccurrence(lesson(completed: true)),
      ]),
      isEmpty,
    );
    final cursor = AttendanceReminderCursor();
    expect(cursor.scan([p], DateTime.utc(2026, 10, 30, 2, 29)), isEmpty);
    expect(cursor.scan([p], DateTime.utc(2026, 10, 30, 2, 30)), hasLength(1));
    expect(cursor.scan([p], DateTime.utc(2026, 10, 30, 2, 30, 30)), isEmpty);
    expect(cursor.scan([p], DateTime.utc(2026, 10, 30, 17)), isEmpty);
  });
  test(
    'desktop quick OAuth transport never uses mobile Firebase route',
    () async {
      final service = GoogleSheetService(
        endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
        tokenProvider: () async => 'oauth',
        client: MockClient((r) async {
          final body = jsonDecode(r.body);
          expect(body['action'], 'desktopAttendanceCall');
          expect(body['name'], 'getQuickAttendanceContext');
          expect(body['idToken'], 'oauth');
          expect(body['input'], selector);
          return http.Response(
            jsonEncode({'ok': true, 'data': QuickFixture().context}),
            200,
              headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(
        (await SheetDailyAttendanceRepository(
          service,
        ).call('getQuickAttendanceContext', selector))['revision'],
        'v1',
      );
    },
  );
  Future<void> showQuick(
    WidgetTester t,
    QuickFixture repo,
    MemoryAttendanceLocalStore store,
  ) async {
    await t.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: QuickAttendanceScreen(
          repository: repo,
          selector: selector,
          owner: 'l1',
          store: store,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'no writes until review confirmation; absent exceptions shared with default present',
    (t) async {
      final repo = QuickFixture(), store = MemoryAttendanceLocalStore();
      await showQuick(t, repo, store);
      expect(repo.submissions, isEmpty);
      expect(find.text('2 sinh viên: 2 Có mặt'), findsOneWidget);
      await t.tap(find.text('Vắng').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Kiểm tra / Lưu điểm danh'));
      await t.pumpAndSettle();
      expect(repo.submissions, isEmpty);
      await t.tap(find.text('Xác nhận lưu điểm danh'));
      await t.pumpAndSettle();
      expect(repo.submissions.single['exceptions'], [
        {'studentId': 's2', 'status': 'ABSENT'},
      ]);
      expect(repo.submissions.single['expectedRevision'], 'v1');
      expect(find.text('Đã lưu điểm danh và chốt buổi học.'), findsOneWidget);
      expect(store.values, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'network retry preserves exact receipt ID and payload across screen reopen',
    (t) async {
      final repo = QuickFixture()..failOnce = true;
      final store = MemoryAttendanceLocalStore();
      await showQuick(t, repo, store);
      await t.tap(find.text('Kiểm tra / Lưu điểm danh'));
      await t.pumpAndSettle();
      await t.tap(find.text('Xác nhận lưu điểm danh'));
      await t.pumpAndSettle();
      expect(repo.submissions, hasLength(1));
      final first = jsonEncode(repo.submissions.first);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await showQuick(t, repo, store);
      expect(find.text('Kiểm tra lần gửi trước'), findsOneWidget);
      await t.tap(find.text('Kiểm tra lần gửi trước'));
      await t.pumpAndSettle();
      await t.tap(find.text('Kiểm tra / Gửi lại'));
      await t.pumpAndSettle();
      expect(jsonEncode(repo.submissions.last), first);
      expect(store.values, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('previous day context is read-only', (t) async {
    final repo = QuickFixture()..editable = false;
    await showQuick(t, repo, MemoryAttendanceLocalStore());
    final button = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Kiểm tra / Lưu điểm danh'),
    );
    expect(button.onPressed, isNull);
    expect(repo.submissions, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'mobile completion removes pending reminder on periodic refresh',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final repo = QuickFixture(),
          store = MemoryAttendanceLocalStore(),
          alerts = AlertFixture();
      store.values['desktop-attendance-reminders/v1/l1'] = 'true';
      store.values['desktop-attendance-reminders/v1/l1/term'] = 'FA26';
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AttendanceDayPanel(
                repository: repo,
                owner: 'l1',
                store: store,
                alerts: alerts,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Điểm danh hôm nay · 1 buổi chưa chốt'), findsOneWidget);
      repo.saved = true;
      await t.pump(const Duration(seconds: 31));
      await t.pumpAndSettle();
      expect(find.text('Điểm danh hôm nay · 0 buổi chưa chốt'), findsOneWidget);
      expect(alerts.retained.last, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
}

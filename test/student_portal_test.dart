import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fap_attendance/services/google_sheet_service.dart';
import 'package:fap_attendance/repositories/student_portal_repository.dart';
import 'package:fap_attendance/features/student_portal/student_portal_screen.dart';
import 'package:fap_attendance/features/student_portal/leave_request_panel.dart';

class LeaveFixture extends StudentPortalRepository {
  String status = 'PENDING';
  final calls = <PortalRow>[];
  @override
  Future<dynamic> call(String method, [PortalRow data = const {}]) async {
    calls.add({'method': method, ...data});
    if (method == 'reviewLeaveRequest') {
      status = data['status'] as String;
      return {'saved': true};
    }
    return [
      {
        'id': 'leave-1',
        'classId': 'c1',
        'studentId': 's1',
        'studentCode': 'SE1',
        'fullName': 'Sinh viên A',
        'sessionDate': '2026-10-24',
        'slot': 1,
        'reason': 'Khám bệnh theo lịch hẹn',
        'status': status,
        'submittedAt': '2026-10-23T01:00:00Z',
        'version': 1,
        'scheduleChanged': false,
      },
    ];
  }
}

void main() {
  testWidgets(
    'lecturer forecast opens without losing unsaved grades or publishing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = DemoStudentPortalRepository();
      repo.state['components'] = <PortalRow>[
        {'id': 'quiz', 'name': 'Quiz', 'maxScore': 10},
      ];
      repo.state['students'][0]['grades'] = {'quiz': 5};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StudentPortalScreen(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '8');
      await tester.tap(find.text('Tính điểm FE/PE'));
      await tester.pumpAndSettle();
      expect(find.text('Tư vấn điểm cần đạt'), findsOneWidget);
      expect(find.text('FA26 · PRM393 · SE1848'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
                .widget<TextFormField>(find.byType(TextFormField).first)
                .controller
                ?.text ??
            tester
                .widget<TextFormField>(find.byType(TextFormField).first)
                .initialValue,
        '8',
      );
      expect(repo.state['students'][0]['grades']['quiz'], 5);
      expect(repo.state['version'], 0);
      expect(repo.state['activePublicationId'], '');
      expect(find.textContaining('Có thay đổi chưa lưu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('desktop sends OAuth identity through shared portal envelope', () async {
    final service = GoogleSheetService(
      endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
      tokenProvider: () async => 'oauth-token',
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map;
        expect(body['action'], 'portalCall');
        expect(body['method'], 'getGradebook');
        expect(body['idToken'], 'oauth-token');
        expect(body['data'], {'classId': 'c1'});
        expect(body.containsKey('firebaseAuth'), isFalse);
        return http.Response('{"ok":true,"data":{"version":0}}', 200);
      }),
    );
    expect(
      (await SheetStudentPortalRepository(
        service,
      ).call('getGradebook', {'classId': 'c1'}))['version'],
      0,
    );
  });
  testWidgets(
    'grade editor saves zero, preserves identity and explicitly publishes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = DemoStudentPortalRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StudentPortalScreen(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm cột điểm'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), 'Practical');
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.tap(find.text('Lưu bản nháp'));
      await tester.pumpAndSettle();
      expect((repo.state['students'] as List).first['studentCode'], 'SE000001');
      expect(
        ((repo.state['students'] as List).first['grades'] as Map).values.single,
        0,
      );
      expect(repo.state['activePublicationId'], '');
      await tester.tap(find.text('Xem trước / Công bố'));
      await tester.pumpAndSettle();
      expect(find.text('Xem trước công bố điểm'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Công bố điểm'));
      await tester.pumpAndSettle();
      expect(repo.state['activePublicationId'], 'demo-publication');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets(
    'slot leave panel scopes requests and sends explicit teacher review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = LeaveFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LeaveRequestPanel(
                repository: repo,
                classId: 'c1',
                sessionDate: '2026-10-24',
                slot: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.calls.first['sessionDate'], '2026-10-24');
      expect(repo.calls.first['slot'], 1);
      expect(find.text('Khám bệnh theo lịch hẹn'), findsOneWidget);
      await tester.tap(find.text('Duyệt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      final review = repo.calls.firstWhere(
        (c) => c['method'] == 'reviewLeaveRequest',
      );
      expect(review['status'], 'APPROVED');
      expect(review['version'], 1);
      expect(review['classId'], 'c1');
      expect(find.text('Duyệt'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}

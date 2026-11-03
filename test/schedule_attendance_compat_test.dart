import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fap_attendance/services/google_sheet_service.dart';
import 'package:fap_attendance/repositories/attendance_repository.dart';
import 'package:fap_attendance/core/app_config.dart';
import 'package:fap_attendance/models/session_model.dart';
import 'package:fap_attendance/features/attendance/session_qr_widget.dart';

void main() {
  test(
    'Desktop sends ten minutes and consumes actual server deadline; Vietnamese window error is surfaced',
    () async {
      var denied = false;
      final api = GoogleSheetService(
        endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
        tokenProvider: () async => 'token',
        client: MockClient((request) async {
          final payload = jsonDecode(request.body);
          expect(payload['durationMinutes'], 10);
          expect(payload['date'], '2026-10-11');
          return http.Response(
            jsonEncode(
              denied
                  ? {'ok': false, 'error': 'OCCURRENCE_NOT_YET'}
                  : {
                      'ok': true,
                      'data': {
                        'sessionId': 'actual',
                        'classId': 'c1',
                        'status': 'OPEN',
                        'opensAt': 1000,
                        'closesAt': 301000,
                        'effectiveDurationMinutes': 5,
                        'tokenExpiredAt': '2026-10-11T02:30:00Z',
                      },
                    },
            ),
            200,
          );
        }),
      );
      final repo = SheetAttendanceRepository(api);
      Future<SessionModel> open() => repo.startSession(
        date: '2026-10-11',
        classId: 'c1',
        slot: 1,
        startTime: 'forged',
        endTime: 'forged',
        lecturerId: 'l1',
      );
      final session = await open();
      expect(session.closesAt, 301000);
      expect(session.effectiveDurationMinutes, 5);
      expect(session.copyWith(currentToken: 'rotated').closesAt, 301000);
      denied = true;
      await expectLater(
        open(),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Chưa đến giờ'),
          ),
        ),
      );
      api.client.close();
    },
  );
  testWidgets('Desktop QR updates when Mobile changes the shared token', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget qr(String token) => MaterialApp(
      home: Scaffold(
        body: SessionQrDisplayWidget(
          sessionId: 'shared',
          initialToken: token,
          initialSecretCode: token == 'mobile' ? '123456' : '',
          onRotateToken: (_, _) async {},
        ),
      ),
    );
    await tester.pumpWidget(qr('desktop'));
    expect(find.text('123456'), findsNothing);
    await tester.pumpWidget(qr('mobile'));
    expect(find.text('123456'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });
}

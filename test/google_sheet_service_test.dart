import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fap_attendance/services/google_sheet_service.dart';

void main() {
  GoogleSheetService service(MockClient client) => GoogleSheetService(
    endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
    tokenProvider: () async => 'private-token',
    client: client,
  );
  test('Token stays in POST body and is not forwarded to result URL', () async {
    var calls = 0;
    final api = service(
      MockClient((request) async {
        calls++;
        if (calls == 1) {
          expect(request.method, 'POST');
          expect(request.url.query, isEmpty);
          expect(jsonDecode(request.body)['idToken'], 'private-token');
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://script.googleusercontent.com/result?id=123',
            },
          );
        }
        expect(request.method, 'GET');
        expect(request.body, isEmpty);
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response('{"ok":true,"data":[{"scheduleId":"s1"}]}', 200);
      }),
    );
    expect((await api.getRows('Schedules')).single['scheduleId'], 's1');
    expect(calls, 2);
  });
  test('Rejects foreign redirects and non-JSON responses', () async {
    final redirect = service(
      MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example/result'},
        ),
      ),
    );
    await expectLater(redirect.getRows('Schedules'), throwsException);
    final html = service(
      MockClient((_) async => http.Response('<html>Login</html>', 200)),
    );
    await expectLater(html.getRows('Schedules'), throwsException);
  });
  test('Failed mutation is surfaced', () async {
    final api = service(
      MockClient(
        (_) async => http.Response('{"ok":false,"error":"Forbidden"}', 200),
      ),
    );
    await expectLater(api.deleteRow('Schedules', 's1'), throwsException);
  });
}

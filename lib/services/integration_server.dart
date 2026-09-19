import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/app_config.dart';
import '../models/fap_import_dto.dart';
import '../repositories/schedule_repository.dart';
import 'fap_import_service.dart';

/// Runs only while a lecturer is signed in. Ordinary web pages cannot post here.
class IntegrationServer {
  HttpServer? _server;
  bool _stopped = false;
  bool _importing = false;
  final _events = StreamController<FapImportResult>.broadcast();
  Stream<FapImportResult> get onImportComplete => _events.stream;
  int? get port => _server?.port;

  Future<void> start(
    ScheduleRepository repository,
    String lecturerId, {
    int port = 8765,
  }) async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    if (_stopped) {
      await server.close(force: true);
      return;
    }
    _server = server;
    final service = FapImportService(repository, lecturerId);
    server.listen((request) => _handle(request, service));
  }

  Future<void> stop() async {
    _stopped = true;
    await _server?.close(force: true);
    _server = null;
    await _events.close();
  }

  Future<void> _handle(HttpRequest request, FapImportService service) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    void reply(int status, Map<String, dynamic> body) {
      response.statusCode = status;
      response.write(jsonEncode(body));
    }

    try {
      final origin = request.headers.value('origin');
      final allowed =
          origin == null ||
          RegExp(r'^chrome-extension://[a-p]{32}$').hasMatch(origin);
      if (!allowed) {
        reply(403, {
          'success': false,
          'message': 'Chỉ extension được kết nối.',
        });
        return;
      }
      if (origin != null) {
        response.headers.set('Access-Control-Allow-Origin', origin);
      }
      response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, POST, OPTIONS',
      );
      response.headers.set(
        'Access-Control-Allow-Headers',
        'Content-Type, X-FAP-Attendance-Client',
      );
      if (request.method == 'OPTIONS') {
        response.statusCode = 204;
        return;
      }
      if (request.method == 'GET' &&
          request.uri.path == '/api/integration/health') {
        reply(200, {
          'status': 'ok',
          'application': 'FAP Attendance Desktop',
          'protocolVersion': 1,
        });
        return;
      }
      if (request.method != 'POST' ||
          request.uri.path != '/api/integration/fap/session') {
        reply(404, {'success': false, 'message': 'Không tìm thấy endpoint.'});
        return;
      }
      if (request.headers.value('X-FAP-Attendance-Client') !=
              'browser-extension' ||
          request.headers.contentType?.mimeType != 'application/json') {
        reply(403, {
          'success': false,
          'message': 'Thiếu header của extension.',
        });
        return;
      }
      if (_importing) {
        reply(409, {
          'success': false,
          'message': 'Đang nhập một buổi học. Vui lòng đợi rồi gửi lại.',
        });
        return;
      }
      _importing = true;
      try {
        final bytes = <int>[];
        await for (final chunk in request.timeout(
          const Duration(seconds: 15),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            reply(413, {'success': false, 'message': 'Dữ liệu vượt quá 1 MB.'});
            return;
          }
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map<String, dynamic>) {
          throw const FormatException('Payload phải là object.');
        }
        final result = await service.importSession(FapImportDto.fromJson(json));
        reply(200, result.toJson());
        if (!_events.isClosed) _events.add(result);
      } finally {
        _importing = false;
      }
    } on FormatException catch (e) {
      reply(400, {'success': false, 'message': e.message});
    } on AppException catch (e) {
      reply(422, {'success': false, 'message': e.message});
    } catch (_) {
      reply(500, {
        'success': false,
        'message':
            'Không nhập được buổi học. Kiểm tra kết nối Sheets rồi gửi lại.',
      });
    } finally {
      await response.close();
    }
  }
}

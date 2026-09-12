import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';

typedef JsonRow = Map<String, dynamic>;

class GoogleSheetService {
  final Uri endpoint;
  final Future<String> Function() tokenProvider;
  final http.Client client;
  GoogleSheetService({
    required this.endpoint,
    required this.tokenProvider,
    http.Client? client,
  }) : client = client ?? http.Client() {
    if (endpoint.scheme != 'https' ||
        endpoint.host != 'script.google.com' ||
        !endpoint.path.endsWith('/exec')) {
      throw const AppException(
        'URL phải là Apps Script HTTPS deployment /exec.',
      );
    }
  }
  Future<dynamic> request(String action, [JsonRow payload = const {}]) async {
    final token = await tokenProvider();
    final req = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({...payload, 'action': action, 'idToken': token});
    var response = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    // Apps Script ContentService returns the result through a one-use GET URL.
    if ([302, 303].contains(response.statusCode)) {
      final target = Uri.tryParse(response.headers['location'] ?? '');
      if (target == null ||
          target.scheme != 'https' ||
          target.host != 'script.googleusercontent.com') {
        throw const AppException('Apps Script chuyển hướng không hợp lệ.');
      }
      response = await client.get(target).timeout(const Duration(seconds: 30));
    }
    if (response.statusCode != 200) {
      throw const AppException(
        'Không kết nối được Google Sheets. Thử tải lại.',
      );
    }
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw const AppException(
        'API không trả JSON. Kiểm tra quyền truy cập và deployment Apps Script.',
      );
    }
    if (data is! Map || data['ok'] != true) {
      throw AppException(
        data is Map
            ? '${data['error'] ?? 'Yêu cầu thất bại.'}'
            : 'Phản hồi API không hợp lệ.',
      );
    }
    return data['data'];
  }

  Future<List<JsonRow>> getRows(String sheet) async =>
      (await request('getRows', {'sheet': sheet}) as List)
          .map((r) => JsonRow.from(r as Map))
          .toList();
  Future<void> appendRow(String sheet, JsonRow row) async {
    await request('appendRow', {'sheet': sheet, 'row': row});
  }

  Future<void> updateRow(String sheet, String id, JsonRow row) async {
    await request('updateRow', {'sheet': sheet, 'id': id, 'row': row});
  }

  Future<void> deleteRow(String sheet, String id) async {
    await request('deleteRow', {'sheet': sheet, 'id': id});
  }

  Future<void> batchUpdate(String sheet, List<JsonRow> rows) async {
    await request('batchUpdate', {'sheet': sheet, 'rows': rows});
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../core/app_config.dart';

/// System browser + loopback + PKCE. Only refresh tokens are persisted.
class GoogleOAuthService {
  final http.Client client;
  final FlutterSecureStorage storage;
  String? _idToken, _refreshToken;
  DateTime _expires = DateTime(2000);
  bool _remember = false;
  Future<String>? _refreshing;
  GoogleOAuthService({http.Client? client, FlutterSecureStorage? storage})
    : client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();
  String get _storageKey => 'fap.refresh.${AppConfig.clientId}';
  String _random() => base64UrlEncode(
    List.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  Future<void> login({required bool remember}) async {
    if (!AppConfig.configured) {
      throw const AppException(
        'Chưa cấu hình Google OAuth / Apps Script. Xem README.',
      );
    }
    await logout();
    _remember = remember;
    final verifier = _random();
    final state = _random();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final completer = Completer<String>();
    final subscription = server.listen((request) async {
      final query = request.uri.queryParameters;
      if (request.uri.path != '/' || query['state'] != state) {
        request.response.statusCode = 400;
        request.response.write('Invalid OAuth callback.');
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><body>You may return to FAP Attendance.</body></html>',
      );
      await request.response.close();
      if (completer.isCompleted) return;
      if (query['error'] != null || query['code'] == null) {
        completer.completeError(
          const AppException('Đăng nhập Google đã bị hủy.'),
        );
      } else {
        completer.complete(query['code']);
      }
    });
    try {
      final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': AppConfig.clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': state,
        'code_challenge': base64UrlEncode(
          sha256.convert(ascii.encode(verifier)).bytes,
        ).replaceAll('=', ''),
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent select_account',
      });
      // Attach the error handler before a very fast browser callback can arrive.
      final codeFuture = completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw const AppException(
          'Hết thời gian đăng nhập. Vui lòng thử lại.',
        ),
      );
      // Observe early callback errors while the browser launcher is still pending.
      unawaited(
        codeFuture.then<void>((_) {}, onError: (Object e, StackTrace s) {}),
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        // Avoid leaving an unobserved timed future on a launch failure.
        if (!completer.isCompleted) completer.complete('');
        await codeFuture;
        throw const AppException('Không mở được trình duyệt.');
      }
      final code = await codeFuture;
      await _exchange({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirect,
        'code_verifier': verifier,
      });
    } finally {
      if (!completer.isCompleted) completer.complete('');
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<void> _exchange(Map<String, String> fields) async {
    final response = await client
        .post(
          Uri.https('oauth2.googleapis.com', '/token'),
          body: {
            ...fields,
            'client_id': AppConfig.clientId,
            if (AppConfig.clientSecret.isNotEmpty)
              'client_secret': AppConfig.clientSecret,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      if (response.statusCode == 400 || response.statusCode == 401) {
        await logout();
      }
      throw const AppException(
        'Không thể cấp/gia hạn phiên Google. Vui lòng đăng nhập lại.',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['id_token'] is! String) {
      throw const AppException('Google không trả về ID token.');
    }
    _idToken = data['id_token'] as String;
    _refreshToken = data['refresh_token'] as String? ?? _refreshToken;
    _expires = DateTime.now().add(
      Duration(seconds: (data['expires_in'] as num).toInt() - 60),
    );
    if (_remember && _refreshToken != null) {
      await storage.write(key: _storageKey, value: _refreshToken);
    }
  }

  Future<bool> restore() async {
    _refreshToken = await storage.read(key: _storageKey);
    if (_refreshToken == null) return false;
    _remember = true;
    await idToken();
    return true;
  }

  Future<String> idToken() async {
    if (_idToken != null && DateTime.now().isBefore(_expires)) return _idToken!;
    if (_refreshToken == null) {
      throw const AppException('Vui lòng đăng nhập lại.');
    }
    return _refreshing ??= _refresh();
  }

  Future<String> _refresh() async {
    try {
      await _exchange({
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
      });
      return _idToken!;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> logout() async {
    _idToken = null;
    _refreshToken = null;
    _expires = DateTime(2000);
    await storage.delete(key: _storageKey);
  }
}

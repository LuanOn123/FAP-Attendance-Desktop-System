import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SessionQrDisplayWidget extends StatefulWidget {
  final String sessionId, initialToken, initialSecretCode;
  final Future<void> Function(String, String) onRotateToken;
  const SessionQrDisplayWidget({
    super.key,
    required this.sessionId,
    required this.initialToken,
    required this.initialSecretCode,
    required this.onRotateToken,
  });
  @override
  State<SessionQrDisplayWidget> createState() => _SessionQrDisplayWidgetState();
}

class _SessionQrDisplayWidgetState extends State<SessionQrDisplayWidget> {
  late String token, secret;
  static const lifetime = 120;
  int seconds = lifetime;
  bool busy = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    token = widget.initialToken;
    secret = widget.initialSecretCode;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || busy || error != null) return;
      if (seconds > 1) {
        setState(() => seconds--);
      } else {
        rotate();
      }
    });
  }

  Future<void> rotate({bool? enableSecret}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final random = Random.secure();
    final nextToken = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final nextSecret = (enableSecret ?? secret.isNotEmpty)
        ? (100000 + random.nextInt(900000)).toString()
        : '';
    try {
      await widget.onRotateToken(nextToken, nextSecret);
      if (mounted) {
        setState(() {
          token = nextToken;
          secret = nextSecret;
          seconds = lifetime;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Chưa cập nhật được mã. Kiểm tra mạng và bấm thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = Uri.https('fap-attendance-cba45.web.app', '/checkin', {
      'sessionId': widget.sessionId,
      'token': token,
    });
    return SizedBox(
      width: 370,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'QUÉT MÃ ĐIỂM DANH',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Đăng nhập email trường để xác nhận có mặt.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (error == null)
                QrImageView(
                  data: url.toString(),
                  size: 260,
                  backgroundColor: Colors.white,
                )
              else
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: seconds / lifetime),
              const SizedBox(height: 8),
              Text('Đổi mã sau: ${seconds}s'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mở Secret Code'),
                subtitle: const Text(
                  'Sinh viên có thể chọn nhập mã thay cho QR',
                ),
                value: secret.isNotEmpty,
                onChanged: busy ? null : (value) => rotate(enableSecret: value),
              ),
              if (secret.isNotEmpty)
                SelectableText(
                  secret,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineLarge?.copyWith(letterSpacing: 6),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => rotate(),
                icon: const Icon(Icons.refresh),
                label: Text(
                  busy
                      ? 'Đang cập nhật…'
                      : error == null
                      ? 'Đổi mã ngay'
                      : 'Thử lại',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SessionQrDisplayWidget extends StatefulWidget {
  final String sessionId;
  final String initialToken;
  final String initialSecretCode;
  final Future<void> Function(String newToken, String newSecretCode)
  onRotateToken;

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
  late String currentToken;
  late String currentSecretCode;
  static const int totalSeconds = 30;
  int countdownSeconds = totalSeconds;
  Timer? _timer;
  bool isRotating = false;
  bool isPaused = false;

  @override
  void initState() {
    super.initState();
    currentToken = widget.initialToken;
    currentSecretCode = widget.initialSecretCode;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || isPaused) return;
      if (countdownSeconds > 1) {
        setState(() {
          countdownSeconds--;
        });
      } else {
        _rotateToken();
      }
    });
  }

  Future<void> _rotateToken() async {
    if (isRotating) return;
    setState(() => isRotating = true);

    final newToken = 'TKN_${DateTime.now().millisecondsSinceEpoch}';
    final newSecret =
        (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();

    try {
      await widget.onRotateToken(newToken, newSecret);
      if (mounted) {
        setState(() {
          currentToken = newToken;
          currentSecretCode = newSecret;
          countdownSeconds = totalSeconds;
        });
      }
    } catch (_) {
      // Keep running countdown even if network update experienced lag
      if (mounted) {
        setState(() {
          currentToken = newToken;
          currentSecretCode = newSecret;
          countdownSeconds = totalSeconds;
        });
      }
    } finally {
      if (mounted) setState(() => isRotating = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qrData = Uri.https('fap-attendance-cba45.web.app', '/checkin', {
      'sessionId': widget.sessionId,
      'token': currentToken,
    }).toString();

    final progress = countdownSeconds / totalSeconds;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppPalette.orangeSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    color: AppPalette.orangeDark,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'QUÉT MÃ QR ĐIỂM DANH',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 250.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 320,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
              ),
              child: Column(
                children: [
                  const Text(
                    'SECRET CODE (NHẬP TRÊN ĐIỆN THOẠI):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.orangeDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentSecretCode,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: AppPalette.orangeDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 340,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        countdownSeconds <= 20
                            ? Colors.red
                            : AppPalette.orangeDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: countdownSeconds <= 20
                                  ? Colors.red
                                  : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                isPaused
                                    ? 'Đang tạm dừng'
                                    : 'Đổi mã sau: ${countdownSeconds}s',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: countdownSeconds <= 20
                                      ? Colors.red
                                      : Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: isPaused ? 'Tiếp tục' : 'Tạm dừng',
                            onPressed: () =>
                                setState(() => isPaused = !isPaused),
                            icon: Icon(
                              isPaused ? Icons.play_arrow : Icons.pause,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Đổi mã ngay',
                            onPressed: isRotating ? null : _rotateToken,
                            icon: isRotating
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh, color: Colors.blue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../core/app_config.dart';
import 'auth_controller.dart';
import '../../shared/widgets/section_header.dart';

class LoginScreen extends StatefulWidget {
  final AuthController auth;
  const LoginScreen({super.key, required this.auth});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool remember = true;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: SizedBox(
          width: 540,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    eyebrow: 'FAP • GIẢNG VIÊN',
                    title: 'Xin chào, thầy cô.',
                    subtitle: 'Lịch dạy rõ ràng. Điểm danh nhẹ nhàng.',
                  ),
                  const SizedBox(height: 28),
                  const Icon(
                    Icons.fact_check_outlined,
                    size: 54,
                    color: AppPalette.orange,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'FAP Attendance',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Không gian quản lý lịch dạy và điểm danh',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Đăng nhập giảng viên',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text('Sử dụng tài khoản email trường để tiếp tục.'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    onChanged: widget.auth.busy
                        ? null
                        : (v) => setState(() => remember = v!),
                    title: const Text('Ghi nhớ phiên trên máy này'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (widget.auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        widget.auth.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (widget.auth.busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        widget.auth.busy ||
                            !AppConfig.configured ||
                            AppConfig.demo
                        ? null
                        : () => widget.auth.login(remember),
                    icon: const Icon(Icons.login),
                    label: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Tiếp tục với Google'),
                    ),
                  ),
                  if (!AppConfig.configured && !AppConfig.demo)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Chưa cấu hình kết nối. Xem README.md để thiết lập Google OAuth và Apps Script.',
                      ),
                    ),
                  if (AppConfig.demo) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: widget.auth.busy
                          ? null
                          : widget.auth.demoLogin,
                      child: const Text('Vào bản demo ngoại tuyến'),
                    ),
                    const Text(
                      'DEMO • Dữ liệu mẫu lưu trong bộ nhớ, mất khi tắt ứng dụng.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/foundation.dart';
import '../../core/app_config.dart';
import '../../models/lecturer.dart';
import '../../services/google_oauth_service.dart';
import '../../services/google_sheet_service.dart';

class AuthController extends ChangeNotifier {
  final GoogleOAuthService oauth;
  final GoogleSheetService? sheets;
  Lecturer? lecturer;
  bool busy = false;
  String? error;
  AuthController(this.oauth, this.sheets);
  Future<void> _profile() async {
    final data = await sheets!.request('profile');
    final profile = Lecturer.fromJson(Map<String, dynamic>.from(data as Map));
    if (!isSchoolEmail(profile.email, AppConfig.domainList)) {
      throw const AppException('Email không thuộc domain trường đã cấu hình.');
    }
    lecturer = profile;
  }

  Future<void> restore() => _run(() async {
    if (!AppConfig.demo && sheets != null && await oauth.restore()) {
      await _profile();
    }
  });
  Future<void> login(bool remember) => _run(() async {
    await oauth.login(remember: remember);
    await _profile();
  });
  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      lecturer = null;
      error = e is AppException
          ? e.message
          : 'Không thể đăng nhập. Kiểm tra mạng và cấu hình rồi thử lại.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void demoLogin() {
    if (!AppConfig.demo) return;
    lecturer = const Lecturer(
      lecturerId: 'demo-lecturer',
      lecturerCode: 'GV-DEMO',
      fullName: 'Giảng viên Demo',
      email: 'demo@fpt.edu.vn',
      department: 'Công nghệ thông tin',
    );
    error = null;
    notifyListeners();
  }

  Future<void> logout() async {
    lecturer = null;
    error = null;
    notifyListeners();
    try {
      await oauth.logout();
    } catch (_) {
      error =
          'Không xóa được phiên đã nhớ trong Windows. Vui lòng thử đăng xuất lại.';
      notifyListeners();
    }
  }
}

import 'package:flutter/material.dart';
import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/schedule/schedule_screen.dart';
import 'repositories/schedule_repository.dart';
import 'services/google_oauth_service.dart';
import 'services/google_sheet_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final oauth = GoogleOAuthService();
  final sheets = AppConfig.configured
      ? GoogleSheetService(
          endpoint: Uri.parse(AppConfig.scriptUrl),
          tokenProvider: oauth.idToken,
        )
      : null;
  final auth = AuthController(oauth, sheets);
  runApp(
    FapApp(
      auth: auth,
      repository: AppConfig.demo
          ? DemoScheduleRepository()
          : sheets != null
          ? SheetScheduleRepository(sheets)
          : null,
    ),
  );
  auth.restore();
}

class FapApp extends StatelessWidget {
  final AuthController auth;
  final ScheduleRepository? repository;
  const FapApp({super.key, required this.auth, required this.repository});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FAP Attendance',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routes: {
      '/': (_) => ListenableBuilder(
        listenable: auth,
        builder: (context, _) => auth.lecturer == null
            ? LoginScreen(auth: auth)
            : ScheduleScreen(
                key: ValueKey(auth.lecturer!.lecturerId),
                lecturer: auth.lecturer!,
                repository: repository!,
                onLogout: auth.logout,
              ),
      ),
    },
  );
}

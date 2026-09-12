class AppConfig {
  static const clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
  static const scriptUrl = String.fromEnvironment('APPS_SCRIPT_URL');
  static const demo = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
  static const domainList = String.fromEnvironment(
    'SCHOOL_DOMAINS',
    defaultValue: 'fpt.edu.vn,fe.edu.vn',
  );
  static bool get configured =>
      clientId.isNotEmpty && Uri.tryParse(scriptUrl)?.scheme == 'https';
}

class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

bool isSchoolEmail(String email, String domains) {
  final parts = email.trim().toLowerCase().split('@');
  return parts.length == 2 &&
      parts.first.isNotEmpty &&
      domains
          .split(',')
          .map((d) => d.trim().toLowerCase())
          .contains(parts.last);
}

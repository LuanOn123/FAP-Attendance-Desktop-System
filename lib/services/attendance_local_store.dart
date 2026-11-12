import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AttendanceLocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAttendanceLocalStore implements AttendanceLocalStore {
  final FlutterSecureStorage storage;
  static Future<void> _pending = Future.value();
  SecureAttendanceLocalStore({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  // Windows secure storage updates a single shared file for all keys.
  Future<T> _run<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<String?> read(String key) => _run(() => storage.read(key: key));
  @override
  Future<void> write(String key, String value) =>
      _run(() => storage.write(key: key, value: value));
  @override
  Future<void> delete(String key) => _run(() => storage.delete(key: key));
}

class MemoryAttendanceLocalStore implements AttendanceLocalStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AttendanceLocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAttendanceLocalStore implements AttendanceLocalStore {
  final FlutterSecureStorage storage;
  SecureAttendanceLocalStore({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
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

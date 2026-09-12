import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';
import 'ocr_layout.dart';

class OcrResult {
  final String path, text;
  const OcrResult(this.path, this.text);
}

class OcrService {
  Future<OcrResult?> pickAndRecognize() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
      allowMultiple: false,
    );
    if (picked == null) return null;
    final path = picked.files.single.path;
    if (path == null) throw const AppException('Không đọc được đường dẫn ảnh.');
    return OcrResult(path, await recognize(path));
  }

  Future<String> recognize(String path) async {
    if (!Platform.isWindows) {
      throw const AppException(
        'OCR local hiện hỗ trợ Windows. Có thể nhập văn bản OCR hoặc nhập tay.',
      );
    }
    final file = File(path);
    if (!await file.exists() || await file.length() > 20 * 1024 * 1024) {
      throw const AppException('Ảnh không tồn tại hoặc lớn hơn 20 MB.');
    }
    final temp = await Directory.systemTemp.createTemp('fap_ocr_');
    Process? process;
    try {
      final script = File('${temp.path}/ocr.ps1');
      await script.writeAsString(
        await rootBundle.loadString('assets/ocr_windows.ps1'),
      );
      final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      process = await Process.start(
        '$windows/System32/WindowsPowerShell/v1.0/powershell.exe',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-ImagePath',
          file.absolute.path,
        ],
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 60),
      );
      final text = (await output).trim().replaceFirst('\uFEFF', '');
      await errors;
      if (text.isEmpty) {
        throw const AppException(
          'Windows OCR không chạy được. Kiểm tra Windows PowerShell và language pack OCR.',
        );
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (exitCode != 0 || data['ok'] != true) {
        throw AppException('OCR: ${data['error'] ?? 'Không đọc được ảnh.'}');
      }
      final raw = OcrLayout.reconstruct(data).trim();
      if (raw.isEmpty) {
        throw const AppException(
          'Không tìm thấy chữ trong ảnh. Chọn ảnh rõ hơn hoặc nhập tay.',
        );
      }
      return raw;
    } on TimeoutException {
      process?.kill();
      throw const AppException('OCR quá thời gian. Hãy thử ảnh nhỏ hơn.');
    } finally {
      process?.kill();
      await temp.delete(recursive: true);
    }
  }
}

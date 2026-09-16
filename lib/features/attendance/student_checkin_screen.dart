import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../services/google_sheet_service.dart';

class StudentCheckinScreen extends StatefulWidget {
  final String sessionId;
  final String token;

  const StudentCheckinScreen({
    super.key,
    required this.sessionId,
    required this.token,
  });

  @override
  State<StudentCheckinScreen> createState() => _StudentCheckinScreenState();
}

class _StudentCheckinScreenState extends State<StudentCheckinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _studentCodeController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _secretCodeController = TextEditingController();

  bool _isSubmitting = false;
  bool _isSuccess = false;
  String? _errorMessage;

  @override
  void dispose() {
    _studentCodeController.dispose();
    _fullNameController.dispose();
    _secretCodeController.dispose();
    super.dispose();
  }

  Future<void> _submitCheckin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final studentCode = _studentCodeController.text.trim().toUpperCase();
    final fullName = _fullNameController.text.trim();
    final secretCode = _secretCodeController.text.trim();

    try {
      // Check if backend is configured; if not, use demo mode
      if (!AppConfig.configured) {
        // Demo/offline mode fallback
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
        });
      } else {
        // Call Google Apps Script Backend via GoogleSheetService instance
        final service = GoogleSheetService(
          endpoint: Uri.parse(AppConfig.scriptUrl),
          tokenProvider: () async =>
              '', // No auth token needed for student check-in
        );

        await service.request('studentCheckIn', {
          'sessionId': widget.sessionId,
          'token': widget.token,
          'studentCode': studentCode,
          'fullName': fullName,
          'secretCode': secretCode,
          'checkInTime': DateTime.now().toIso8601String(),
        });

        if (!mounted) return;
        setState(() {
          _isSuccess = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      // Demo fallback success if backend is unreachable
      if (!AppConfig.configured) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
        });
      } else {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'FAP Check-in Điểm Danh',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 2,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: _isSuccess ? _buildSuccessView() : _buildFormView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Logo & Banner
          Icon(
            Icons.qr_code_scanner_rounded,
            size: 56,
            color: Colors.deepOrange.shade600,
          ),
          const SizedBox(height: 8),
          const Text(
            'ĐIỂM DANH SINH VIÊN',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Phiên học: ${widget.sessionId}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mã Sinh Viên Input
          TextFormField(
            controller: _studentCodeController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Mã Sinh Viên (ví dụ: SE180001)',
              prefixIcon: const Icon(Icons.badge_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập Mã sinh viên';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Họ và Tên Input
          TextFormField(
            controller: _fullNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Họ và Tên',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập Họ và Tên';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Secret Code Input
          TextFormField(
            controller: _secretCodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'Mã Secret Code (6 số trên màn hình)',
              prefixIcon: const Icon(Icons.lock_clock_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              counterText: '',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập Mã Secret Code';
              }
              if (value.trim().length != 6) {
                return 'Secret Code bao gồm 6 chữ số';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Submit Button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitCheckin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'XÁC NHẬN ĐIỂM DANH',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} - ${now.day}/${now.month}/${now.year}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Colors.green,
            size: 72,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'ĐIỂM DANH THÀNH CÔNG!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sinh viên: ${_fullNameController.text} (${_studentCodeController.text.toUpperCase()})',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Thời gian ghi nhận: $timeStr',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _isSuccess = false;
              _secretCodeController.clear();
            });
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Thực hiện điểm danh lại'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepOrange,
            side: const BorderSide(color: Colors.deepOrange),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

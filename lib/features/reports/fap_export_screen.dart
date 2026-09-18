import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/attendance_record.dart';
import '../../../models/class_model.dart';
import '../../../models/lecturer.dart';
import '../../../repositories/attendance_repository.dart';
import '../../../repositories/report_repository.dart';
import '../../../shared/widgets/section_header.dart';

/// Màn hình xuất file Excel FAP dựa trên dữ liệu điểm danh
class FapExportScreen extends StatefulWidget {
  final Lecturer lecturer;
  final List<ClassModel> classes;
  final AttendanceRepository attendanceRepository;
  final ReportRepository reportRepository;

  const FapExportScreen({
    super.key,
    required this.lecturer,
    required this.classes,
    required this.attendanceRepository,
    required this.reportRepository,
  });

  @override
  State<FapExportScreen> createState() => _FapExportScreenState();
}

class _FapExportScreenState extends State<FapExportScreen> {
  // Step: 0 = chọn lớp & template, 1 = preview, 2 = export done
  int _step = 0;
  ClassModel? _selectedClass;
  String? _templatePath;
  String? _templateName;
  List<AttendanceRecord> _exportRecords = [];
  bool _loading = false;
  String? _error;
  String? _exportedPath;

  final _steps = ['Chọn lớp & Template', 'Preview dữ liệu', 'Xuất file'];

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) _selectedClass = widget.classes.first;
  }

  Future<void> _pickTemplate() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Chọn template Excel FAP',
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _templatePath = file.path;
          _templateName = file.name;
        });
      }
    } catch (e) {
      _showError('Không thể mở file picker. Thử lại.');
    }
  }

  Future<void> _loadPreview() async {
    if (_selectedClass == null) {
      _showError('Vui lòng chọn lớp trước.');
      return;
    }
    if (_templatePath == null) {
      _showError('Vui lòng chọn file template FAP trước.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await widget.reportRepository.getExportRecords(
        classId: _selectedClass!.classId,
        semester: _selectedClass!.semester,
      );
      if (mounted) {
        setState(() {
          _exportRecords = records;
          _step = 1;
        });
      }
    } catch (e) {
      _showError('Không tải được dữ liệu điểm danh.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doExport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Tạo nội dung CSV (có thể mở rộng sang xlsx với package archive+xml)
      final csvLines = StringBuffer();
      csvLines.writeln('MSSV,Họ và tên,Trạng thái,Thời gian Check-in,Ghi chú');
      for (final r in _exportRecords) {
        String time = r.checkInTime.isEmpty ? '' : r.checkInTime;
        try {
          if (time.isNotEmpty) {
            final dt = DateTime.parse(time).toLocal();
            time =
                '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }
        } catch (_) {}
        final status = switch (r.status) {
          'PRESENT' => 'P',
          'LATE' => 'L',
          _ => 'A',
        };
        final name = r.fullName.replaceAll(',', ' ');
        final note = r.note.replaceAll(',', ' ');
        csvLines.writeln(
            '${r.studentCode},$name,$status,$time,$note');
      }

      // Chọn nơi lưu
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu file điểm danh FAP',
        fileName:
            'FAP_${_selectedClass!.subjectCode}_${_selectedClass!.classCode}_${_selectedClass!.semester}.csv',
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );

      if (savePath != null) {
        final file = File(savePath);
        await file.writeAsString(csvLines.toString(), flush: true);
        if (mounted) {
          setState(() {
            _exportedPath = savePath;
            _step = 2;
          });
        }
      }
    } catch (e) {
      _showError('Xuất file thất bại: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    setState(() => _error = msg);
  }

  void _reset() {
    setState(() {
      _step = 0;
      _exportRecords = [];
      _exportedPath = null;
      _error = null;
    });
  }

  Color _statusColor(String s) => switch (s) {
        'PRESENT' => Colors.green.shade700,
        'LATE' => Colors.orange.shade700,
        _ => Colors.red.shade600,
      };

  String _statusLabel(String s) => switch (s) {
        'PRESENT' => 'P – Có mặt',
        'LATE' => 'L – Đi muộn',
        _ => 'A – Vắng mặt',
      };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SectionHeader(
          eyebrow: 'XUẤT FILE ĐIỂM DANH',
          title: 'FAP Excel Export',
          subtitle:
              'Chọn lớp và file template FAP, xem preview dữ liệu rồi xuất ra file CSV/Excel để nộp lên hệ thống FAP.',
        ),
        const SizedBox(height: 24),

        // Stepper indicator
        _buildStepper(),
        const SizedBox(height: 28),

        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _error = null),
                ),
              ],
            ),
          ),

        // Step content
        if (_step == 0) _buildStep0(),
        if (_step == 1) _buildStep1(),
        if (_step == 2) _buildStep2(),

        if (_loading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Widget _buildStepper() {
    return Row(
      children: _steps.asMap().entries.map((entry) {
        final idx = entry.key;
        final label = entry.value;
        final isActive = _step == idx;
        final isDone = _step > idx;

        return Expanded(
          child: Row(
            children: [
              if (idx > 0)
                Expanded(
                  child: Divider(
                    color: isDone ? AppPalette.orange : Colors.grey.shade300,
                    thickness: 2,
                  ),
                ),
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDone
                          ? AppPalette.orange
                          : isActive
                              ? AppPalette.orangeSoft
                              : Colors.grey.shade100,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (isActive || isDone)
                            ? AppPalette.orange
                            : Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isDone
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : Text(
                              '${idx + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isActive
                                    ? AppPalette.orangeDark
                                    : Colors.grey.shade500,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive
                          ? AppPalette.orangeDark
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (idx < _steps.length - 1) const SizedBox(width: 4),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStep0() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppPalette.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Class selector
            Text(
              '1. Chọn lớp học',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<ClassModel>(
                key: ValueKey('cls_${_selectedClass?.classId}'),
                initialValue: _selectedClass,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Lớp học',
                  prefixIcon: Icon(Icons.class_outlined),
                ),
                items: widget.classes
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(
                          '${c.subjectCode} – ${c.classCode} (${c.semester})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (c) => setState(() => _selectedClass = c),
              ),
            ),
            const SizedBox(height: 28),

            // Template picker
            Text(
              '2. Chọn file template Excel FAP',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Chọn file .xlsx hoặc .csv từ FAP làm template. Hệ thống sẽ đọc MSSV từ template và điền trạng thái tương ứng.',
              style: TextStyle(color: AppPalette.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickTemplate,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Chọn file template'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                ),
                const SizedBox(width: 16),
                if (_templateName != null)
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _templateName!,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 32),

            // Note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ký hiệu xuất ra: P = Có mặt (Present), L = Đi muộn (Late), A = Vắng mặt (Absent). '
                      'Không thay đổi cấu trúc cột nếu FAP yêu cầu format cố định.',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Next button
            FilledButton.icon(
              onPressed: (_loading || _selectedClass == null || _templateName == null)
                  ? null
                  : _loadPreview,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Tiếp theo: Preview dữ liệu'),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.orange,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    final presentCount = _exportRecords.where((r) => r.isPresent).length;
    final lateCount = _exportRecords.where((r) => r.isLate).length;
    final absentCount = _exportRecords.where((r) => r.isAbsent).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary stats
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ExportStat(
              label: 'Tổng bản ghi',
              value: '${_exportRecords.length}',
              color: AppPalette.orange,
              icon: Icons.people_outline,
            ),
            _ExportStat(
              label: 'Có mặt (P)',
              value: '$presentCount',
              color: Colors.green.shade700,
              icon: Icons.check_circle_outline,
            ),
            _ExportStat(
              label: 'Đi muộn (L)',
              value: '$lateCount',
              color: Colors.orange.shade700,
              icon: Icons.access_time,
            ),
            _ExportStat(
              label: 'Vắng (A)',
              value: '$absentCount',
              color: Colors.red.shade600,
              icon: Icons.cancel_outlined,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Preview table
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppPalette.line),
          ),
          child: Column(
            children: [
              // Header
              Container(
                color: AppPalette.orangeSoft,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: const [
                    _EH('MSSV', flex: 2),
                    _EH('Họ và tên', flex: 3),
                    _EH('Ký hiệu FAP', flex: 2),
                    _EH('Thời gian', flex: 3),
                    _EH('Ghi chú', flex: 3),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _exportRecords.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  final r = _exportRecords[idx];
                  String timeStr = '—';
                  if (r.checkInTime.isNotEmpty) {
                    try {
                      final dt = DateTime.parse(r.checkInTime).toLocal();
                      timeStr =
                          '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    } catch (_) {
                      timeStr = r.checkInTime;
                    }
                  }
                  final statusCode = switch (r.status) {
                    'PRESENT' => 'P',
                    'LATE' => 'L',
                    _ => 'A',
                  };
                  final color = _statusColor(r.status);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            r.studentCode,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            r.fullName.isNotEmpty ? r.fullName : '—',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: color.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  statusCode,
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _statusLabel(r.status),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppPalette.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            r.note.isNotEmpty ? r.note : '—',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppPalette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _step = 0;
                _exportRecords = [];
              }),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Quay lại'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _doExport,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Xuất file CSV'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Center(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.green.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green.shade600,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Xuất file thành công!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
              ),
              const SizedBox(height: 12),
              if (_exportedPath != null)
                SelectableText(
                  _exportedPath!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppPalette.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Xuất lớp khác'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _ExportStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ],
    ),
  );
}

class _EH extends StatelessWidget {
  final String text;
  final int flex;
  const _EH(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppPalette.orangeDark,
        letterSpacing: 0.6,
      ),
    ),
  );
}

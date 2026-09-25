import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/attendance_record.dart';
import '../../../models/class_model.dart';

/// Bảng hiển thị danh sách sinh viên đã điểm danh (hoặc vắng mặt)
class ReportTable extends StatelessWidget {
  final List<AttendanceRecord> records;
  final ClassModel? selectedClass;
  final bool loading;
  final void Function(int index) onEdit;

  const ReportTable({
    super.key,
    required this.records,
    required this.selectedClass,
    required this.loading,
    required this.onEdit,
  });

  Color _statusColor(String s) => switch (s) {
    'PRESENT' => Colors.green.shade700,
    'LATE' => Colors.orange.shade700,
    _ => Colors.red.shade600,
  };

  String _statusLabel(String s) => switch (s) {
    'PRESENT' => 'Có mặt',
    'LATE' => 'Đi muộn',
    'ABSENT' => 'Vắng',
    _ => 'Chưa xác nhận',
  };

  String _fapCode(String s) => switch (s) {
    'PRESENT' => 'P',
    'LATE' => 'L',
    'ABSENT' => 'A',
    _ => '—',
  };

  String _formatTime(String rawTime) {
    if (rawTime.isEmpty) return '—';
    try {
      final dt = DateTime.parse(rawTime).toUtc().add(const Duration(hours: 7));
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return rawTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              selectedClass == null
                  ? 'Chọn lớp học để xem danh sách điểm danh.'
                  : 'Chưa có dữ liệu báo cáo để hiển thị.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppPalette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Table header
          Container(
            color: AppPalette.orangeSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                _TH('MSSV', flex: 2),
                _TH('Họ và tên', flex: 3),
                _TH('Lớp học', flex: 2),
                _TH('Check-in', flex: 3),
                _TH('Trạng thái', flex: 2),
                _TH('FAP', flex: 1),
                _TH('Ghi chú', flex: 3),
                SizedBox(width: 40),
              ],
            ),
          ),
          const Divider(height: 1),
          // Rows
          Expanded(
            child: ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (_, idx) => _buildRow(idx),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int idx) {
    final r = records[idx];
    final color = _statusColor(r.status);
    final classCode = selectedClass?.classCode ?? '—';
    final timeStr = _formatTime(r.checkInTime);

    return InkWell(
      onTap: () => onEdit(idx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // MSSV
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
            // Name
            Expanded(
              flex: 3,
              child: Text(
                r.fullName.isNotEmpty ? r.fullName : '—',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            // Lớp học
            Expanded(
              flex: 2,
              child: Text(
                classCode,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppPalette.orangeDark,
                ),
              ),
            ),
            // Time
            Expanded(
              flex: 3,
              child: Text(
                timeStr,
                style: const TextStyle(fontSize: 12, color: AppPalette.muted),
              ),
            ),
            // Status badge
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _statusLabel(r.status),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            // FAP code
            Expanded(
              flex: 1,
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _fapCode(r.status),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Note
            Expanded(
              flex: 3,
              child: Text(
                r.note.isNotEmpty ? r.note : '—',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            // Edit action
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Chỉnh sửa trạng thái',
              onPressed: () => onEdit(idx),
            ),
          ],
        ),
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  final int flex;
  const _TH(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: AppPalette.orangeDark,
        ),
      ),
    );
  }
}

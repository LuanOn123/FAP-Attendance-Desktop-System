import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/attendance_record.dart';
import '../../../core/app_config.dart';

/// Dialog cho phép giảng viên chỉnh sửa trạng thái điểm danh thủ công
class ManualUpdateDialog extends StatefulWidget {
  final AttendanceRecord record;
  final Future<void> Function(String status, String note) onSave;

  const ManualUpdateDialog({
    super.key,
    required this.record,
    required this.onSave,
  });

  @override
  State<ManualUpdateDialog> createState() => _ManualUpdateDialogState();
}

class _ManualUpdateDialogState extends State<ManualUpdateDialog> {
  late String _selectedStatus;
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.record.status;
    _noteCtrl.text = widget.record.note;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String s) => switch (s) {
    'PRESENT' => Colors.green,
    'LATE' => Colors.orange,
    _ => Colors.red.shade700,
  };

  IconData _statusIcon(String s) => switch (s) {
    'PRESENT' => Icons.check_circle,
    'LATE' => Icons.access_time,
    _ => Icons.cancel,
  };

  String _statusLabel(String s) => switch (s) {
    'PRESENT' => 'Có mặt',
    'LATE' => 'Đi muộn',
    _ => 'Vắng mặt',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: AppPalette.orange),
          const SizedBox(width: 10),
          const Text('Cập nhật trạng thái'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppPalette.line),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppPalette.orange,
                    foregroundColor: Colors.white,
                    child: Text(
                      widget.record.fullName.isNotEmpty
                          ? widget.record.fullName[0]
                          : 'S',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.record.fullName.isNotEmpty
                              ? widget.record.fullName
                              : widget.record.studentCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'MSSV: ${widget.record.studentCode}',
                          style: TextStyle(
                            color: AppPalette.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),

            // Status Selector
            const Text(
              'Trạng thái mới',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: ['PRESENT', 'LATE', 'ABSENT'].map((s) {
                final selected = _selectedStatus == s;
                final color = _statusColor(s);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedStatus = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withValues(alpha: 0.12)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? color : Colors.grey.shade200,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _statusIcon(s),
                              color: selected ? color : Colors.grey,
                              size: 22,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _statusLabel(s),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected ? color : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Note field
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Lý do / Ghi chú',
                hintText: 'Ví dụ: Nghỉ có phép, Đi thi khác...',
                prefixIcon: const Icon(Icons.note_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed:
              _saving ||
                  !['PRESENT', 'LATE', 'ABSENT'].contains(_selectedStatus)
              ? null
              : () async {
                  setState(() {
                    _saving = true;
                    _error = null;
                  });
                  try {
                    await widget.onSave(_selectedStatus, _noteCtrl.text.trim());
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (context.mounted) {
                      setState(() {
                        _saving = false;
                        _error = e is AppException
                            ? e.message
                            : 'Không lưu được thay đổi. Vui lòng thử lại.';
                      });
                    }
                  }
                },
          style: FilledButton.styleFrom(backgroundColor: AppPalette.orange),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save),
          label: const Text('Lưu thay đổi'),
        ),
      ],
    );
  }
}

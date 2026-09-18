import 'package:flutter/material.dart';
import '../../../core/app_config.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/attendance_record.dart';
import '../../../models/class_model.dart';
import '../../../models/lecturer.dart';
import '../../../repositories/attendance_repository.dart';
import '../../../shared/widgets/section_header.dart';
import 'widgets/manual_update_dialog.dart';

class HistoryScreen extends StatefulWidget {
  final Lecturer lecturer;
  final List<ClassModel> classes;
  final AttendanceRepository attendanceRepository;

  const HistoryScreen({
    super.key,
    required this.lecturer,
    required this.classes,
    required this.attendanceRepository,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<AttendanceRecord> _allRecords = [];
  bool _loading = false;
  String? _error;
  ClassModel? _selectedClass;

  // Filters
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _statusFilter; // null = tất cả
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) {
      _selectedClass = widget.classes.first;
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (_selectedClass == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await widget.attendanceRepository.getClassHistory(
        _selectedClass!.classId,
      );
      if (mounted) setState(() => _allRecords = records);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e is AppException ? e.message : 'Không tải được lịch sử.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AttendanceRecord> get _filteredRecords {
    return _allRecords.where((r) {
      // Status filter
      if (_statusFilter != null && r.status != _statusFilter) return false;
      // Search: MSSV or Name
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!r.studentCode.toLowerCase().contains(q) &&
            !r.fullName.toLowerCase().contains(q)) {
          return false;
        }
      }
      // Date range
      if (_fromDate != null || _toDate != null) {
        if (r.checkInTime.isEmpty) {
          if (_statusFilter != 'ABSENT') {
            return false;
          }
          return true;
        }
        try {
          final dt = DateTime.parse(r.checkInTime);
          if (_fromDate != null && dt.isBefore(_fromDate!)) return false;
          if (_toDate != null &&
              dt.isAfter(_toDate!.add(const Duration(days: 1)))) {
            return false;
          }
        } catch (_) {}
      }
      return true;
    }).toList();
  }

  Future<void> _openManualUpdate(AttendanceRecord record) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ManualUpdateDialog(
        record: record,
        onSave: (status, note) async {
          await widget.attendanceRepository.updateAttendanceStatus(
            attendanceId: record.attendanceId,
            status: status,
            note: note,
            updatedBy: widget.lecturer.email,
          );
          await _loadHistory();
        },
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật trạng thái điểm danh.')),
      );
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _fromDate = range.start;
        _toDate = range.end;
      });
    }
  }

  Color _statusColor(String s) => switch (s) {
        'PRESENT' => Colors.green,
        'LATE' => Colors.orange,
        _ => Colors.red.shade600,
      };

  String _statusLabel(String s) => switch (s) {
        'PRESENT' => 'Có mặt',
        'LATE' => 'Đi muộn',
        _ => 'Vắng',
      };

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SectionHeader(
          eyebrow: 'LỊCH SỬ ĐIỂM DANH',
          title: 'Tra cứu & Chỉnh sửa',
          subtitle:
              'Xem lịch sử điểm danh từng buổi, lọc theo sinh viên, trạng thái và ngày. Có thể chỉnh sửa thủ công.',
        ),
        const SizedBox(height: 24),

        // Filters
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppPalette.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Class picker
                SizedBox(
                  width: 230,
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
                              '${c.subjectCode} – ${c.classCode}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (c) {
                      setState(() {
                        _selectedClass = c;
                        _allRecords = [];
                      });
                      _loadHistory();
                    },
                  ),
                ),
                // Status filter chips
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in [null, 'PRESENT', 'LATE', 'ABSENT'])
                      ChoiceChip(
                        label: Text(s == null ? 'Tất cả' : _statusLabel(s)),
                        selected: _statusFilter == s,
                        onSelected: (_) => setState(() => _statusFilter = s),
                        selectedColor: s == null
                            ? AppPalette.orange.withValues(alpha: 0.15)
                            : _statusColor(s).withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: _statusFilter == s
                              ? (s == null
                                  ? AppPalette.orangeDark
                                  : _statusColor(s))
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                // Search
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'MSSV hoặc Tên...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                // Date range
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    _fromDate != null
                        ? '${_fromDate!.day}/${_fromDate!.month} – ${_toDate!.day}/${_toDate!.month}'
                        : 'Chọn khoảng ngày',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (_fromDate != null)
                  IconButton(
                    tooltip: 'Xóa bộ lọc ngày',
                    onPressed: () =>
                        setState(() => _fromDate = _toDate = null),
                    icon: const Icon(Icons.clear, size: 18),
                  ),
                IconButton(
                  tooltip: 'Tải lại',
                  onPressed: _loadHistory,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_loading)
          const LinearProgressIndicator()
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          )
        else if (_selectedClass == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('Chọn lớp để xem lịch sử điểm danh.'),
            ),
          )
        else if (filtered.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.history_toggle_off,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    _allRecords.isEmpty
                        ? 'Chưa có dữ liệu điểm danh cho lớp này.'
                        : 'Không tìm thấy kết quả phù hợp.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          _buildTable(filtered),
      ],
    );
  }

  Widget _buildTable(List<AttendanceRecord> records) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppPalette.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.table_rows_outlined, size: 18, color: AppPalette.orange),
                const SizedBox(width: 8),
                Text(
                  '${records.length} bản ghi',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Table Header
          Container(
            color: AppPalette.orangeSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: const [
                SizedBox(width: 48),
                _HeaderCell('MSSV', flex: 2),
                _HeaderCell('Họ và tên', flex: 3),
                _HeaderCell('Thời gian Check-in', flex: 3),
                _HeaderCell('Trạng thái', flex: 2),
                _HeaderCell('Ghi chú', flex: 3),
                SizedBox(width: 48),
              ],
            ),
          ),
          // Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) => _buildRow(records[idx]),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(AttendanceRecord r) {
    final color = _statusColor(r.status);
    String timeStr = '—';
    if (r.checkInTime.isNotEmpty) {
      try {
        final dt = DateTime.parse(r.checkInTime).toLocal();
        timeStr =
            '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        timeStr = r.checkInTime;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Text(
              r.fullName.isNotEmpty ? r.fullName[0] : 'S',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _Cell(r.studentCode, flex: 2, bold: true),
          _Cell(
            r.fullName.isNotEmpty ? r.fullName : '—',
            flex: 3,
          ),
          _Cell(timeStr, flex: 3, muted: true),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              r.note.isNotEmpty ? r.note : '—',
              style: TextStyle(
                color: r.note.isEmpty ? Colors.grey.shade400 : AppPalette.ink,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Chỉnh sửa trạng thái',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _openManualUpdate(r),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;
  const _HeaderCell(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppPalette.orangeDark,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _Cell extends StatelessWidget {
  final String text;
  final int flex;
  final bool bold;
  final bool muted;
  const _Cell(this.text, {required this.flex, this.bold = false, this.muted = false});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
        color: muted ? AppPalette.muted : AppPalette.ink,
      ),
    ),
  );
}

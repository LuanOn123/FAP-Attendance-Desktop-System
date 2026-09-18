import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/app_config.dart';
import '../../core/theme/app_palette.dart';
import '../../models/attendance_record.dart';
import '../../models/class_model.dart';
import '../../models/lecturer.dart';
import '../../models/roster.dart';
import '../../models/schedule.dart';
import '../../models/session_model.dart';
import '../../repositories/attendance_repository.dart';
import '../../repositories/schedule_repository.dart';
import '../../services/class_mapping_service.dart';
import '../../services/excel_export_service.dart';
import 'widgets/manual_update_dialog.dart';

/// Màn hình Báo cáo & Xuất file FAP (Member 4)
///
/// Flow: Chọn lớp → tự động chọn buổi học mới nhất (Thứ 2 / Thứ 5 / Slot tương ứng)
///       → hiển thị danh sách đã điểm danh qua QR theo lớp → chỉnh sửa nếu cần → xuất Excel/CSV cho FAP.
class AttendanceReportScreen extends StatefulWidget {
  final Lecturer lecturer;
  final List<ClassModel> classes;
  final List<Schedule> schedules;
  final AttendanceRepository attendanceRepository;
  final ScheduleRepository? scheduleRepository;

  const AttendanceReportScreen({
    super.key,
    required this.lecturer,
    required this.classes,
    required this.schedules,
    required this.attendanceRepository,
    this.scheduleRepository,
  });

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  ClassModel? _selectedClass;
  List<SessionModel> _sessions = [];
  List<RosterStudent> _roster = [];
  String? _selectedDateOption; // 'ALL' hoặc '${s.date}|${s.slot}'
  List<AttendanceRecord> _records = [];
  bool _loading = false;
  bool _exportingExcel = false;
  bool _exportingCsv = false;
  String? _error;

  List<ClassModel> get _mappedClasses {
    final svc = ClassMappingService();
    final mapped = widget.classes.where((c) {
      return widget.schedules.any(
        (s) => svc.map(s, widget.classes).mappedClass?.classId == c.classId,
      );
    }).toList();
    return mapped.isNotEmpty ? mapped : widget.classes;
  }

  /// Danh sách các buổi học (Ngày + Slot) duy nhất của lớp
  List<String> get _dateOptions {
    final Set<String> options = {};
    for (final s in _sessions) {
      options.add('${s.date}|${s.slot}');
    }
    final list = options.toList();
    list.sort((a, b) => b.compareTo(a)); // Mới nhất lên đầu
    return list;
  }

  String _formatOptionLabel(String opt) {
    final parts = opt.split('|');
    final dateStr = parts[0];
    final slotStr = parts.length > 1 ? parts[1] : '';
    try {
      final dt = DateTime.parse(dateStr);
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year.toString();
      return '$d/$m/$y (Slot $slotStr)';
    } catch (_) {
      return '$dateStr (Slot $slotStr)';
    }
  }

  final Map<String, List<AttendanceRecord>> _attendanceCache = {};

  @override
  void initState() {
    super.initState();
    final mapped = _mappedClasses;
    if (mapped.isNotEmpty) {
      _selectedClass = mapped.first;
      _loadAttendance();
    }
  }

  Future<void> _loadAttendance() async {
    if (_selectedClass == null) return;
    setState(() {
      _loading = true;
      _sessions = [];
      _roster = [];
      _records = [];
      _error = null;
      _attendanceCache.clear();
    });
    try {
      final cls = _selectedClass!;
      final classId = cls.classId.trim();
      final key = cls.key.trim();
      final classCode = cls.classCode.trim();
      final subjectCode = cls.subjectCode.trim();

      // 1. Tải danh sách các phiên học của lớp (truy vấn toàn bộ các mã định danh có thể có)
      final Set<String> sessionIds = {};
      final List<SessionModel> sessions = [];

      final targetsToTry = {
        if (classId.isNotEmpty && classId != 'null') classId,
        if (key.isNotEmpty) key,
        if (classCode.isNotEmpty) classCode,
        if (subjectCode.isNotEmpty && classCode.isNotEmpty)
          '$subjectCode-$classCode',
        if (subjectCode.isNotEmpty && classCode.isNotEmpty)
          '${subjectCode}_$classCode',
        if (subjectCode.isNotEmpty && classCode.isNotEmpty)
          '$subjectCode - $classCode',
      };

      for (final target in targetsToTry) {
        try {
          final list = await widget.attendanceRepository.getSessionsByClass(
            target,
          );
          for (final s in list) {
            if (sessionIds.add(s.sessionId)) sessions.add(s);
          }
        } catch (_) {}
      }

      sessions.sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        return b.slot.compareTo(a.slot);
      });

      // 2. Tải danh sách sinh viên theo lớp nếu có scheduleRepository
      List<RosterStudent> roster = [];
      if (widget.scheduleRepository != null) {
        try {
          final target = ClassTarget(
            semester: cls.semester,
            subjectCode: cls.subjectCode,
            classCode: cls.classCode,
            classId: cls.classId,
          );
          roster = await widget.scheduleRepository!.getRoster(target);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _roster = roster;
          final dateOpts = _dateOptions;
          if (dateOpts.isNotEmpty) {
            _selectedDateOption = dateOpts.first;
          } else {
            _selectedDateOption = null;
          }
        });

        if (sessions.isNotEmpty || roster.isNotEmpty) {
          await _loadRecordsForSelectedDate();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'Không tải được danh sách phiên học.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRecordsForSelectedDate() async {
    if (_selectedClass == null) {
      setState(() => _records = []);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      List<SessionModel> targetSessions = [];

      if (_selectedDateOption != null) {
        final parts = _selectedDateOption!.split('|');
        final targetDate = parts[0];
        final targetSlot = parts.length > 1 ? parts[1] : '';
        targetSessions = _sessions
            .where(
              (s) =>
                  s.date == targetDate &&
                  (targetSlot.isEmpty || s.slot.toString() == targetSlot),
            )
            .toList();
      } else {
        targetSessions = _sessions;
      }

      // Fetch attendance in parallel for targetSessions (sử dụng cache nếu đã tải)
      final List<AttendanceRecord> allRaw = [];
      final List<Future<List<AttendanceRecord>>> futures = [];

      for (final s in targetSessions) {
        if (_attendanceCache.containsKey(s.sessionId)) {
          allRaw.addAll(_attendanceCache[s.sessionId]!);
        } else {
          futures.add(
            widget.attendanceRepository
                .getSessionAttendance(s.sessionId)
                .then((list) {
                  _attendanceCache[s.sessionId] = list;
                  return list;
                })
                .catchError((_) => <AttendanceRecord>[]),
          );
        }
      }

      if (futures.isNotEmpty) {
        final results = await Future.wait(futures);
        for (final r in results) {
          allRaw.addAll(r);
        }
      }

      // Gộp các bản ghi QR theo MSSV
      final Map<String, AttendanceRecord> qrMerged = {};
      for (final r in allRaw) {
        final code = r.studentCode.trim().toUpperCase();
        if (code.isEmpty) continue;
        if (!qrMerged.containsKey(code)) {
          qrMerged[code] = r;
        } else {
          final existing = qrMerged[code]!;
          if (r.isPresent && !existing.isPresent) {
            qrMerged[code] = r;
          } else if (r.isLate && existing.isAbsent) {
            qrMerged[code] = r;
          } else if (r.status == existing.status && r.checkInTime.isNotEmpty) {
            if (existing.checkInTime.isEmpty ||
                r.checkInTime.compareTo(existing.checkInTime) < 0) {
              qrMerged[code] = r;
            }
          }
        }
      }

      List<AttendanceRecord> finalList = [];
      if (_roster.isNotEmpty) {
        // Lớp đã có danh sách sinh viên nhập từ markbook:
        // Khớp chính xác theo danh sách lớp này, loại bỏ các SV thuộc lớp khác
        for (final s in _roster) {
          final code = s.studentCode.trim().toUpperCase();
          if (qrMerged.containsKey(code)) {
            final rec = qrMerged[code]!;
            finalList.add(
              rec.copyWith(
                fullName: s.fullName.isNotEmpty ? s.fullName : rec.fullName,
              ),
            );
          } else {
            finalList.add(
              AttendanceRecord(
                attendanceId: 'absent-$code',
                sessionId: targetSessions.isNotEmpty
                    ? targetSessions.first.sessionId
                    : '',
                studentId: 'std-$code',
                studentCode: code,
                fullName: s.fullName,
                status: 'ABSENT',
                checkInTime: '',
                updatedAt: '',
                note: '',
                updatedBy: '',
              ),
            );
          }
        }
      } else {
        // Chưa nhập danh sách: hiển thị những sinh viên đã quét QR của phiên lớp này
        finalList = qrMerged.values.toList();
      }

      finalList.sort((a, b) => a.studentCode.compareTo(b.studentCode));

      if (mounted) {
        setState(() => _records = finalList);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'Không tải được danh sách điểm danh.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openManualUpdate(int idx) async {
    final record = _records[idx];
    final updated = await showDialog<bool>(
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
          if (mounted) {
            setState(() {
              _records[idx] = record.copyWith(
                status: status,
                note: note,
                updatedAt: DateTime.now().toIso8601String(),
                updatedBy: widget.lecturer.email,
              );
            });
          }
        },
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cập nhật trạng thái điểm danh.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatTime(String rawTime) {
    if (rawTime.isEmpty) return '—';
    try {
      final dt = DateTime.parse(rawTime).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return rawTime;
    }
  }

  String _currentExportDateTag() {
    if (_selectedDateOption != null && _selectedDateOption != 'ALL') {
      final parts = _selectedDateOption!.split('|');
      final d = parts[0];
      final s = parts.length > 1 ? '_Slot${parts[1]}' : '';
      return '$d$s';
    }
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _exportExcel() async {
    if (_records.isEmpty || _selectedClass == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingExcel = true);
    try {
      final cls = _selectedClass!;
      final dateTag = _currentExportDateTag();

      final headers = [
        'STT',
        'Lớp học',
        'Mã môn',
        'MSSV',
        'Họ và tên',
        'Thời gian check-in',
        'Trạng thái',
        'Ký hiệu FAP',
        'Ghi chú',
      ];

      final rows = <List<String>>[];
      for (int i = 0; i < _records.length; i++) {
        final r = _records[i];
        rows.add([
          '${i + 1}',
          cls.classCode,
          cls.subjectCode,
          r.studentCode,
          r.fullName,
          _formatTime(r.checkInTime),
          r.status, // Tiếng Anh (PRESENT, LATE, ABSENT)
          _fapCode(r.status),
          '', // Ghi chú để trống
        ]);
      }

      final bytes = ExcelExportService.generateXlsx(
        sheetName: 'DiemDanh_${cls.classCode}',
        headers: headers,
        rows: rows,
      );

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu file điểm danh Excel (.xlsx)',
        fileName: 'Diemdanh_${cls.subjectCode}_${cls.classCode}_$dateTag.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (savePath != null) {
        await File(savePath).writeAsBytes(bytes, flush: true);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Đã xuất file Excel: $savePath'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Xuất file Excel thất bại: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_records.isEmpty || _selectedClass == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingCsv = true);
    try {
      final cls = _selectedClass!;
      final dateTag = _currentExportDateTag();

      final buf = StringBuffer();
      buf.write('\uFEFF');
      buf.writeln(
        'STT,Lop hoc,Ma mon,MSSV,Ho ten,Thoi gian check-in,Trang thai,Ky hieu FAP,Ghi chu',
      );

      for (int i = 0; i < _records.length; i++) {
        final r = _records[i];
        final time = _formatTime(r.checkInTime).replaceAll(',', ' ');
        final name = r.fullName.replaceAll(',', ' ');
        final fap = _fapCode(r.status);
        final statusEnglish = r.status;
        const note = '';
        buf.writeln(
          '${i + 1},${cls.classCode},${cls.subjectCode},${r.studentCode},$name,$time,$statusEnglish,$fap,$note',
        );
      }

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu file điểm danh CSV (.csv)',
        fileName: 'Diemdanh_${cls.subjectCode}_${cls.classCode}_$dateTag.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (savePath != null) {
        await File(savePath).writeAsString(buf.toString(), flush: true);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Đã xuất file CSV: $savePath'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Xuất file CSV thất bại: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Color _statusColor(String s) => switch (s) {
    'PRESENT' => Colors.green.shade700,
    'LATE' => Colors.orange.shade700,
    _ => Colors.red.shade600,
  };

  String _statusLabel(String s) => switch (s) {
    'PRESENT' => 'Có mặt',
    'LATE' => 'Đi muộn',
    _ => 'Vắng',
  };

  String _fapCode(String s) => switch (s) {
    'PRESENT' => 'P',
    'LATE' => 'L',
    _ => 'A',
  };

  @override
  Widget build(BuildContext context) {
    final mappedClasses = _mappedClasses;
    final dateOpts = _dateOptions;
    final presentCount = _records.where((r) => r.isPresent).length;
    final lateCount = _records.where((r) => r.isLate).length;
    final absentCount = _records.where((r) => r.isAbsent).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ───
            Row(
              children: [
                const Icon(
                  Icons.download_outlined,
                  size: 32,
                  color: AppPalette.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Báo cáo & Xuất file',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Danh sách sinh viên đã điểm danh. Chỉnh sửa nếu cần, rồi xuất file Excel hoặc CSV.',
                        style: TextStyle(color: AppPalette.muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                // Export buttons
                if (_records.isNotEmpty) ...[
                  FilledButton.icon(
                    onPressed: (_exportingExcel || _exportingCsv)
                        ? null
                        : _exportExcel,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E7145), // Excel Green
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: _exportingExcel
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.table_chart_outlined, size: 18),
                    label: Text(
                      _exportingExcel ? 'Đang xuất...' : 'Xuất Excel (.xlsx)',
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: (_exportingExcel || _exportingCsv)
                        ? null
                        : _exportCsv,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: _exportingCsv
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.description_outlined, size: 18),
                    label: Text(
                      _exportingCsv ? 'Đang xuất...' : 'Xuất CSV (.csv)',
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // ─── Selectors ───
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade600,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 1. Class picker
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<ClassModel>(
                    key: ValueKey('cls_${_selectedClass?.classId}'),
                    initialValue: _selectedClass,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Chọn lớp học',
                      prefixIcon: Icon(Icons.class_outlined, size: 18),
                      isDense: true,
                    ),
                    items: mappedClasses.isEmpty
                        ? [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Chưa có lớp đã ghép'),
                            ),
                          ]
                        : mappedClasses
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
                      if (c == null) return;
                      setState(() => _selectedClass = c);
                      _loadAttendance();
                    },
                  ),
                ),

                // 2. Buổi điểm danh (Ngày + Slot) picker
                if (dateOpts.isNotEmpty)
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'date_${_selectedDateOption}_${dateOpts.length}',
                      ),
                      initialValue:
                          _selectedDateOption ??
                          (dateOpts.isNotEmpty ? dateOpts.first : null),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Buổi điểm danh',
                        prefixIcon: Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                        isDense: true,
                      ),
                      items: dateOpts.map((opt) {
                        return DropdownMenuItem(
                          value: opt,
                          child: Text(
                            _formatOptionLabel(opt),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          _selectedDateOption = val;
                        });
                        _loadRecordsForSelectedDate();
                      },
                    ),
                  ),

                if (_loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),

                IconButton(
                  tooltip: 'Tải lại danh sách điểm danh mới nhất',
                  onPressed: _loadAttendance,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Stats strip ───
            if (_records.isNotEmpty) ...[
              Row(
                children: [
                  _StatPill(
                    label: 'Tổng điểm danh',
                    count: _records.length,
                    color: const Color(0xFF1976D2),
                    icon: Icons.people_outline,
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    label: 'Có mặt',
                    count: presentCount,
                    color: Colors.green.shade700,
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    label: 'Đi muộn',
                    count: lateCount,
                    color: Colors.orange.shade700,
                    icon: Icons.access_time,
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    label: 'Vắng',
                    count: absentCount,
                    color: Colors.red.shade600,
                    icon: Icons.cancel_outlined,
                  ),
                  const SizedBox(width: 16),
                  if (absentCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: Colors.amber.shade800,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$absentCount sinh viên vắng trong buổi này',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // ─── Table ───
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _records.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 56,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedClass == null
                                ? 'Chọn lớp học để xem danh sách điểm danh.'
                                : 'Chưa có sinh viên nào điểm danh qua QR cho buổi này.',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : _buildTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
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
              itemCount: _records.length,
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
    final r = _records[idx];
    final color = _statusColor(r.status);
    final classCode = _selectedClass?.classCode ?? '—';
    final timeStr = _formatTime(r.checkInTime);

    return InkWell(
      onTap: () => _openManualUpdate(idx),
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
              onPressed: () => _openManualUpdate(idx),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StatPill({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text('$label: ', style: TextStyle(fontSize: 12, color: color)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
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

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
import '../../services/excel_export_service.dart';
import 'widgets/manual_update_dialog.dart';
import 'widgets/report_table.dart';

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
  final String? initialClassKey;
  final String? initialDateOption;
  final void Function(String? classId, String? sessionId)? onReportSelected;

  const AttendanceReportScreen({
    super.key,
    required this.lecturer,
    required this.classes,
    required this.schedules,
    required this.attendanceRepository,
    this.scheduleRepository,
    this.initialClassKey,
    this.initialDateOption,
    this.onReportSelected,
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
  int _classRequest = 0;
  int _recordsRequest = 0;

  List<ClassModel> get _mappedClasses {
    return widget.classes;
  }

  /// Danh sách các buổi học (Ngày + Slot) duy nhất của lớp
  List<String> get _dateOptions {
    final Set<String> options = {};
    if (_selectedClass?.key == widget.initialClassKey &&
        widget.initialDateOption != null) {
      options.add(widget.initialDateOption!);
    }
    for (final s in _sessions) {
      options.add('${s.date}|${s.slot}');
    }
    final list = options.toList();
    list.sort((a, b) {
      final left = a.split('|'), right = b.split('|');
      final date = right.first.compareTo(left.first);
      return date != 0
          ? date
          : (int.tryParse(right.last) ?? 0).compareTo(
              int.tryParse(left.last) ?? 0,
            );
    });
    return list;
  }

  String _formatOptionLabel(String opt) {
    final parts = opt.split('|');
    final dateStr = parts[0];
    final slotStr = parts.length > 1 ? parts[1] : '';
    try {
      final dt = DateTime.parse(dateStr);
      final weekday = switch (dt.weekday) {
        DateTime.monday => 'Thứ 2',
        DateTime.tuesday => 'Thứ 3',
        DateTime.wednesday => 'Thứ 4',
        DateTime.thursday => 'Thứ 5',
        DateTime.friday => 'Thứ 6',
        DateTime.saturday => 'Thứ 7',
        DateTime.sunday => 'Chủ Nhật',
        _ => '',
      };
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year.toString();
      final dayPrefix = weekday.isNotEmpty ? '$weekday - ' : '';
      return '$dayPrefix$d/$m/$y (Slot $slotStr)';
    } catch (_) {
      return '$dateStr (Slot $slotStr)';
    }
  }

  final Map<String, List<SessionModel>> _sessionsCache = {};
  final Map<String, List<RosterStudent>> _rosterCache = {};

  @override
  void initState() {
    super.initState();
    final mapped = _mappedClasses;
    if (mapped.isNotEmpty) {
      _selectedClass = mapped.firstWhere(
        (c) => c.key == widget.initialClassKey,
        orElse: () => mapped.first,
      );
      _loadAttendance();
    }
  }

  Future<void> _loadAttendance({bool forceRefresh = false}) async {
    widget.onReportSelected?.call(null, null);
    if (_selectedClass == null) return;
    final request = ++_classRequest;
    ++_recordsRequest;
    final previousDate = forceRefresh ? _selectedDateOption : null;
    if (forceRefresh) {
      _sessionsCache.clear();
      _rosterCache.clear();
    }

    setState(() {
      _loading = true;
      _sessions = [];
      _roster = [];
      _records = [];
      _error = null;
    });

    try {
      final cls = _selectedClass!;
      final unifiedClassId =
          cls.classId.trim().isNotEmpty && cls.classId.trim() != 'null'
          ? cls.classId.trim()
          : cls.key.trim();

      // Chạy song song truy vấn phiên học và danh sách sinh viên qua Future.wait
      final results = await Future.wait<dynamic>([
        _sessionsCache.containsKey(unifiedClassId)
            ? Future.value(_sessionsCache[unifiedClassId]!)
            : widget.attendanceRepository
                  .getSessionsByClass(unifiedClassId)
                  .then((list) {
                    if (request == _classRequest) {
                      _sessionsCache[unifiedClassId] = list;
                    }
                    return list;
                  }),
        _rosterCache.containsKey(cls.key)
            ? Future.value(_rosterCache[cls.key]!)
            : (widget.scheduleRepository != null
                  ? widget.scheduleRepository!
                        .getRoster(
                          ClassTarget(
                            semester: cls.semester,
                            subjectCode: cls.subjectCode,
                            classCode: cls.classCode,
                            classId: cls.classId,
                          ),
                        )
                        .then((list) {
                          if (request == _classRequest) {
                            _rosterCache[cls.key] = list;
                          }
                          return list;
                        })
                  : Future.value(<RosterStudent>[])),
      ]);

      final List<SessionModel> sessions = List<SessionModel>.from(
        results[0] as List,
      ).where((s) => s.status != 'RESET').toList();
      final List<RosterStudent> roster = List<RosterStudent>.from(
        results[1] as List,
      );

      sessions.sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        return b.slot.compareTo(a.slot);
      });

      if (mounted && request == _classRequest) {
        setState(() {
          _sessions = sessions;
          _roster = roster;
          final dateOpts = _dateOptions;
          if (dateOpts.isNotEmpty) {
            _selectedDateOption = dateOpts.contains(previousDate)
                ? previousDate
                : _selectedClass?.key == widget.initialClassKey &&
                      dateOpts.contains(widget.initialDateOption)
                ? widget.initialDateOption
                : dateOpts.first;
          } else {
            _selectedDateOption = null;
          }
        });

        if (sessions.isNotEmpty || roster.isNotEmpty) {
          await _loadRecordsForSelectedDate();
        }
      }
    } catch (e) {
      if (mounted && request == _classRequest) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'Không tải được danh sách phiên học.',
        );
      }
    } finally {
      if (mounted && request == _classRequest) setState(() => _loading = false);
    }
  }

  Future<void> _loadRecordsForSelectedDate() async {
    widget.onReportSelected?.call(null, null);
    final request = ++_recordsRequest;
    if (_selectedClass == null) {
      setState(() => _records = []);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _records = [];
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

      if (targetSessions.isEmpty) {
        if (mounted) {
          setState(() {
            _records = [];
            _error = 'Chưa có phiên điểm danh cho ngày và slot đã chọn.';
          });
        }
        return;
      }
      if (targetSessions.length != 1) {
        throw AppException(
          'Có nhiều phiên cho cùng ngày và slot. Cần kiểm tra dữ liệu trước khi sửa hoặc xuất.',
        );
      }

      // Fetch attendance in parallel for targetSessions (sử dụng cache nếu đã tải)
      final List<AttendanceRecord> allRaw = [];
      final List<Future<List<AttendanceRecord>>> futures = [];

      for (final s in targetSessions) {
        futures.add(
          widget.attendanceRepository.getSessionAttendance(s.sessionId),
        );
      }

      if (futures.isNotEmpty) {
        final results = await Future.wait(futures);
        for (final r in results) {
          allRaw.addAll(r);
        }
      }
      if (!mounted || request != _recordsRequest) return;

      // Gộp các bản ghi QR theo MSSV
      final Map<String, AttendanceRecord> qrMerged = {};
      for (final r in allRaw) {
        final code = r.studentCode.trim().toUpperCase();
        if (code.isEmpty || r.sessionId != targetSessions.single.sessionId) {
          throw const AppException(
            'Bản ghi thiếu MSSV hoặc không thuộc phiên đã chọn.',
          );
        }
        if (!qrMerged.containsKey(code)) {
          qrMerged[code] = r;
        } else {
          throw AppException(
            'Trùng bản ghi điểm danh của $code trong phiên. Cần kiểm tra dữ liệu.',
          );
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
      final displayed = finalList
          .map((r) => r.studentCode.trim().toUpperCase())
          .toSet();
      finalList.addAll(
        qrMerged.entries
            .where((e) => !displayed.contains(e.key))
            .map((e) => e.value),
      );

      finalList.sort((a, b) => a.studentCode.compareTo(b.studentCode));

      if (mounted && request == _recordsRequest) {
        setState(() => _records = finalList);
        widget.onReportSelected?.call(
          _selectedClass!.classId,
          targetSessions.single.sessionId,
        );
      }
    } catch (e) {
      if (mounted && request == _recordsRequest) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'Không tải được danh sách điểm danh.',
        );
      }
    } finally {
      if (mounted && request == _recordsRequest) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openManualUpdate(int idx) async {
    if (_loading || _error != null) return;
    final record = _records[idx];
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ManualUpdateDialog(
        record: record,
        onSave: (status, note) async {
          await widget.attendanceRepository.updateAttendanceStatus(
            attendanceId: record.attendanceId,
            sessionId: record.sessionId,
            studentCode: record.studentCode,
            status: status,
            note: note,
            updatedBy: widget.lecturer.email,
          );
        },
      ),
    );
    if (updated == true && mounted) {
      await _loadRecordsForSelectedDate();
      if (!mounted || _error != null) return;
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
      final dt = DateTime.parse(rawTime).toUtc().add(const Duration(hours: 7));
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
    if (_loading ||
        _error != null ||
        _records.isEmpty ||
        _selectedClass == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingExcel = true);
    try {
      final cls = _selectedClass!;
      final dateTag = _currentExportDateTag();
      await _loadRecordsForSelectedDate();
      if (!mounted ||
          _error != null ||
          _records.isEmpty ||
          _selectedClass != cls ||
          _currentExportDateTag() != dateTag ||
          !_validateExport()) {
        return;
      }

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
          r.note,
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
    if (_loading ||
        _error != null ||
        _records.isEmpty ||
        _selectedClass == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingCsv = true);
    try {
      final cls = _selectedClass!;
      final dateTag = _currentExportDateTag();
      await _loadRecordsForSelectedDate();
      if (!mounted ||
          _error != null ||
          _records.isEmpty ||
          _selectedClass != cls ||
          _currentExportDateTag() != dateTag ||
          !_validateExport()) {
        return;
      }

      final buf = StringBuffer();
      buf.write('\uFEFF');
      buf.writeln(
        'STT,Lop hoc,Ma mon,MSSV,Ho ten,Thoi gian check-in,Trang thai,Ky hieu FAP,Ghi chu',
      );

      for (int i = 0; i < _records.length; i++) {
        final r = _records[i];
        buf.writeln(
          [
            '${i + 1}',
            cls.classCode,
            cls.subjectCode,
            r.studentCode,
            r.fullName,
            _formatTime(r.checkInTime),
            r.status,
            _fapCode(r.status),
            r.note,
          ].map((value) => '"${value.replaceAll('"', '""')}"').join(','),
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

  String _fapCode(String s) => switch (s) {
    'PRESENT' => 'P',
    'LATE' => 'L',
    _ => 'A',
  };

  bool _validateExport() {
    if (_records.every(
      (r) => ['PRESENT', 'LATE', 'ABSENT'].contains(r.status),
    )) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cần xác nhận các dòng chưa có trạng thái hợp lệ trước khi xuất FAP.',
        ),
      ),
    );
    return false;
  }

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
                        'Báo cáo & Đồng bộ FAP',
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
                    width: 300,
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
                  onPressed: () => _loadAttendance(forceRefresh: true),
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
              child: ReportTable(
                records: _records,
                selectedClass: _selectedClass,
                loading: _loading,
                onEdit: _openManualUpdate,
              ),
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

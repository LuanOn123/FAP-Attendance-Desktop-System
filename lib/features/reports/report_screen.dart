import 'package:flutter/material.dart';
import '../../../core/app_config.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/class_model.dart';
import '../../../models/lecturer.dart';
import '../../../repositories/attendance_repository.dart';
import '../../../repositories/report_repository.dart';
import '../../../shared/widgets/section_header.dart';
import 'widgets/at_risk_banner.dart';

class ReportScreen extends StatefulWidget {
  final Lecturer lecturer;
  final List<ClassModel> classes;
  final AttendanceRepository attendanceRepository;
  final ReportRepository reportRepository;

  const ReportScreen({
    super.key,
    required this.lecturer,
    required this.classes,
    required this.attendanceRepository,
    required this.reportRepository,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ClassModel? _selectedClass;
  List<StudentAttendanceSummary> _summaries = [];
  bool _loading = false;
  String? _error;
  bool _showOnlyAtRisk = false;

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) {
      _selectedClass = widget.classes.first;
      _loadReport();
    }
  }

  Future<void> _loadReport() async {
    if (_selectedClass == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final [records, sessions] = await Future.wait([
        widget.attendanceRepository.getClassHistory(_selectedClass!.classId),
        widget.attendanceRepository.getSessionsByClass(_selectedClass!.classId),
      ]);

      final summaries = await widget.reportRepository.getClassReport(
        classId: _selectedClass!.classId,
        records: records as dynamic,
        sessions: sessions as dynamic,
      );

      if (mounted) setState(() => _summaries = summaries);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e is AppException ? e.message : 'Không tải được báo cáo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<StudentAttendanceSummary> get _displayed =>
      _showOnlyAtRisk ? _summaries.where((s) => s.isAtRisk).toList() : _summaries;

  List<StudentAttendanceSummary> get _atRisk =>
      _summaries.where((s) => s.isAtRisk).toList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SectionHeader(
          eyebrow: 'BÁO CÁO CHUYÊN CẦN',
          title: 'Báo cáo điểm danh',
          subtitle:
              'Tỷ lệ có mặt từng sinh viên, cảnh báo sinh viên có nguy cơ cấm thi (dưới 80%).',
        ),
        const SizedBox(height: 24),

        // Controls
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<ClassModel>(
                key: ValueKey('cls_${_selectedClass?.classId}'),
                initialValue: _selectedClass,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Chọn lớp học',
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
                onChanged: (c) {
                  setState(() {
                    _selectedClass = c;
                    _summaries = [];
                    _showOnlyAtRisk = false;
                  });
                  _loadReport();
                },
              ),
            ),
            if (_summaries.isNotEmpty) ...[
              FilterChip(
                label: Text('Chỉ At-risk (${_atRisk.length})'),
                selected: _showOnlyAtRisk,
                onSelected: (v) => setState(() => _showOnlyAtRisk = v),
                selectedColor: Colors.red.shade50,
                checkmarkColor: Colors.red.shade700,
                labelStyle: TextStyle(
                  color: _showOnlyAtRisk
                      ? Colors.red.shade700
                      : Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
            IconButton(
              tooltip: 'Tải lại',
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 20),

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
              child: Text('Chọn lớp để xem báo cáo.'),
            ),
          )
        else ...[
          if (_atRisk.isNotEmpty)
            AtRiskBanner(
              atRiskStudents: _atRisk,
              onViewAll: () => setState(() => _showOnlyAtRisk = true),
            ),
          if (_summaries.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.bar_chart_outlined,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('Chưa có dữ liệu điểm danh cho lớp này.'),
                  ],
                ),
              ),
            )
          else
            _buildReportTable(_displayed),
        ],
      ],
    );
  }

  Widget _buildReportTable(List<StudentAttendanceSummary> data) {
    final totalSessions = data.isNotEmpty ? data.first.totalSessions : 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppPalette.line),
      ),
      child: Column(
        children: [
          // Summary row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.analytics_outlined,
                    size: 18, color: AppPalette.orange),
                const SizedBox(width: 8),
                Text(
                  '${data.length} sinh viên  ·  $totalSessions buổi học',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                if (_atRisk.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 14, color: Colors.red.shade600),
                        const SizedBox(width: 4),
                        Text(
                          '${_atRisk.length} At-risk',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Header
          Container(
            color: AppPalette.orangeSoft,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: const [
                SizedBox(width: 40),
                _RH('MSSV', flex: 2),
                _RH('Họ và tên', flex: 3),
                _RH('Có mặt', flex: 1),
                _RH('Đi muộn', flex: 1),
                _RH('Vắng', flex: 1),
                _RH('Tổng buổi', flex: 1),
                _RH('Tỷ lệ có mặt', flex: 2),
              ],
            ),
          ),

          // Data rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, idx) => _buildStudentRow(data[idx]),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRow(StudentAttendanceSummary s) {
    final rate = s.attendanceRate;
    final rateStr = '${(rate * 100).toStringAsFixed(1)}%';
    final rateColor = rate >= 0.8
        ? Colors.green.shade700
        : rate >= 0.6
            ? Colors.orange.shade700
            : Colors.red.shade600;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // At-risk indicator
          SizedBox(
            width: 40,
            child: s.isAtRisk
                ? Tooltip(
                    message: 'Nguy cơ cấm thi: tỷ lệ có mặt < 80%',
                    child: Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade500, size: 18),
                  )
                : Icon(Icons.check_circle_outline,
                    color: Colors.green.shade400, size: 18),
          ),
          _DataCell(s.studentCode, flex: 2, bold: true),
          _DataCell(s.fullName, flex: 3),
          _DataCell('${s.presentCount}', flex: 1, color: Colors.green.shade700),
          _DataCell('${s.lateCount}', flex: 1, color: Colors.orange.shade700),
          _DataCell('${s.absentCount}', flex: 1, color: Colors.red.shade600),
          _DataCell('${s.totalSessions}', flex: 1, muted: true),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: rate.clamp(0, 1),
                          backgroundColor: Colors.grey.shade200,
                          color: rateColor,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rateStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: rateColor,
                      ),
                    ),
                  ],
                ),
                if (s.isAtRisk)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Nguy cơ cấm thi',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RH extends StatelessWidget {
  final String text;
  final int flex;
  const _RH(this.text, {required this.flex});

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

class _DataCell extends StatelessWidget {
  final String text;
  final int flex;
  final bool bold;
  final bool muted;
  final Color? color;

  const _DataCell(
    this.text, {
    required this.flex,
    this.bold = false,
    this.muted = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color ??
            (muted ? AppPalette.muted : AppPalette.ink),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/lecturer.dart';
import '../../../repositories/report_repository.dart';
import '../../../shared/widgets/section_header.dart';

class DashboardScreen extends StatefulWidget {
  final Lecturer lecturer;
  final ReportRepository reportRepository;
  final VoidCallback? onGoHistory;
  final VoidCallback? onGoReport;

  const DashboardScreen({
    super.key,
    required this.lecturer,
    required this.reportRepository,
    this.onGoHistory,
    this.onGoReport,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardStats? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await widget.reportRepository.getDashboard(
        widget.lecturer.lecturerId,
      );
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không tải được dữ liệu. Thử lại sau.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        SectionHeader(
          eyebrow: 'TỔNG QUAN GIẢNG DẠY',
          title: 'Dashboard',
          subtitle:
              'Theo dõi tỷ lệ điểm danh và hoạt động học tập của lớp bạn theo thời gian thực.',
        ),
        const SizedBox(height: 24),

        if (_loading)
          const LinearProgressIndicator()
        else if (_error != null)
          _buildError()
        else if (_stats != null)
          _buildContent(_stats!),
      ],
    );
  }

  Widget _buildError() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline, color: Colors.red.shade600),
        const SizedBox(width: 12),
        Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
        TextButton(onPressed: _load, child: const Text('Thử lại')),
      ],
    ),
  );

  Widget _buildContent(DashboardStats s) {
    final rate = (s.attendanceRate * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stat cards row
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(
              icon: Icons.school_outlined,
              label: 'Tổng lớp học',
              value: '${s.totalClasses}',
              color: const Color(0xFF1976D2),
            ),
            _StatCard(
              icon: Icons.people_outline,
              label: 'Tổng sinh viên',
              value: '${s.totalStudents}',
              color: const Color(0xFF7B1FA2),
            ),
            _StatCard(
              icon: Icons.today_outlined,
              label: 'Ca học hôm nay',
              value: '${s.todaySessions}',
              color: AppPalette.orange,
            ),
            _StatCard(
              icon: Icons.bar_chart_rounded,
              label: 'Tỷ lệ có mặt',
              value: '$rate%',
              color: s.attendanceRate >= 0.8
                  ? Colors.green.shade700
                  : Colors.red.shade600,
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Attendance breakdown card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppPalette.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.donut_large, color: AppPalette.orange),
                    const SizedBox(width: 10),
                    Text(
                      'Phân bố điểm danh',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Tổng: ${s.totalAttendance} lượt',
                      style: TextStyle(color: AppPalette.muted, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Stacked progress bar
                if (s.totalAttendance > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          _buildBar(
                            s.presentCount / s.totalAttendance,
                            Colors.green,
                          ),
                          _buildBar(
                            s.lateCount / s.totalAttendance,
                            Colors.orange,
                          ),
                          _buildBar(
                            s.absentCount / s.totalAttendance,
                            Colors.red.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Legend
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _LegendItem(
                      color: Colors.green,
                      label: 'Có mặt (Present)',
                      count: s.presentCount,
                    ),
                    _LegendItem(
                      color: Colors.orange,
                      label: 'Đi muộn (Late)',
                      count: s.lateCount,
                    ),
                    _LegendItem(
                      color: Colors.red.shade400,
                      label: 'Vắng mặt (Absent)',
                      count: s.absentCount,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Quick actions
        Text(
          'Thao tác nhanh',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: widget.onGoHistory,
              icon: const Icon(Icons.history),
              label: const Text('Lịch sử điểm danh'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            FilledButton.icon(
              onPressed: widget.onGoReport,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Xem báo cáo lớp'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Làm mới'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBar(double ratio, Color color) {
    if (ratio <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: (ratio * 1000).round(),
      child: Container(color: color),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.25)),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.08), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

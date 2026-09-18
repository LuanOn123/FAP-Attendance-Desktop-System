import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../models/class_model.dart';
import '../../models/lecturer.dart';
import '../../models/schedule.dart';
import '../../repositories/attendance_repository.dart';
import '../../repositories/report_repository.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'report_screen.dart';
import 'fap_export_screen.dart';

/// Container của toàn bộ module Báo cáo (Member 4)
/// Sử dụng NavigationRail nội bộ để chuyển giữa các màn hình con.
class ReportsRoot extends StatefulWidget {
  final Lecturer lecturer;
  final List<ClassModel> classes;
  final List<Schedule> schedules;
  final AttendanceRepository attendanceRepository;
  final ReportRepository reportRepository;

  const ReportsRoot({
    super.key,
    required this.lecturer,
    required this.classes,
    required this.schedules,
    required this.attendanceRepository,
    required this.reportRepository,
  });

  @override
  State<ReportsRoot> createState() => _ReportsRootState();
}

class _ReportsRootState extends State<ReportsRoot> {
  int _selected = 0;

  final List<(IconData, String)> _navItems = const [
    (Icons.dashboard_outlined, 'Dashboard'),
    (Icons.history_outlined, 'Lịch sử'),
    (Icons.analytics_outlined, 'Báo cáo'),
    (Icons.download_outlined, 'Xuất FAP'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Sub NavigationRail
        NavigationRail(
          minWidth: 80,
          selectedIndex: _selected,
          onDestinationSelected: (v) => setState(() => _selected = v),
          labelType: NavigationRailLabelType.all,
          backgroundColor: AppPalette.orangeSoft,
          indicatorColor: AppPalette.orange.withValues(alpha: 0.15),
          selectedIconTheme: const IconThemeData(color: AppPalette.orangeDark),
          selectedLabelTextStyle: const TextStyle(
            color: AppPalette.orangeDark,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          unselectedLabelTextStyle: TextStyle(
            color: AppPalette.muted,
            fontSize: 11,
          ),
          destinations: _navItems
              .map(
                (item) => NavigationRailDestination(
                  icon: Icon(item.$1),
                  label: Text(item.$2),
                ),
              )
              .toList(),
        ),
        const VerticalDivider(width: 1),

        // Content area
        Expanded(
          child: switch (_selected) {
            0 => DashboardScreen(
                lecturer: widget.lecturer,
                reportRepository: widget.reportRepository,
                onGoHistory: () => setState(() => _selected = 1),
                onGoReport: () => setState(() => _selected = 2),
              ),
            1 => HistoryScreen(
                lecturer: widget.lecturer,
                classes: widget.classes,
                attendanceRepository: widget.attendanceRepository,
              ),
            2 => ReportScreen(
                lecturer: widget.lecturer,
                classes: widget.classes,
                attendanceRepository: widget.attendanceRepository,
                reportRepository: widget.reportRepository,
              ),
            _ => FapExportScreen(
                lecturer: widget.lecturer,
                classes: widget.classes,
                attendanceRepository: widget.attendanceRepository,
                reportRepository: widget.reportRepository,
              ),
          },
        ),
      ],
    );
  }
}

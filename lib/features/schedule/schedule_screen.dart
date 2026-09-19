import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../core/app_config.dart';
import '../../models/class_model.dart';
import '../../models/lecturer.dart';
import '../../models/schedule.dart';
import '../../repositories/schedule_repository.dart';
import '../../services/class_mapping_service.dart';
import '../../shared/widgets/section_header.dart';
import 'ocr_review_screen.dart';
import 'schedule_editor.dart';
import 'weekly_timetable.dart';
import '../classes/classes_screen.dart';
import '../attendance/attendance_screen.dart';
import '../../repositories/attendance_repository.dart';
import '../reports/attendance_report_screen.dart';
import '../../services/integration_server.dart';
import '../../models/fap_import_dto.dart';
import 'dart:async';

class ScheduleScreen extends StatefulWidget {
  final Lecturer lecturer;
  final ScheduleRepository repository;
  final AttendanceRepository? attendanceRepository;
  final IntegrationServer? integrationServer;
  final Future<void> Function() onLogout;
  const ScheduleScreen({
    super.key,
    required this.lecturer,
    required this.repository,
    this.attendanceRepository,
    this.integrationServer,
    required this.onLogout,
  });
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Schedule> schedules = [];
  List<ClassModel> classes = [];
  bool loading = true;
  String? error;
  String? classError;
  final search = TextEditingController();
  String query = '';
  late final AttendanceRepository _attendanceRepo =
      widget.attendanceRepository ??
      (widget.repository is SheetScheduleRepository
          ? SheetAttendanceRepository(
              (widget.repository as SheetScheduleRepository).sheets,
            )
          : DemoAttendanceRepository());
  int destination = 0;
  bool weekly = true;
  String? semesterFilter;
  StreamSubscription? _importSub;
  late final _integration = widget.integrationServer ?? IntegrationServer();
  FapImportResult? _latestImport;
  final Map<String, String> _importDates = {};
  bool _attendanceVisited = false;
  int _importRevision = 0;
  String? _bridgeError;
  String? _reportClassKey;
  String? _reportDateOption;
  @override
  void initState() {
    super.initState();
    load();
    _integration.start(widget.repository, widget.lecturer.lecturerId).catchError((
      Object e,
    ) {
      if (mounted) {
        setState(
          () => _bridgeError =
              'Không mở được kết nối extension ở cổng 8765. Đóng bản app khác và đăng nhập lại.',
        );
      }
    });
    _importSub = _integration.onImportComplete.listen((
      FapImportResult result,
    ) async {
      if (!mounted) return;
      setState(() {
        _latestImport = result;
        _reportClassKey = result.schedule.key;
        _reportDateOption = '${result.date}|${result.schedule.slot}';
        _importRevision++;
        _importDates[result.schedule.scheduleId] = result.date;
        _attendanceVisited = true;
        destination = 2;
      });
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã nhận ${result.studentCount} sinh viên · ${result.schedule.classCode}. Buổi vừa nhập được đánh dấu Hiện tại.',
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _importSub?.cancel();
    unawaited(_integration.stop());
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      classError = null;
    });
    try {
      List<Schedule>? loadedSchedules;
      List<ClassModel>? loadedClasses;
      String? scheduleFailure, classFailure;
      await Future.wait<void>([
        () async {
          try {
            loadedSchedules = await widget.repository.getSchedules();
          } catch (e) {
            scheduleFailure =
                'Không tải lại được lịch. ${e is AppException ? e.message : 'Kiểm tra kết nối và thử tải lại.'}';
          }
        }(),
        () async {
          try {
            loadedClasses = await widget.repository.getClasses();
          } catch (e) {
            classFailure =
                'Chưa tải được lớp để ghép lịch. ${e is AppException ? e.message : 'Hãy thử tải lại.'}';
          }
        }(),
      ]);
      if (!mounted) return;
      setState(() {
        if (loadedSchedules != null) {
          schedules = loadedSchedules!
            ..sort((a, b) {
              final day = a.dayOfWeek.compareTo(b.dayOfWeek);
              return day != 0 ? day : a.startTime.compareTo(b.startTime);
            });
        }
        classes = loadedClasses ?? [];
        error = scheduleFailure;
        classError = classFailure;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Không tải được dữ liệu. Kiểm tra mạng, quyền giảng viên và cấu hình Sheets.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([Schedule? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScheduleEditor(
        lecturerId: widget.lecturer.lecturerId,
        existing: row,
        onSave: (s) => widget.repository.save([s]),
      ),
    );
    if (saved == true && mounted) await afterSave();
  }

  Future<void> import() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OcrReviewScreen(
          lecturerId: widget.lecturer.lecturerId,
          repository: widget.repository,
        ),
      ),
    );
    if (saved == true && mounted) await afterSave();
  }

  Future<void> afterSave() async {
    setState(() {
      query = '';
      semesterFilter = null;
      search.clear();
      destination = 0;
    });
    await load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? 'Đã lưu lịch và cập nhật danh sách.'
              : 'Đã lưu lịch nhưng chưa tải lại được danh sách. Bấm Tải lại; không cần nhập lại ảnh.',
        ),
      ),
    );
  }

  Future<void> delete(Schedule row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa lịch dạy?'),
        content: Text(
          '${row.subjectCode} • ${row.classCode} • ${row.startTime}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => loading = true);
    try {
      await widget.repository.delete(row.scheduleId);
      await load();
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Không xóa được lịch. Vui lòng thử lại.';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'FAP Attendance',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        Tooltip(
          message:
              _bridgeError ??
              'Extension kết nối qua 127.0.0.1:8765 khi đã đăng nhập.',
          child: Icon(
            _bridgeError == null
                ? Icons.extension_outlined
                : Icons.error_outline,
            color: _bridgeError == null ? Colors.green : Colors.red,
          ),
        ),
        if (AppConfig.demo) const Chip(label: Text('DEMO • Không lưu lâu dài')),
        const SizedBox(width: 16),
        Text(widget.lecturer.fullName),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Đăng xuất',
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: Row(
      children: [
        NavigationRail(
          minWidth: 104,
          groupAlignment: -0.85,
          leading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircleAvatar(
              backgroundColor: AppPalette.orange,
              foregroundColor: Colors.white,
              child: Icon(Icons.school_outlined),
            ),
          ),
          selectedIndex: destination,
          onDestinationSelected: (value) => setState(() {
            destination = value;
            if (value == 2) _attendanceVisited = true;
          }),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: Text('Lịch dạy'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.groups_outlined),
              label: Text('Lớp học'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.qr_code),
              label: Text('Điểm danh'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.bar_chart),
              label: Text('Báo cáo'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.person_outline),
              label: Text('Hồ sơ'),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(
            index: destination,
            children: [
              scheduleBody(),
              destination == 1
                  ? ClassesScreen(
                      classes: classes,
                      schedules: schedules,
                      lecturerId: widget.lecturer.lecturerId,
                      repository: widget.repository,
                      onChanged: load,
                    )
                  : const SizedBox.shrink(),
              _attendanceVisited
                  ? AttendanceScreen(
                      lecturer: widget.lecturer,
                      schedules: schedules,
                      classes: classes,
                      repository: _attendanceRepo,
                      scheduleRepository: widget.repository,
                      currentScheduleId: _latestImport?.schedule.scheduleId,
                      importedDates: Map.of(_importDates),
                      importRevision: _importRevision,
                      onOpenReport: (schedule, session) => setState(() {
                        _reportClassKey = schedule.key;
                        _reportDateOption = '${session.date}|${session.slot}';
                        destination = 3;
                      }),
                    )
                  : const SizedBox.shrink(),
              destination == 3
                  ? AttendanceReportScreen(
                      lecturer: widget.lecturer,
                      classes: classes,
                      schedules: schedules,
                      attendanceRepository: _attendanceRepo,
                      scheduleRepository: widget.repository,
                      initialClassKey: _reportClassKey,
                      initialDateOption: _reportDateOption,
                    )
                  : const SizedBox.shrink(),
              profile(),
            ],
          ),
        ),
      ],
    ),
  );
  Widget profile() => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      Text(
        'Hồ sơ giảng viên',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in [
                widget.lecturer.fullName,
                widget.lecturer.email,
                'Mã giảng viên: ${widget.lecturer.lecturerCode}',
                'Bộ môn: ${widget.lecturer.department}',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SelectableText(
                    item,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget scheduleBody() {
    final visible = schedules
        .where(
          (s) =>
              (semesterFilter == null || s.semester == semesterFilter) &&
              '${s.semester} ${s.subjectCode} ${s.subjectName} ${s.classCode} ${s.room}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    final mapped = schedules
        .where((s) => ClassMappingService().map(s, classes).mappedClass != null)
        .length;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SectionHeader(
          eyebrow: 'KHÔNG GIAN GIẢNG DẠY',
          title: 'Thời khóa biểu',
          subtitle:
              'Sẵn sàng cho một ngày giảng dạy hiệu quả. Quản lý lịch và kết nối lớp học tại đây.',
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            stat('Lịch dạy', '${schedules.length}', Icons.calendar_today),
            stat('Đã ghép lớp', '$mapped', Icons.link),
            stat(
              'Cần ghép / xử lý',
              '${schedules.length - mapped}',
              Icons.rule,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: search,
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  hintText: 'Tìm học kỳ, môn, lớp, phòng…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              width: 175,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey(semesterFilter),
                initialValue: semesterFilter ?? '',
                decoration: const InputDecoration(labelText: 'Học kỳ'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Tất cả học kỳ'),
                  ),
                  for (final semester
                      in (schedules.map((s) => s.semester).toSet().toList()
                        ..sort()))
                    DropdownMenuItem(value: semester, child: Text(semester)),
                ],
                onChanged: (v) =>
                    setState(() => semesterFilter = v == '' ? null : v),
              ),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.calendar_view_week),
                  label: Text('Bảng tuần'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.view_list_outlined),
                  label: Text('Danh sách'),
                ),
              ],
              selected: {weekly},
              onSelectionChanged: (v) => setState(() => weekly = v.single),
            ),
            FilledButton.icon(
              onPressed: loading ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Nhập lịch thủ công'),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : import,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Nhập ảnh OCR'),
            ),
            IconButton(
              tooltip: 'Tải lại và ghép lớp',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        if (classError != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(classError!)),
        if (!loading && error == null && visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              'Chưa có lịch phù hợp. Thêm lịch thủ công hoặc nhập ảnh OCR.',
            ),
          ),
        if (weekly && visible.isNotEmpty)
          WeeklyTimetable(
            schedules: visible,
            onSelect: showLesson,
            subjectCodes: schedules.map((s) => s.subjectCode).toSet().toList()
              ..sort(),
          ),
        if (!weekly)
          for (final s in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 265,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.subjectCode}  •  ${s.classCode}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(s.subjectName),
                            const SizedBox(height: 6),
                            Text('${s.semester}  /  ${s.room}'),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.dayOfWeek == 7 ? 'Chủ nhật' : 'Thứ ${s.dayOfWeek + 1}'}  •  Slot ${s.slot}',
                          ),
                          Text(
                            '${s.startTime} – ${s.endTime}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            s.sourceType == 'IMAGE'
                                ? 'Từ ảnh OCR'
                                : 'Nhập thủ công',
                          ),
                        ],
                      ),
                      Chip(
                        avatar: const Icon(Icons.link, size: 18),
                        label: Text(
                          ClassMappingService().map(s, classes).label,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Sửa lịch',
                            onPressed: loading ? null : () => edit(s),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Xóa lịch',
                            onPressed: loading ? null : () => delete(s),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> showLesson(Schedule row) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${row.subjectCode} · ${row.classCode}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.subjectName),
            const SizedBox(height: 12),
            Text(
              '${row.dayOfWeek == 7 ? 'Chủ nhật' : 'Thứ ${row.dayOfWeek + 1}'} · Slot ${row.slot}',
            ),
            Text('${row.startTime} – ${row.endTime}'),
            Text('Phòng ${row.room} · ${row.semester}'),
            const SizedBox(height: 12),
            Text(ClassMappingService().map(row, classes).label),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: loading ? null : () => Navigator.pop(context, 'delete'),
            child: const Text('Xóa lịch'),
          ),
          FilledButton(
            onPressed: loading ? null : () => Navigator.pop(context, 'edit'),
            child: const Text('Sửa lịch'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await edit(row);
    if (action == 'delete') await delete(row);
  }

  Widget stat(String label, String value, IconData icon) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: AppPalette.orange),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(label),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

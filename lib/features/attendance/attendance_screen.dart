import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../core/app_config.dart';
import '../../models/attendance_record.dart';
import '../../models/class_model.dart';
import '../../models/lecturer.dart';
import '../../models/schedule.dart';
import '../../models/session_model.dart';
import '../../models/roster.dart';
import '../../repositories/schedule_repository.dart';
import '../../repositories/attendance_repository.dart';
import '../../services/class_mapping_service.dart';
import 'session_qr_widget.dart';
import 'student_checkin_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final Lecturer lecturer;
  final List<Schedule> schedules;
  final List<ClassModel> classes;
  final AttendanceRepository repository;
  final ScheduleRepository? scheduleRepository;
  final String? currentScheduleId;
  final Map<String, String> importedDates;
  final void Function(Schedule schedule, SessionModel session)? onOpenReport;
  final int importRevision;

  const AttendanceScreen({
    super.key,
    required this.lecturer,
    required this.schedules,
    required this.classes,
    required this.repository,
    this.scheduleRepository,
    this.currentScheduleId,
    this.importedDates = const {},
    this.onOpenReport,
    this.importRevision = 0,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Schedule? selectedSchedule;
  SessionModel? activeSession;
  bool isStarting = false;
  bool isClosing = false;
  bool _pendingAbsences = false;
  String? errorMessage;
  List<AttendanceRecord> attendanceRecords = [];
  Timer? _refreshTimer;

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentScheduleId != oldWidget.currentScheduleId ||
        widget.importRevision != oldWidget.importRevision) {
      // Leave the existing session on the backend so it can be resumed.
      _refreshTimer?.cancel();
      activeSession = null;
      selectedSchedule = null;
      attendanceRecords = [];
      _pendingAbsences = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAttendancePolling() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (activeSession != null && activeSession!.isOpen) {
        _fetchAttendanceList();
      }
    });
  }

  Future<void> _fetchAttendanceList() async {
    if (activeSession == null) return;
    try {
      final records = await widget.repository.getSessionAttendance(
        activeSession!.sessionId,
      );
      if (mounted) {
        setState(() {
          attendanceRecords = records;
        });
      }
    } catch (_) {}
  }

  Future<void> _startSession(Schedule schedule) async {
    final mapping = ClassMappingService().map(schedule, widget.classes);
    if (mapping.mappedClass == null) {
      setState(() {
        errorMessage =
            'Không thể mở phiên: Lịch dạy chưa được ghép với lớp học tương ứng.';
      });
      return;
    }

    setState(() {
      isStarting = true;
      errorMessage = null;
    });

    final mappedClass = mapping.mappedClass!;
    final classIdToUse =
        mappedClass.classId.trim().isNotEmpty &&
            mappedClass.classId.trim() != 'null'
        ? mappedClass.classId.trim()
        : mappedClass.key;

    try {
      final importedDate = widget.importedDates[schedule.scheduleId];
      final date =
          importedDate ?? DateTime.now().toIso8601String().substring(0, 10);
      final sessions = await widget.repository.getSessionsByClass(classIdToUse);
      final sameSession = sessions
          .where((s) => s.date == date && s.slot == schedule.slot)
          .toList();
      // Retry/navigation must resume the existing session, including closed ones.
      var session = sameSession.isNotEmpty
          ? sameSession.first
          : await widget.repository.startSession(
              date: date,
              classId: classIdToUse,
              slot: schedule.slot,
              startTime: schedule.startTime,
              endTime: schedule.endTime,
              lecturerId: widget.lecturer.lecturerId,
            );
      if (sameSession.isNotEmpty && session.isOpen) {
        final now = DateTime.now();
        final token = 'TKN_${now.microsecondsSinceEpoch}';
        final secret = session.currentSecretCode.isNotEmpty
            ? session.currentSecretCode
            : session.currentToken.split('#').last;
        final expiresAt = now
            .add(const Duration(seconds: 120))
            .toIso8601String();
        await widget.repository.rotateSessionToken(
          sessionId: session.sessionId,
          newToken: token,
          newSecretCode: secret,
          tokenExpiredAt: expiresAt,
        );
        session = session.copyWith(
          currentToken: token,
          currentSecretCode: secret,
          tokenExpiredAt: expiresAt,
        );
      }

      if (mounted) {
        setState(() {
          selectedSchedule = schedule;
          activeSession = session;
          attendanceRecords = [];
          _pendingAbsences =
              !session.isOpen && widget.scheduleRepository != null;
        });
        _startAttendancePolling();
        await _fetchAttendanceList();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e is AppException
              ? e.message
              : 'Không thể khởi tạo phiên điểm danh.';
        });
      }
    } finally {
      if (mounted) setState(() => isStarting = false);
    }
  }

  Future<void> _closeSession() async {
    if (activeSession == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết thúc điểm danh?'),
        content: const Text(
          'Khi kết thúc, mã QR sẽ không còn hiệu lực và sinh viên không thể tự check-in được nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kết thúc ngay'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isClosing = true);
    final closingSession = activeSession!;
    final closingSchedule = selectedSchedule!;
    try {
      await widget.repository.closeSession(closingSession.sessionId);
      if (mounted && activeSession?.sessionId == closingSession.sessionId) {
        _refreshTimer?.cancel();
        setState(() {
          activeSession = closingSession.copyWith(status: 'CLOSED');
          _pendingAbsences = widget.scheduleRepository != null;
        });
      }
      await _markMissing(closingSession, closingSchedule);
      await _fetchAttendanceList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã đóng phiên điểm danh thành công.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is AppException ? e.message : 'Lỗi khi đóng phiên điểm danh.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isClosing = false);
    }
  }

  Future<void> _markMissing(SessionModel session, Schedule schedule) async {
    if (widget.scheduleRepository == null) return;
    final roster = await widget.scheduleRepository!.getRoster(
      ClassTarget(
        semester: schedule.semester,
        subjectCode: schedule.subjectCode,
        classCode: schedule.classCode,
      ),
    );
    await widget.repository.markAbsent(
      sessionId: session.sessionId,
      studentCodes: roster.map((s) => s.studentCode).toList(),
      lecturerEmail: widget.lecturer.email,
    );
    if (mounted && activeSession?.sessionId == session.sessionId) {
      setState(() => _pendingAbsences = false);
    }
  }

  Future<void> _retryAbsences() async {
    setState(() => isClosing = true);
    try {
      await _markMissing(activeSession!, selectedSchedule!);
      await _fetchAttendanceList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Chưa chốt được danh sách vắng. Thử lại trước khi xuất báo cáo. $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isClosing = false);
    }
  }

  Future<void> _openStudentCheckinTest() async {
    if (activeSession == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentCheckinScreen(
          sessionId: activeSession!.sessionId,
          token: activeSession!.currentToken.split('#').first,
        ),
      ),
    );
    if (mounted) _fetchAttendanceList();
  }

  @override
  Widget build(BuildContext context) {
    if (activeSession != null) {
      return _buildActiveSessionView();
    }
    return _buildScheduleSelectionView();
  }

  Widget _buildScheduleSelectionView() {
    final mappingService = ClassMappingService();
    final sortedSchedules = List<Schedule>.of(widget.schedules)
      ..sort((a, b) {
        if (a.scheduleId == b.scheduleId) return 0;
        if (a.scheduleId == widget.currentScheduleId) return -1;
        if (b.scheduleId == widget.currentScheduleId) return 1;
        final day = a.dayOfWeek.compareTo(b.dayOfWeek);
        return day != 0 ? day : a.startTime.compareTo(b.startTime);
      });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code, size: 32, color: AppPalette.orange),
                const SizedBox(width: 12),
                Text(
                  'Bắt đầu phiên điểm danh',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn ca học từ lịch dạy của bạn để tạo mã QR và Secret Code cho sinh viên điểm danh.',
              style: TextStyle(color: Colors.black54, fontSize: 15),
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: widget.schedules.isEmpty
                  ? const Center(
                      child: Text('Chưa có lịch dạy nào. Hãy thêm lịch trước.'),
                    )
                  : ListView.builder(
                      itemCount: widget.schedules.length,
                      itemBuilder: (context, index) {
                        final schedule = sortedSchedules[index];
                        final mapping = mappingService.map(
                          schedule,
                          widget.classes,
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: mapping.mappedClass != null
                                  ? AppPalette.orange.withValues(alpha: 0.3)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: mapping.mappedClass != null
                                        ? AppPalette.orangeSoft
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.school,
                                    color: mapping.mappedClass != null
                                        ? AppPalette.orangeDark
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${schedule.subjectCode} - ${schedule.classCode}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${schedule.subjectName} · Phòng ${schedule.room}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Slot ${schedule.slot} (${schedule.startTime} - ${schedule.endTime})',
                                        style: const TextStyle(
                                          color: Colors.blueGrey,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (schedule.scheduleId ==
                                        widget.currentScheduleId)
                                      const Chip(
                                        label: Text('Hiện tại'),
                                        avatar: Icon(Icons.push_pin, size: 16),
                                      ),
                                    if (widget.importedDates[schedule
                                            .scheduleId] !=
                                        null)
                                      Text(
                                        'Ngày: ${widget.importedDates[schedule.scheduleId]}',
                                      ),
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor:
                                          mapping.mappedClass != null
                                          ? Colors.green.shade50
                                          : Colors.amber.shade50,
                                      side: BorderSide(
                                        color: mapping.mappedClass != null
                                            ? Colors.green
                                            : Colors.amber.shade700,
                                      ),
                                      label: Text(
                                        mapping.mappedClass != null
                                            ? 'Đã ghép lớp'
                                            : 'Chưa ghép lớp',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: mapping.mappedClass != null
                                              ? Colors.green.shade800
                                              : Colors.amber.shade900,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                      onPressed:
                                          (mapping.mappedClass == null ||
                                              isStarting)
                                          ? null
                                          : () => _startSession(schedule),
                                      icon: isStarting
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.play_arrow),
                                      label: const Text('Tạo phiên'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionView() {
    final schedule = selectedSchedule!;
    final session = activeSession!;
    final presentCount = attendanceRecords
        .where((r) => r.status == 'PRESENT')
        .length;
    final lateCount = attendanceRecords.where((r) => r.status == 'LATE').length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${schedule.subjectCode} · ${schedule.classCode}',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: session.isOpen
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                          ),
                          child: Text(
                            session.isOpen ? 'ĐANG ĐIỂM DANH' : 'ĐÃ ĐÓNG PHIÊN',
                            style: TextStyle(
                              color: session.isOpen
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${schedule.subjectName} · Slot ${schedule.slot} (${schedule.startTime} - ${schedule.endTime}) · Phòng ${schedule.room}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (!session.isOpen && widget.onOpenReport != null)
                      OutlinedButton.icon(
                        onPressed: _pendingAbsences
                            ? null
                            : () => widget.onOpenReport!(schedule, session),
                        icon: const Icon(Icons.bar_chart),
                        label: const Text('Báo cáo / Excel'),
                      ),
                    if (_pendingAbsences)
                      FilledButton.icon(
                        onPressed: isClosing ? null : _retryAbsences,
                        icon: const Icon(Icons.sync),
                        label: const Text('Chốt danh sách vắng'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _refreshTimer?.cancel();
                        setState(() {
                          activeSession = null;
                          selectedSchedule = null;
                          attendanceRecords = [];
                        });
                      },
                      icon: const Icon(Icons.list),
                      label: const Text('Danh sách buổi học'),
                    ),
                    if (session.isOpen)
                      OutlinedButton.icon(
                        onPressed: _openStudentCheckinTest,
                        icon: const Icon(Icons.phone_android),
                        label: const Text('Mở Test Check-in'),
                      ),
                    const SizedBox(width: 12),
                    if (session.isOpen)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                        ),
                        onPressed: isClosing ? null : _closeSession,
                        icon: const Icon(Icons.stop),
                        label: isClosing
                            ? const Text('Đang đóng...')
                            : const Text('Kết thúc phiên'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            activeSession = null;
                            selectedSchedule = null;
                            attendanceRecords = [];
                          });
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Quay lại danh sách'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Main Content: Left QR Display, Right Live Attendance Table
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // QR Display (for Projector)
                if (session.isOpen)
                  SessionQrDisplayWidget(
                    sessionId: session.sessionId,
                    initialToken: session.currentToken.split('#').first,
                    initialSecretCode: session.currentSecretCode.isNotEmpty
                        ? session.currentSecretCode
                        : (session.currentToken.contains('#')
                              ? session.currentToken.split('#').last
                              : '888999'),
                    onRotateToken: (newToken, newSecret) async {
                      final expiresAt = DateTime.now()
                          .add(const Duration(seconds: 120))
                          .toIso8601String();
                      await widget.repository.rotateSessionToken(
                        sessionId: session.sessionId,
                        newToken: newToken,
                        newSecretCode: newSecret,
                        tokenExpiredAt: expiresAt,
                      );
                      if (mounted) {
                        setState(() {
                          activeSession = activeSession!.copyWith(
                            currentToken: '$newToken#$newSecret',
                            currentSecretCode: newSecret,
                            tokenExpiredAt: expiresAt,
                          );
                        });
                      }
                    },
                  )
                else
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const SizedBox(
                      width: 380,
                      height: 380,
                      child: Center(
                        child: Text(
                          'Phiên điểm danh đã kết thúc.\nMã QR đã bị vô hiệu hóa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 24),

                // Right: Attendance Live Counter & List
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats Row
                      Row(
                        children: [
                          _buildStatCard(
                            'Tổng check-in',
                            '${presentCount + lateCount}',
                            Icons.how_to_reg,
                            const Color(0xFF1976D2),
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            'Đúng giờ (Present)',
                            '$presentCount',
                            Icons.check_circle_outline,
                            Colors.green,
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            'Đi muộn (Late)',
                            '$lateCount',
                            Icons.access_time,
                            Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Attendance List Table
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Danh sách sinh viên vừa điểm danh',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Làm mới danh sách',
                                    onPressed: _fetchAttendanceList,
                                    icon: const Icon(Icons.refresh, size: 20),
                                  ),
                                ],
                              ),
                              const Divider(),
                              if (attendanceRecords.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Center(
                                    child: Text(
                                      'Chưa có sinh viên nào check-in.\nHướng dẫn sinh viên quét mã QR trên màn hình.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: attendanceRecords.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, idx) {
                                    final record = attendanceRecords[idx];
                                    final isPresent =
                                        record.status == 'PRESENT';

                                    return ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: isPresent
                                            ? Colors.green.shade50
                                            : Colors.orange.shade50,
                                        child: Icon(
                                          isPresent
                                              ? Icons.check
                                              : Icons.warning_amber_rounded,
                                          size: 16,
                                          color: isPresent
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      ),
                                      title: Text(
                                        record.fullName.isNotEmpty
                                            ? record.fullName
                                            : record.studentCode,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'MSSV: ${record.studentCode} · ${record.checkInTime.split('T').last.split('.').first}',
                                      ),
                                      trailing: Chip(
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: isPresent
                                            ? Colors.green.shade50
                                            : Colors.orange.shade50,
                                        label: Text(
                                          record.status,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isPresent
                                                ? Colors.green.shade800
                                                : Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              Expanded(
                child: Column(
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
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
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

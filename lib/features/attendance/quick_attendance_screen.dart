import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/teaching_occurrence.dart';
import '../../models/quick_attendance_draft.dart';
import '../../repositories/daily_attendance_repository.dart';
import '../../repositories/student_portal_repository.dart';
import '../../services/attendance_local_store.dart';
import '../student_portal/leave_request_panel.dart';

class QuickAttendanceScreen extends StatefulWidget {
  final DailyAttendanceRepository repository;
  final AttendanceData selector;
  final String owner;
  final AttendanceLocalStore store;
  final StudentPortalRepository? portalRepository;
  final VoidCallback? onSaved;
  const QuickAttendanceScreen({
    super.key,
    required this.repository,
    required this.selector,
    required this.owner,
    required this.store,
    this.portalRepository,
    this.onSaved,
  });
  @override
  State<QuickAttendanceScreen> createState() => _QuickAttendanceScreenState();
}

class _QuickAttendanceScreenState extends State<QuickAttendanceScreen> {
  AttendanceData? data, pending;
  QuickAttendanceDraft? draft;
  bool busy = false, restored = false;
  String? error, message;
  final search = TextEditingController();
  QuickFilter filter = QuickFilter.all;
  Timer? timer;
  DateTime? loadedAt;
  Future<void> persisting = Future.value();
  String get key => quickDraftKey(widget.owner, widget.selector);
  DateTime get serverNow => DateTime.fromMillisecondsSinceEpoch(
    (data!['serverTime'] as num).toInt(),
    isUtc: true,
  ).add(DateTime.now().difference(loadedAt!));
  bool get editable =>
      data?['editable'] == true &&
      serverNow.isBefore(
        DateTime.parse(
          '${widget.selector['sessionDate']}T00:00:00+07:00',
        ).add(const Duration(days: 1)),
      );
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && data != null) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.repository.call(
        'getQuickAttendanceContext',
        widget.selector,
      );
      final next = QuickAttendanceDraft(
        (value['students'] as List)
            .map((r) => QuickStudent.fromMap(AttendanceData.from(r as Map)))
            .toList(),
        revision: '${value['revision'] ?? ''}',
      );
      final saved = await widget.store.read(key),
          pendingText = await widget.store.read('$key/pending');
      AttendanceData? savedPending;
      if (pendingText != null) {
        try {
          savedPending = AttendanceData.from(jsonDecode(pendingText) as Map);
        } catch (_) {
          await widget.store.delete('$key/pending');
        }
      }
      final wasRestored = value['editable'] == true && next.restore(saved);
      if (!mounted) return;
      setState(() {
        data = value;
        loadedAt = DateTime.now();
        draft = next;
        pending = savedPending;
        restored = wasRestored;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void persist() {
    final source = draft!.encode();
    persisting = persisting
        .catchError((Object _) {})
        .then((_) => widget.store.write(key, source));
    unawaited(
      persisting.catchError((Object _) {
        if (mounted) {
          setState(
            () => error =
                'Không lưu được bản nháp trên máy. Hãy kiểm tra lại trước khi rời trang.',
          );
        }
      }),
    );
  }

  Future<bool> confirmDiscard() async {
    if (draft?.dirty != true && pending == null) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bỏ bản nháp và tải lại?'),
            content: const Text(
              'Kết quả đã lưu trên máy chủ sẽ được giữ. Các thay đổi chưa gửi trên máy này sẽ bị bỏ.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Tiếp tục sửa'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Bỏ nháp / Tải lại'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> reload() async {
    if (!await confirmDiscard() || !mounted) return;
    await persisting.catchError((Object _) {});
    try {
      await widget.store.delete(key);
      await widget.store.delete('$key/pending');
    } catch (e) {
      if (mounted) setState(() => error = 'Không xóa được nháp: $e');
      return;
    }
    await load();
  }

  Future<void> review() async {
    final d = draft!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          pending == null
              ? 'Kiểm tra trước khi lưu'
              : 'Kiểm tra lần gửi chưa xác nhận',
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data!['classCode']} · ${widget.selector['sessionDate']} · Slot ${widget.selector['slot']}',
                ),
                const SizedBox(height: 12),
                Text(d.summary()),
                if (pending != null)
                  const Text(
                    'Sẽ gửi lại đúng yêu cầu trước đó để kiểm tra biên nhận. Không tạo lần điểm danh mới.',
                  ),
                if (pending == null) ...[
                  const Text(
                    'Sinh viên chưa có kết quả được mặc định Có mặt. Chỉ lưu sau khi bạn xác nhận.',
                  ),
                  for (final s in d.exceptions)
                    Text('${s.code} · ${s.name}: Vắng'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              pending == null ? 'Xác nhận lưu điểm danh' : 'Kiểm tra / Gửi lại',
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await submit();
  }

  Future<void> submit() async {
    if (busy ||
        draft == null ||
        (pending == null && (!editable || draft!.students.isEmpty))) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await persisting;
      pending ??= draft!.payload(
        widget.selector,
        'desktop-${const Uuid().v4()}',
      );
      await widget.store.write('$key/pending', jsonEncode(pending));
      final result = await widget.repository.call(
        'submitQuickAttendance',
        pending!,
      );
      await widget.store.delete(key);
      await widget.store.delete('$key/pending');
      if (!mounted) return;
      setState(() {
        pending = null;
        message = result['alreadySaved'] == true
            ? 'Máy chủ đã lưu lần gửi trước. Đã xác nhận kết quả.'
            : 'Đã lưu điểm danh và chốt buổi học.';
      });
      widget.onSaved?.call();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Điểm danh nhanh')),
      body: data == null || draft == null
          ? Center(
              child: busy
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error ?? 'Chưa tải được buổi học.'),
                        FilledButton(
                          onPressed: load,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data!['subjectId']} · ${data!['classCode']} · ${widget.selector['sessionDate']} · Slot ${widget.selector['slot']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${data!['scheduledStartTime']}–${data!['scheduledEndTime']} · Phòng ${data!['room'] ?? ''}',
                      ),
                      const Text(
                        'Có thể điểm danh và điều chỉnh trong ngày học, đến trước 00:00 giờ Việt Nam.',
                      ),
                      Text(
                        draft!.summary(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (busy) const LinearProgressIndicator(),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (message != null)
                        Text(
                          message!,
                          style: const TextStyle(color: Colors.green),
                        ),
                      if (restored)
                        const Text(
                          'Đã khôi phục bản nháp trên máy; bản nháp chưa phải kết quả chính thức.',
                        ),
                      if (pending != null)
                        const Text(
                          'Có lần gửi chưa xác nhận. Kiểm tra/gửi lại hoặc tải lại để đối chiếu trước khi sửa tiếp.',
                          style: TextStyle(color: Colors.deepOrange),
                        ),
                      if (!editable && pending == null)
                        const Text(
                          'Buổi học chỉ được xem. Ngày đã qua hoặc lịch không còn cho phép chỉnh sửa.',
                        ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed:
                                busy ||
                                    draft!.students.isEmpty ||
                                    (pending == null && !editable)
                                ? null
                                : review,
                            child: Text(
                              pending != null
                                  ? 'Kiểm tra lần gửi trước'
                                  : data!['attendanceCompleted'] == true
                                  ? 'Kiểm tra / Lưu điều chỉnh'
                                  : 'Kiểm tra / Lưu điểm danh',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : reload,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tải lại từ máy chủ'),
                          ),
                          TextButton.icon(
                            onPressed:
                                busy ||
                                    pending != null ||
                                    !editable ||
                                    !draft!.canUndo
                                ? null
                                : () => setState(() {
                                    draft!.undo();
                                    persist();
                                  }),
                            icon: const Icon(Icons.undo),
                            label: const Text('Hoàn tác'),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: search,
                              decoration: const InputDecoration(
                                labelText: 'Tìm MSSV hoặc họ tên',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilterChip(
                            label: const Text('Chỉ sinh viên Vắng'),
                            selected: filter == QuickFilter.exceptions,
                            onSelected: (v) => setState(
                              () => filter = v
                                  ? QuickFilter.exceptions
                                  : QuickFilter.all,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (widget.portalRepository != null)
                        LeaveRequestPanel(
                          repository: widget.portalRepository!,
                          classId: '${widget.selector['classId']}',
                          sessionDate: '${widget.selector['sessionDate']}',
                          slot: int.parse('${widget.selector['slot']}'),
                        ),
                      if (draft!.students.isEmpty)
                        const ListTile(
                          title: Text(
                            'Lớp chưa có danh sách sinh viên. Nhập danh sách tại mục Lớp học.',
                          ),
                        ),
                      for (final s in draft!.visible(filter, search.text))
                        ListTile(
                          title: Text('${s.code} · ${s.name}'),
                          subtitle: Text(
                            s.existing == null
                                ? 'Mặc định Có mặt · chưa lưu'
                                : 'Đã lưu: ${quickStatusLabel(s.existing!)}',
                          ),
                          trailing: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'present',
                                label: Text('Có mặt'),
                              ),
                              ButtonSegment(
                                value: 'absent',
                                label: Text('Vắng'),
                              ),
                            ],
                            selected: {draft!.statusOf(s.id)},
                            onSelectionChanged:
                                busy || !editable || pending != null
                                ? null
                                : (values) => setState(() {
                                    draft!.set(s.id, values.single);
                                    persist();
                                  }),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    ),
  );
}

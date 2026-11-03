import 'package:flutter/material.dart';
import '../../repositories/student_portal_repository.dart';

class LeaveRequestPanel extends StatefulWidget {
  final StudentPortalRepository repository;
  final String classId;
  final String? sessionDate, sessionId;
  final int? slot;
  final bool sessionClosed;
  final VoidCallback? onAttendanceChanged;
  const LeaveRequestPanel({
    super.key,
    required this.repository,
    required this.classId,
    this.sessionDate,
    this.slot,
    this.sessionId,
    this.sessionClosed = false,
    this.onAttendanceChanged,
  });
  @override
  State<LeaveRequestPanel> createState() => _LeaveRequestPanelState();
}

class _LeaveRequestPanelState extends State<LeaveRequestPanel> {
  List<PortalRow> rows = [];
  bool busy = false;
  String? error;
  String filter = 'ALL';
  static const labels = {
    'PENDING': 'Chờ duyệt',
    'APPROVED': 'Đã duyệt',
    'REJECTED': 'Từ chối',
    'CANCELLED': 'Đã hủy',
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.call('listClassLeaveRequests', {
        'classId': widget.classId,
        if (widget.sessionDate != null) 'sessionDate': widget.sessionDate,
        if (widget.slot != null) 'slot': widget.slot,
      });
      if (mounted) {
        setState(
          () => rows = (result as List)
              .map((r) => PortalRow.from(r as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(PortalRow row, String status) async {
    final note = TextEditingController();
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          status == 'APPROVED'
              ? 'Duyệt đơn xin nghỉ?'
              : 'Từ chối đơn xin nghỉ?',
        ),
        content: SizedBox(
          width: 480,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${row['fullName']} · ${row['sessionDate']} · Slot ${row['slot']}',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Phản hồi cho sinh viên',
                  ),
                  validator: (v) =>
                      status == 'REJECTED' && (v?.trim().isEmpty ?? true)
                      ? 'Nhập lý do từ chối'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    // Controllers used by a dialog remain alive through its closing animation.
    Future.delayed(const Duration(seconds: 1), note.dispose);
    if (confirmed != true || !mounted) return;
    await mutate('reviewLeaveRequest', {
      'classId': widget.classId,
      'id': row['id'],
      'version': row['version'],
      'status': status,
      'reviewNote': text,
    });
  }

  Future<void> mutate(String method, PortalRow data) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.call(method, data);
      if (!mounted) return;
      widget.onAttendanceChanged?.call();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        rows.where((r) => filter == 'ALL' || r['status'] == filter).toList()
          ..sort(
            (a, b) => '${b['submittedAt']}'.compareTo('${a['submittedAt']}'),
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Đơn xin nghỉ (${rows.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                DropdownButton<String>(
                  value: filter,
                  items: {'ALL': 'Tất cả', ...labels}.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => filter = v!),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tải lại đơn'),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!busy && visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Chưa có đơn xin nghỉ phù hợp.'),
              ),
            for (final r in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    Text(
                      '${r['studentCode']} · ${r['fullName']} — ${r['sessionDate']} · Slot ${r['slot']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SelectableText('${r['reason']}'),
                    Text(
                      '${labels[r['status']] ?? r['status']} · Gửi: ${r['submittedAt']}',
                    ),
                    if ('${r['reviewNote'] ?? ''}'.isNotEmpty)
                      Text('Phản hồi: ${r['reviewNote']}'),
                    if (r['scheduleChanged'] == true)
                      const Text(
                        'Lịch đã thay đổi. Cần kiểm tra lại đơn.',
                        style: TextStyle(color: Colors.deepOrange),
                      ),
                    if (r['status'] == 'PENDING')
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: busy || r['scheduleChanged'] == true
                                ? null
                                : () => review(r, 'APPROVED'),
                            child: const Text('Duyệt'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => review(r, 'REJECTED'),
                            child: const Text('Từ chối'),
                          ),
                        ],
                      ),
                    if (r['status'] == 'APPROVED' &&
                        widget.sessionClosed &&
                        r['scheduleChanged'] != true)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => mutate('applyApprovedLeave', {
                                'sessionId': widget.sessionId,
                                'studentId': r['studentId'],
                              }),
                        child: const Text(
                          'Cập nhật nghỉ có phép cho phiên đã chốt',
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
}

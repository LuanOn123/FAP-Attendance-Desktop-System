import 'package:flutter/material.dart';
import 'group_api.dart';

String groupTaskDeadline(DateTime utc) {
  final vn = utc.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(vn.day)}/${two(vn.month)}/${vn.year} ${two(vn.hour)}:${two(vn.minute)}';
}

class GroupTasksPage extends StatefulWidget {
  final GroupCall call;
  final String classId, groupId, groupName;
  final int version, memberCount;
  const GroupTasksPage({
    super.key,
    required this.call,
    required this.classId,
    required this.groupId,
    required this.groupName,
    required this.version,
    required this.memberCount,
  });
  @override
  State<GroupTasksPage> createState() => _GroupTasksPageState();
}

class _GroupTasksPageState extends State<GroupTasksPage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController();
  DateTime? dueAt;
  Map<String, dynamic>? pending;
  List<Map<String, dynamic>> tasks = [];
  bool busy = false, loading = true, confirming = false;
  String? error, success;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await widget.call('listGroupTasks', {
        'classId': widget.classId,
        'groupId': widget.groupId,
      });
      if (!mounted) return;
      setState(() {
        tasks = (result['tasks'] as List)
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList();
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Chưa tải được công việc. Kiểm tra kết nối và thử lại.';
        });
      }
    }
  }

  Future<void> chooseDeadline() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;
    setState(
      () => dueAt = DateTime.utc(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).subtract(const Duration(hours: 7)),
    );
  }

  Future<void> assign() async {
    if (busy || confirming) return;
    if (pending == null) {
      if (!form.currentState!.validate()) return;
      if (dueAt == null || !dueAt!.isAfter(DateTime.now().toUtc())) {
        setState(() => error = 'Chọn hạn hoàn thành trong tương lai.');
        return;
      }
      confirming = true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Xác nhận giao việc'),
          content: Text(
            '${title.text.trim()}\n${widget.groupName} · ${widget.memberCount} sinh viên\nHạn: ${groupTaskDeadline(dueAt!)} (giờ Việt Nam)\n\nTạo thông báo trên Student Web và xếp hàng gửi email trường cho từng thành viên.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Giao việc'),
            ),
          ],
        ),
      );
      confirming = false;
      if (confirmed != true || !mounted) return;
      pending = {
        'classId': widget.classId,
        'groupId': widget.groupId,
        'version': widget.version,
        'title': title.text.trim(),
        'description': description.text.trim(),
        'dueAt': dueAt!.toUtc().toIso8601String(),
        'requestKey': groupRequestKey(),
      };
    }
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      final receipt = await widget.call('createGroupTask', pending!);
      if (!mounted) return;
      setState(() {
        pending = null;
        title.clear();
        description.clear();
        dueAt = null;
        success =
            'Đã giao việc · ${receipt['recipientCount']} người nhận. Email đang được xử lý.';
      });
      await load();
    } catch (e) {
      if (mounted) {
        const errors = {
          'VERSION_CONFLICT':
              'Danh sách nhóm đã thay đổi. Quay lại và tải lại nhóm trước khi giao việc.',
          'ROSTER_CHANGED':
              'Danh sách lớp đã thay đổi. Quay lại và lưu lại nhóm.',
          'GROUP_MEMBER_EMAIL_INVALID':
              'Có thành viên thiếu email trường hợp lệ hoặc trùng email. Kiểm tra hồ sơ sinh viên.',
          'GROUP_TASKS_SETUP_REQUIRED':
              'Backend chưa bật giao việc. Quản trị viên cần chạy setupGroupTasks và cập nhật deployment.',
          'INVALID_TASK_DEADLINE':
              'Hạn hoàn thành phải ở tương lai. Chọn lại hạn.',
          'INVALID_TASK': 'Kiểm tra tên việc và yêu cầu trước khi gửi.',
          'EMPTY_GROUP': 'Nhóm chưa có thành viên.',
          'GROUP_ACCESS_DENIED':
              'Nhóm không còn khả dụng. Quay lại và tải lại nhóm.',
          'PERMISSION_DENIED':
              'Tài khoản không có quyền giao việc cho lớp này.',
        };
        final known = errors.keys
            .where((code) => e.toString().contains(code))
            .firstOrNull;
        setState(() {
          if (known != null) pending = null;
          error = known == null
              ? 'Chưa xác nhận kết quả. Bấm Thử lại để kiểm tra cùng lần giao việc, tránh tạo trùng.'
              : errors[known];
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Giao việc · ${widget.groupName}')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (success != null) Semantics(liveRegion: true, child: Text(success!)),
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: title,
                enabled: !busy && pending == null,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Tên việc'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nhập tên việc' : null,
              ),
              TextFormField(
                controller: description,
                enabled: !busy && pending == null,
                maxLength: 4000,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Yêu cầu'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nhập yêu cầu' : null,
              ),
              OutlinedButton.icon(
                onPressed: busy || pending != null ? null : chooseDeadline,
                icon: const Icon(Icons.event),
                label: Text(
                  dueAt == null
                      ? 'Chọn hạn · Giờ Việt Nam'
                      : groupTaskDeadline(dueAt!),
                ),
              ),
              Text(
                '${widget.memberCount} thành viên · Student Web + email trường',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy || widget.memberCount == 0 ? null : assign,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  pending == null ? 'Giao việc' : 'Thử lại cùng lần giao việc',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Việc đã giao', style: Theme.of(context).textTheme.titleLarge),
        TextButton(
          onPressed: busy || loading ? null : load,
          child: const Text('Tải lại công việc'),
        ),
        if (loading) const LinearProgressIndicator(),
        if (!loading && tasks.isEmpty) const Text('Chưa có việc được giao.'),
        for (final t in tasks)
          Card(
            child: ListTile(
              title: Text('${t['title']}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t['description']}'),
                  Text('Hạn: ${groupTaskDeadline(DateTime.parse(t['dueAt']))}'),
                  Text(
                    'Đã đọc ${t['readCount']}/${t['recipientCount']} · Email đã gửi ${t['emailSentCount']}/${t['recipientCount']}',
                  ),
                  if ((t['emailPendingCount'] as num? ?? 0) > 0)
                    Text('Email chờ gửi: ${t['emailPendingCount']}'),
                  if ((t['emailReviewCount'] as num? ?? 0) > 0)
                    const Text('Một số email cần quản trị viên kiểm tra.'),
                  if ((t['emailSkippedCount'] as num? ?? 0) > 0)
                    Text(
                      'Email bỏ qua do thay đổi thành viên: ${t['emailSkippedCount']}',
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

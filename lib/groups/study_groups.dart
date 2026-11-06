import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'group_signup_panel.dart';
import 'group_tasks.dart';

typedef GroupCall =
    Future<dynamic> Function(String method, Map<String, dynamic> data);
String groupRequestKey() {
  final r = Random.secure();
  return List.generate(
    24,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class StudyGroups extends StatefulWidget {
  final GroupCall call;
  final String classId;
  const StudyGroups({super.key, required this.call, required this.classId});
  @override
  State<StudyGroups> createState() => _StudyGroupsState();
}

class _StudyGroupsState extends State<StudyGroups> {
  Map<String, dynamic>? plan;
  List<Map<String, dynamic>> groups = [], students = [], messages = [];
  String? selected, error, older;
  int count = 4;
  bool busy = false, dirty = false, loading = true, polling = false;
  final text = TextEditingController();
  Map<String, dynamic>? attachment, pending;
  Timer? timer;
  int generation = 0;
  bool firstMessages = true;
  bool signupLocked = false;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!busy && selected != null) readMessages();
    });
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = 'Chưa hoàn tất: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    try {
      final value = Map<String, dynamic>.from(
        await widget.call('getGroupPlan', {'classId': widget.classId}) as Map,
      );
      if (!mounted) return;
      setState(() {
        plan = value;
        groups = (value['groups'] as List)
            .map((g) => Map<String, dynamic>.from(g as Map))
            .toList();
        students = (value['students'] as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
        selected = groups.any((g) => g['id'] == selected)
            ? selected
            : groups.firstOrNull?['id'];
        dirty = false;
        loading = false;
        error = null;
      });
      await readMessages();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> readMessages({bool previous = false}) async {
    if (selected == null || polling || dirty) return;
    polling = true;
    final id = selected, epoch = generation;
    try {
      final v = await widget.call('getGroupMessages', {
        'classId': widget.classId,
        'groupId': id,
        if (previous && older != null) 'before': older,
      });
      if (!mounted || epoch != generation || selected != id) return;
      setState(() {
        final rows = (v['messages'] as List)
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList();
        messages = previous
            ? [...rows, ...messages]
            : {
                for (final m in [...messages, ...rows]) m['id']: m,
              }.values.toList();
        if (previous || firstMessages) older = v['older'];
        firstMessages = false;
        error = null;
      });
    } catch (e) {
      if (mounted && selected == id) {
        setState(() {
          error = '$e';
          messages = [];
        });
      }
    } finally {
      polling = false;
    }
  }

  Future<void> save() async {
    final payload = {
      'classId': widget.classId,
      'version': plan!['version'],
      'groups': groups
          .map(
            (g) => {
              ...g,
              'memberIds': (g['memberIds'] as List)
                  .where((id) => students.any((s) => s['studentId'] == id))
                  .toList(),
            },
          )
          .toList(),
      'requestKey': groupRequestKey(),
    };
    await widget.call('saveGroupPlan', payload);
    await load();
  }

  void divide() {
    final shuffled = [...students]..shuffle(Random.secure());
    final n = count.clamp(1, max(1, min(50, students.length))).toInt();
    setState(() {
      groups = List.generate(
        n,
        (i) => {
          'id': groupRequestKey(),
          'name': 'Nhóm ${i + 1}',
          'memberIds': <String>[],
        },
      );
      for (var i = 0; i < shuffled.length; i++) {
        (groups[i % n]['memberIds'] as List).add(shuffled[i]['studentId']);
      }
      selected = groups.first['id'];
      messages = [];
      dirty = true;
    });
  }

  Future<void> send() async {
    pending ??= {
      'classId': widget.classId,
      'groupId': selected,
      'text': text.text,
      if (attachment != null) 'file': attachment,
      'requestKey': groupRequestKey(),
    };
    await widget.call('sendGroupMessage', pending!);
    pending = null;
    text.clear();
    attachment = null;
    await readMessages();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Nhóm học tập', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Chia nhóm, trao đổi và chia sẻ tài liệu trong lớp.'),
      if (plan != null)
        GroupSignupPanel(
          key: ValueKey('signup/${widget.classId}'),
          call: widget.call,
          classId: widget.classId,
          version: plan!['version'] as int,
          groupCount: count,
          existingGroupCount: groups.length,
          disabled:
              busy ||
              dirty ||
              pending != null ||
              text.text.isNotEmpty ||
              attachment != null,
          hasUnsavedChanges: () =>
              busy ||
              dirty ||
              pending != null ||
              text.text.isNotEmpty ||
              attachment != null,
          onChanged: load,
          onLockChanged: (value) {
            if (mounted) setState(() => signupLocked = value);
          },
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (loading) const LinearProgressIndicator(),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<int>(
              initialValue: count,
              decoration: const InputDecoration(labelText: 'Số nhóm'),
              items: List.generate(
                50,
                (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
              ),
              onChanged: busy || signupLocked
                  ? null
                  : (v) => setState(() => count = v!),
            ),
          ),
          OutlinedButton(
            onPressed: busy || signupLocked || plan == null || pending != null
                ? null
                : divide,
            child: const Text('Chia ngẫu nhiên'),
          ),
          FilledButton(
            onPressed: busy || signupLocked || !dirty
                ? null
                : () => action(save),
            child: const Text('Lưu cách chia nhóm'),
          ),
          TextButton(
            onPressed: busy || pending != null
                ? null
                : () async {
                    if (dirty &&
                        !await confirm(
                          context,
                          'Bỏ cách chia chưa lưu và tải lại?',
                        )) {
                      return;
                    }
                    await load();
                  },
            child: const Text('Tải lại'),
          ),
        ],
      ),
      if (dirty)
        const Text(
          'Chưa lưu. Chia lại tạo phòng chat mới; phòng cũ không bị xóa. Lưu để sinh viên thấy nhóm mới.',
        ),
      if (plan != null && groups.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Chưa chia nhóm. Chọn số nhóm và bấm Chia ngẫu nhiên.'),
        ),
      for (final g in groups)
        Card(
          key: ValueKey('group/${g['id']}'),
          child: ExpansionTile(
            key: ValueKey(g['id']),
            title: Text(
              '${g['name']} · ${(g['memberIds'] as List).length} thành viên',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextFormField(
                  key: ValueKey('${g['id']}-name'),
                  initialValue: g['name'],
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Tên nhóm'),
                  enabled: !busy && !signupLocked && pending == null,
                  onChanged: (v) => setState(() {
                    g['name'] = v;
                    dirty = true;
                  }),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Giao việc cho nhóm'),
                onPressed:
                    busy ||
                        dirty ||
                        pending != null ||
                        text.text.isNotEmpty ||
                        attachment != null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupTasksPage(
                            call: widget.call,
                            classId: widget.classId,
                            groupId: g['id'],
                            groupName: g['name'],
                            version: plan!['version'] as int,
                            memberCount: (g['memberIds'] as List).length,
                          ),
                        ),
                      ),
              ),
              for (final s in students.where(
                (s) => (g['memberIds'] as List).contains(s['studentId']),
              ))
                ListTile(
                  title: Text('${s['fullName']}'),
                  subtitle: Text('${s['studentCode']}'),
                  trailing: DropdownButton<String>(
                    value: g['id'],
                    items: groups
                        .map(
                          (x) => DropdownMenuItem<String>(
                            value: x['id'],
                            child: Text('${x['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: busy || signupLocked || pending != null
                        ? null
                        : (id) => setState(() {
                            for (final x in groups) {
                              x['memberIds'] = List.of(x['memberIds'])
                                ..remove(s['studentId']);
                            }
                            (groups.firstWhere(
                                      (x) => x['id'] == id,
                                    )['memberIds']
                                    as List)
                                .add(s['studentId']);
                            dirty = true;
                          }),
                  ),
                ),
            ],
          ),
        ),
      if (groups.isNotEmpty &&
          students.any(
            (s) => !groups.any(
              (g) => (g['memberIds'] as List).contains(s['studentId']),
            ),
          )) ...[
        const Text(
          'Sinh viên chưa được phân nhóm',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final s in students.where(
          (s) => !groups.any(
            (g) => (g['memberIds'] as List).contains(s['studentId']),
          ),
        ))
          ListTile(
            title: Text('${s['fullName']}'),
            subtitle: Text('${s['studentCode']}'),
            trailing: DropdownButton<String>(
              hint: const Text('Chọn nhóm'),
              items: groups
                  .map(
                    (g) => DropdownMenuItem<String>(
                      value: g['id'],
                      child: Text('${g['name']}'),
                    ),
                  )
                  .toList(),
              onChanged: busy || signupLocked
                  ? null
                  : (id) => setState(() {
                      (groups.firstWhere((g) => g['id'] == id)['memberIds']
                              as List)
                          .add(s['studentId']);
                      dirty = true;
                    }),
            ),
          ),
      ],
      if (groups.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          key: ValueKey(selected),
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Phòng trao đổi'),
          items: groups
              .map(
                (g) => DropdownMenuItem<String>(
                  value: g['id'],
                  child: Text('${g['name']}'),
                ),
              )
              .toList(),
          onChanged: busy || pending != null
              ? null
              : (v) {
                  setState(() {
                    selected = v;
                    messages = [];
                    older = null;
                    firstMessages = true;
                    generation++;
                  });
                  readMessages();
                },
        ),
        if (older != null)
          TextButton(
            onPressed: () => readMessages(previous: true),
            child: const Text('Tin nhắn cũ hơn'),
          ),
        for (final m in messages)
          Card(
            child: ListTile(
              title: Text('${m['senderName']} · ${m['createdAt']}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('${m['text']}'),
                  if (m['hasFile'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => action(() async {
                              final f = await widget.call('downloadGroupFile', {
                                'classId': widget.classId,
                                'groupId': selected,
                                'messageId': m['id'],
                              });
                              await FilePicker.platform.saveFile(
                                dialogTitle: 'Lưu tệp nhóm',
                                fileName: f['name'],
                                bytes: Uint8List.fromList(
                                  base64Decode(f['base64']),
                                ),
                              );
                            }),
                      child: Text('Tải ${m['fileName']}'),
                    ),
                ],
              ),
            ),
          ),
        TextField(
          controller: text,
          onChanged: (_) => setState(() {}),
          enabled: !busy && pending == null,
          maxLength: 2000,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Tin nhắn cho nhóm'),
        ),
        if (attachment != null) Text('Đính kèm: ${attachment!['name']}'),
        if (pending != null && !busy)
          TextButton(
            onPressed: () async {
              if (!await confirm(
                context,
                'Tin nhắn có thể đã được nhận. Bỏ bản chờ và kiểm tra lịch sử trước khi gửi mới?',
              )) {
                return;
              }
              if (!mounted) return;
              setState(() {
                pending = null;
                text.clear();
                attachment = null;
              });
              await load();
            },
            child: const Text('Bỏ bản gửi đang chờ và kiểm tra lại'),
          ),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton(
              onPressed: busy || dirty || pending != null
                  ? null
                  : () => action(() async {
                      final p = await FilePicker.platform.pickFiles(
                        withData: true,
                        type: FileType.custom,
                        allowedExtensions: [
                          'pdf',
                          'txt',
                          'png',
                          'jpg',
                          'jpeg',
                          'xlsx',
                          'docx',
                          'csv',
                        ],
                      );
                      if (p == null) return;
                      if (p.files.single.size > 512000 ||
                          p.files.single.bytes == null) {
                        throw StateError('Tệp tối đa 500 KB.');
                      }
                      attachment = {
                        'name': p.files.single.name,
                        'base64': base64Encode(p.files.single.bytes!),
                      };
                    }),
              child: const Text('Đính kèm (tối đa 500 KB)'),
            ),
            FilledButton(
              onPressed: busy || dirty ? null : () => action(send),
              child: Text(
                pending == null ? 'Gửi tin nhắn' : 'Thử gửi lại cùng tin',
              ),
            ),
          ],
        ),
      ],
    ],
  );
  Future<bool> confirm(BuildContext context, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Tiếp tục'),
            ),
          ],
        ),
      ) ??
      false;
}

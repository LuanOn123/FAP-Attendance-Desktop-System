import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'group_signup_panel.dart';
import 'group_api.dart';
import 'group_tasks.dart';
import '../services/schedule_clock.dart';

class StudyGroups extends StatefulWidget {
  final GroupCall call;
  final String classId;
  final bool startInChat;
  const StudyGroups({
    super.key,
    required this.call,
    required this.classId,
    this.startInChat = false,
  });
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
  late bool chatMode = widget.startInChat;
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
        final next = groups.any((g) => g['id'] == selected)
            ? selected
            : groups.firstOrNull?['id'];
        if (selected != next) resetConversation(next as String?);
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
    if (firstMessages && error != null) setState(() => error = null);
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
      if (mounted && epoch == generation && selected == id) {
        setState(() {
          error = '$e';
          messages = [];
        });
      }
    } finally {
      if (epoch == generation) polling = false;
    }
  }

  Widget emptyConversation() {
    if (dirty) return const Center(child: Text('Chưa lưu nhóm'));
    if (error != null) return const SizedBox.shrink();
    return Center(
      child: Text(
        firstMessages
            ? 'Đang tải tin nhắn…'
            : 'Chưa có tin nhắn trong hội thoại này.',
        textAlign: TextAlign.center,
      ),
    );
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
      resetConversation(groups.first['id'] as String);
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
    if (!mounted) return;
    pending = null;
    text.clear();
    attachment = null;
    await readMessages();
  }

  void resetConversation(String? id) {
    selected = id;
    messages = [];
    older = null;
    firstMessages = true;
    polling = false;
    generation++;
  }

  Future<void> selectConversation(String id) async {
    if (id == selected || busy || pending != null) return;
    if ((text.text.isNotEmpty || attachment != null) &&
        !await confirm(context, 'Bỏ tin nhắn và tệp chưa gửi để đổi nhóm?')) {
      return;
    }
    if (!mounted || busy || pending != null) return;
    setState(() {
      text.clear();
      attachment = null;
      error = null;
      resetConversation(id);
    });
    await readMessages();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tin nhắn'),
              selected: chatMode,
              onSelected: (_) => setState(() => chatMode = true),
            ),
            ChoiceChip(
              label: const Text('Quản lý nhóm'),
              selected: !chatMode,
              onSelected: (_) => setState(() => chatMode = false),
            ),
          ],
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: chatMode ? 1 : 0,
          sizing: StackFit.expand,
          children: [management(), conversation()],
        ),
      ),
    ],
  );

  Widget management() => ListView(
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
    ],
  );

  Widget conversation() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (groups.isEmpty || selected == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error ?? 'Chưa có hội thoại. Tạo nhóm để bắt đầu trao đổi.'),
            TextButton(
              onPressed: error == null
                  ? () => setState(() => chatMode = false)
                  : load,
              child: Text(error == null ? 'Quản lý nhóm' : 'Tải lại nhóm'),
            ),
          ],
        ),
      );
    }
    final active = groups.firstWhere((group) => group['id'] == selected);
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 760;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) ...[
              SizedBox(
                width: 252,
                child: Material(
                  color: colors.surface,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'HỘI THOẠI',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final group in groups)
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          selected: selected == group['id'],
                          selectedTileColor: const Color(0xFFE5F0FF),
                          leading: const CircleAvatar(
                            child: Icon(Icons.groups_outlined),
                          ),
                          title: Text(
                            '${group['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${(group['memberIds'] as List).length} thành viên',
                          ),
                          onTap: busy || pending != null
                              ? null
                              : () => selectConversation(group['id'] as String),
                        ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: colors.surface,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      leading: const CircleAvatar(
                        child: Icon(Icons.forum_outlined),
                      ),
                      title: wide
                          ? Text(
                              '${active['name']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            )
                          : DropdownButton<String>(
                              value: selected,
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final group in groups)
                                  DropdownMenuItem(
                                    value: group['id'] as String,
                                    child: Text(
                                      '${group['name']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: busy || pending != null
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        selectConversation(value);
                                      }
                                    },
                            ),
                      subtitle: Text(
                        '${(active['memberIds'] as List).length} thành viên',
                      ),
                      trailing: IconButton(
                        tooltip: 'Tải lại tin nhắn',
                        icon: const Icon(Icons.refresh),
                        onPressed: busy || dirty ? null : readMessages,
                      ),
                    ),
                  ),
                  if (dirty || error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        dirty
                            ? 'Lưu cách chia nhóm trước khi nhắn tin.'
                            : error!,
                      ),
                    ),
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFFEAF0F7),
                      child: messages.isEmpty
                          ? emptyConversation()
                          : ListView.builder(
                              key: ValueKey(selected),
                              reverse: true,
                              padding: const EdgeInsets.all(16),
                              itemCount:
                                  messages.length + (older == null ? 0 : 1),
                              itemBuilder: (context, index) {
                                if (index == messages.length) {
                                  return Center(
                                    child: TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => readMessages(previous: true),
                                      child: const Text('Tin nhắn cũ hơn'),
                                    ),
                                  );
                                }
                                final i = messages.length - index - 1;
                                final current = messages[i];
                                final day = messageDate(current);
                                return Column(
                                  children: [
                                    if (day != null &&
                                        (i == 0 ||
                                            messageDate(messages[i - 1]) !=
                                                day))
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Chip(label: Text(day)),
                                      ),
                                    messageBubble(current),
                                  ],
                                );
                              },
                            ),
                    ),
                  ),
                  composer(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  DateTime? messageTime(Map<String, dynamic> message) =>
      DateTime.tryParse('${message['createdAt'] ?? ''}');

  String? messageDate(Map<String, dynamic> message) {
    final at = messageTime(message);
    return at == null ? null : ScheduleClock.date(ScheduleClock.now(at));
  }

  Widget messageBubble(Map<String, dynamic> message) {
    final mine =
        message['mine'] == true ||
        (message['sender'] != null && message['sender'] == plan?['viewerId']);
    final at = messageTime(message);
    final delivery = message['delivery'] as Map?;
    final count = delivery?['recipientCount'] ?? 0;
    final read = (delivery?['readCount'] as num?) ?? 0;
    final delivered = (delivery?['deliveredCount'] as num?) ?? 0;
    final status = read > 0
        ? 'Đã xem $read/$count'
        : delivered > 0
        ? 'Đã nhận $delivered/$count'
        : 'Đã gửi';
    final body = '${message['text'] ?? ''}';
    final name = '${message['senderName'] ?? 'Thành viên'}'.trim();
    return LayoutBuilder(
      builder: (context, box) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            if (!mine)
              CircleAvatar(
                radius: 16,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: min(560.0, box.maxWidth * .72),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: mine ? const Color(0xFFD8EBFF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD6E2F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      if (!mine)
                        Text(
                          name,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      if (body.isNotEmpty) SelectableText(body),
                      if (message['hasFile'] == true)
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => action(() => download(message)),
                          icon: const Icon(Icons.file_download_outlined),
                          label: Text('${message['fileName']}'),
                        ),
                      Text(
                        [
                          if (at != null)
                            TimeOfDay.fromDateTime(
                              ScheduleClock.now(at),
                            ).format(context),
                          if (mine) status,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget composer() {
    final canSend =
        !busy &&
        !dirty &&
        (pending != null || text.text.trim().isNotEmpty || attachment != null);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null)
              InputChip(
                label: Text(
                  '${attachment!['name']}',
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: busy || pending != null
                    ? null
                    : () => setState(() => attachment = null),
              ),
            if (pending != null && !busy)
              TextButton(
                onPressed: discardPending,
                child: const Text('Bỏ bản gửi đang chờ và kiểm tra lại'),
              ),
            Row(
              spacing: 8,
              children: [
                IconButton(
                  tooltip: 'Đính kèm (tối đa 500 KB)',
                  onPressed: busy || dirty || pending != null
                      ? null
                      : () => action(pickAttachment),
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    controller: text,
                    onChanged: (_) => setState(() {}),
                    enabled: !busy && !dirty && pending == null,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Tin nhắn cho nhóm',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: pending == null
                      ? 'Gửi tin nhắn'
                      : 'Thử gửi lại cùng tin',
                  onPressed: canSend ? () => action(send) : null,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF0068DB),
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(pending == null ? Icons.send : Icons.refresh),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> discardPending() async {
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
  }

  Future<void> pickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
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
    if (!mounted || picked == null) return;
    final file = picked.files.single;
    if (file.size > 512000 || file.bytes == null) {
      throw StateError('Tệp tối đa 500 KB.');
    }
    attachment = {'name': file.name, 'base64': base64Encode(file.bytes!)};
  }

  Future<void> download(Map<String, dynamic> message) async {
    final file = await widget.call('downloadGroupFile', {
      'classId': widget.classId,
      'groupId': selected,
      'messageId': message['id'],
    });
    if (!mounted) return;
    await FilePicker.platform.saveFile(
      dialogTitle: 'Lưu tệp nhóm',
      fileName: file['name'],
      bytes: Uint8List.fromList(base64Decode(file['base64'])),
    );
  }

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

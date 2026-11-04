import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

String _signupTime(Object? value) {
  final parsed = DateTime.tryParse('$value');
  if (parsed == null) return 'Chưa có';
  final vn = parsed.toUtc().add(const Duration(hours: 7));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(vn.hour)}:${pad(vn.minute)} ${pad(vn.day)}/${pad(vn.month)}/${vn.year} · Giờ Việt Nam';
}

class GroupSignupPanel extends StatefulWidget {
  final Future<dynamic> Function(String, Map<String, dynamic>) call;
  final String classId;
  final int version, groupCount, existingGroupCount;
  final bool disabled;
  final bool Function()? hasUnsavedChanges;
  final Future<void> Function() onChanged;
  final void Function(bool) onLockChanged;
  const GroupSignupPanel({
    super.key,
    required this.call,
    required this.classId,
    required this.version,
    required this.groupCount,
    required this.existingGroupCount,
    required this.disabled,
    this.hasUnsavedChanges,
    required this.onChanged,
    required this.onLockChanged,
  });
  @override
  State<GroupSignupPanel> createState() => _GroupSignupPanelState();
}

class _GroupSignupPanelState extends State<GroupSignupPanel> {
  Map<String, dynamic>? sheet, pendingCreate;
  bool busy = false, reading = false, confirming = false;
  bool? lastLock;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    read();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!busy) read();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  bool get locked =>
      ['PREPARING', 'OPEN', 'CONFLICT'].contains(sheet?['state']);
  bool get disabled =>
      widget.disabled || widget.hasUnsavedChanges?.call() == true;

  void apply(Map<String, dynamic> value) {
    setState(() {
      sheet = value;
      error = null;
    });
    if (value['state'] == 'OPEN') pendingCreate = null;
    if (lastLock != locked) {
      lastLock = locked;
      widget.onLockChanged(locked);
    }
  }

  Future<void> read() async {
    if (reading || busy) return;
    reading = true;
    try {
      final value = Map<String, dynamic>.from(
        await widget.call('getGroupSignupSheet', {'classId': widget.classId})
            as Map,
      );
      if (!mounted) return;
      apply(value);
      if (!disabled &&
          value['currentPlanVersion'] != null &&
          value['currentPlanVersion'] != widget.version) {
        await widget.onChanged();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Chưa kiểm tra được Sheet đăng ký. Backend cần có tính năng này; bấm tải lại để thử.',
        );
      }
    } finally {
      reading = false;
    }
  }

  Future<bool> confirm(String title, String detail) async {
    if (confirming) return false;
    confirming = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(title),
              content: Text(detail),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Quay lại'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Xác nhận'),
                ),
              ],
            ),
          ) ==
          true;
    } finally {
      confirming = false;
    }
  }

  Future<void> run(String method) async {
    if (busy || confirming || disabled) return;
    if (method == 'createGroupSignupSheet' && pendingCreate == null) {
      final version = widget.version, count = widget.groupCount;
      if (!await confirm(
        'Mở đăng ký nhóm bằng Google Sheets?',
        '${widget.existingGroupCount > 0 ? 'Giữ ${widget.existingGroupCount} nhóm đã lưu và lựa chọn hiện tại.' : 'Tạo ${widget.groupCount} nhóm trống để sinh viên tự chọn.'}\n\nTạo một file riêng, cấp quyền cho email trường trong danh sách lớp. Mỗi sinh viên chỉ sửa ô chọn nhóm của mình. Các bạn cùng lớp xem được tên và MSSV trong bảng. Sau khi mở, chốt đăng ký trước khi sửa nhóm trực tiếp trong app.',
      )) {
        return;
      }
      if (!mounted) return;
      final random = Random.secure();
      pendingCreate = {
        'classId': widget.classId,
        'version': version,
        'groupCount': count,
        'requestKey': List.generate(
          24,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      };
    }
    if (method == 'closeGroupSignupSheet' &&
        !await confirm(
          'Chốt đăng ký?',
          'Dừng cho sinh viên đổi nhóm trên Sheet và giữ kết quả đã đồng bộ. Sinh viên chưa chọn nhóm sẽ còn trong danh sách chưa phân nhóm để giảng viên xử lý.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = Map<String, dynamic>.from(
        await widget.call(
              method,
              method == 'createGroupSignupSheet'
                  ? pendingCreate!
                  : {'classId': widget.classId},
            )
            as Map,
      );
      if (!mounted) return;
      apply(value);
      if (method == 'closeGroupSignupSheet') pendingCreate = null;
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() {
          final message = e.toString();
          error = message.contains('EMPTY_ROSTER')
              ? 'Lớp chưa có sinh viên để mở đăng ký.'
              : message.contains('CLASS_TOO_LARGE')
              ? 'Danh sách lớp quá lớn cho bảng đăng ký hiện tại. Liên hệ quản trị viên.'
              : message.contains('GROUP_SIGNUP_OPEN')
              ? 'Lớp đã có lượt đăng ký đang mở. Tải lại Sheet để tiếp tục.'
              : message.contains('GROUP_MEMBER_EMAIL_INVALID')
              ? 'Kiểm tra email trường bị thiếu hoặc trùng trong danh sách sinh viên.'
              : message.contains('GROUP_SIGNUP_SETUP_REQUIRED')
              ? 'Quản trị viên cần cập nhật backend và chạy setupGroupSignupSheets.'
              : message.contains('VERSION_CONFLICT') ||
                    message.contains('ROSTER_CHANGED')
              ? 'Nhóm đã thay đổi. Tải lại danh sách để kiểm tra trước khi mở đăng ký.'
              : 'Chưa xác nhận kết quả. Tạo Sheet có thể mất thời gian; thử lại cùng lượt để tránh tạo trùng. Kiểm tra quyền Google Sheets/Drive nếu còn lỗi.';
          if (message.contains('VERSION_CONFLICT') ||
              message.contains('ROSTER_CHANGED') ||
              message.contains('GROUP_MEMBER_EMAIL_INVALID') ||
              message.contains('EMPTY_ROSTER') ||
              message.contains('CLASS_TOO_LARGE') ||
              message.contains('GROUP_SIGNUP_OPEN') ||
              message.contains('GROUP_SIGNUP_SETUP_REQUIRED')) {
            pendingCreate = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = sheet?['state'] ?? 'NONE';
    final rawUrl = sheet?['url'] as String?;
    final url =
        rawUrl != null &&
            RegExp(
              r'^https://docs\.google\.com/spreadsheets/d/[A-Za-z0-9_-]+/edit#gid=\d+$',
            ).hasMatch(rawUrl)
        ? rawUrl
        : null;
    final labels = {
      'NONE': 'Chưa mở',
      'PREPARING': 'Đang tạo và cấp quyền',
      'OPEN': 'Đang mở',
      'CONFLICT': 'Cần kiểm tra dữ liệu',
      'CLOSED': 'Đã chốt',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sinh viên tự chọn nhóm',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Google Sheets · ${labels[state] ?? state}'),
            if (sheet != null && state != 'NONE')
              Text(
                '${sheet!['assignedCount']}/${sheet!['studentCount']} đã có nhóm · ${sheet!['groupCount']} nhóm',
              ),
            if (state == 'OPEN')
              const Text(
                'Sheet đồng bộ khoảng mỗi phút. Màn hình nhóm tự kiểm tra kết quả mỗi 15 giây khi không có bản nháp.',
              ),
            if (sheet?['lastError']?.toString().isNotEmpty == true)
              const Text(
                'Có lỗi đồng bộ. Kiểm tra ô chọn nhóm, danh sách lớp hoặc thay đổi nhóm; chưa nhận được bản mới.',
              ),
            if (sheet?['lastSyncedAt']?.toString().isNotEmpty == true)
              Text('Đồng bộ gần nhất: ${_signupTime(sheet!['lastSyncedAt'])}'),
            if (disabled)
              const Text(
                'Lưu hoặc bỏ thay đổi/bản nháp trước khi thao tác Sheet.',
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state == 'NONE' ||
                    state == 'CLOSED' ||
                    pendingCreate != null)
                  FilledButton.icon(
                    onPressed: busy || disabled
                        ? null
                        : () => run('createGroupSignupSheet'),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text(
                      pendingCreate == null
                          ? 'Tạo Sheet chọn nhóm'
                          : 'Thử tạo lại cùng Sheet',
                    ),
                  ),
                if (state == 'PREPARING' && pendingCreate == null)
                  OutlinedButton(
                    onPressed: busy || disabled
                        ? null
                        : () => run('resumeGroupSignupSheet'),
                    child: const Text('Tiếp tục tạo Sheet'),
                  ),
                if (state == 'OPEN')
                  OutlinedButton(
                    onPressed: busy || disabled
                        ? null
                        : () => run('syncGroupSignupSheet'),
                    child: const Text('Đồng bộ ngay'),
                  ),
                if (locked)
                  OutlinedButton(
                    onPressed: busy || disabled
                        ? null
                        : () => run('closeGroupSignupSheet'),
                    child: const Text('Chốt đăng ký'),
                  ),
                TextButton(
                  onPressed: busy ? null : read,
                  child: const Text('Tải lại Sheet'),
                ),
                if (url != null && state != 'PREPARING') ...[
                  OutlinedButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Đã sao chép link Sheet cho sinh viên.',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Sao chép link'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (!await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          ) &&
                          mounted) {
                        setState(
                          () => error =
                              'Chưa mở được trình duyệt. Sao chép link để mở.',
                        );
                      }
                    },
                    child: const Text('Mở Sheet'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

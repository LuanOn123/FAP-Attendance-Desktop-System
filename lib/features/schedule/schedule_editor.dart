import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/schedule.dart';

const scheduleLabels = <String, String>{
  'semester': 'Học kỳ (FA26)',
  'subjectCode': 'Mã môn (PRM393)',
  'subjectName': 'Tên môn',
  'classCode': 'Mã lớp (SE1848)',
  'dayOfWeek': 'Thứ: 1 = Thứ 2, …, 7 = CN',
  'slot': 'Slot (1–12)',
  'startTime': 'Giờ bắt đầu (HH:mm)',
  'endTime': 'Giờ kết thúc (HH:mm)',
  'room': 'Phòng học',
};

class ScheduleEditor extends StatefulWidget {
  final String lecturerId, sourceType;
  final Schedule? existing;
  final Map<String, String>? initial;
  final Future<void> Function(Schedule) onSave;
  const ScheduleEditor({
    super.key,
    required this.lecturerId,
    required this.onSave,
    this.sourceType = 'MANUAL',
    this.existing,
    this.initial,
  });
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  final formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late final String id;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    id = widget.existing?.scheduleId ?? const Uuid().v4();
    final initial = widget.existing?.toJson() ?? widget.initial ?? {};
    fields = {
      for (final key in scheduleLabels.keys)
        key: TextEditingController(text: '${initial[key] ?? ''}'),
    };
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    final row = Schedule(
      scheduleId: id,
      lecturerId: widget.lecturerId,
      semester: fields['semester']!.text.trim(),
      subjectCode: fields['subjectCode']!.text.trim(),
      subjectName: fields['subjectName']!.text.trim(),
      classCode: fields['classCode']!.text.trim(),
      dayOfWeek: int.tryParse(fields['dayOfWeek']!.text) ?? 0,
      slot: int.tryParse(fields['slot']!.text) ?? 0,
      startTime: fields['startTime']!.text.trim(),
      endTime: fields['endTime']!.text.trim(),
      room: fields['room']!.text.trim(),
      sourceType: widget.existing?.sourceType ?? widget.sourceType,
    );
    final errors = row.validate();
    if (errors.isNotEmpty) {
      setState(() => error = errors.join('\n'));
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(row);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Không lưu được. Kiểm tra kết nối rồi thử lại; dữ liệu nhập vẫn được giữ.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(
        widget.existing == null ? 'Thêm lịch dạy' : 'Chỉnh sửa lịch dạy',
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final entry in scheduleLabels.entries)
                      SizedBox(
                        width: 310,
                        child: TextFormField(
                          controller: fields[entry.key],
                          enabled: !saving,
                          decoration: InputDecoration(labelText: entry.value),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Bắt buộc' : null,
                        ),
                      ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Lưu lịch dạy'),
        ),
      ],
    ),
  );
}

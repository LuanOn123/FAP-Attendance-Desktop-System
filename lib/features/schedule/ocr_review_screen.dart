import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import 'package:uuid/uuid.dart';
import '../../core/app_config.dart';
import '../../models/schedule.dart';
import '../../repositories/schedule_repository.dart';
import '../../services/ocr_service.dart';
import '../../services/schedule_parser.dart';
import 'widgets/schedule_fields.dart';
import '../../shared/widgets/section_header.dart';

class OcrReviewScreen extends StatefulWidget {
  final String lecturerId;
  final ScheduleRepository repository;
  const OcrReviewScreen({
    super.key,
    required this.lecturerId,
    required this.repository,
  });
  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  final raw = TextEditingController();
  final semester = TextEditingController();
  final warnings = <List<String>>[];
  final rows = <Map<String, TextEditingController>>[];
  final ids = <String>[];
  String? imagePath, message;
  bool busy = false, confirmed = false;
  bool parsed = false;
  bool useNvhTimes = true;
  final semesterKey = GlobalKey<FormFieldState<String>>();

  bool validateSemester() => semesterKey.currentState?.validate() ?? false;
  @override
  void dispose() {
    raw.dispose();
    semester.dispose();
    clearRows();
    super.dispose();
  }

  void clearRows() {
    for (final row in rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    rows.clear();
    ids.clear();
    warnings.clear();
  }

  void addRow([Map<String, String> values = const {}]) {
    ids.add(const Uuid().v4());
    warnings.add([]);
    rows.add({
      for (final key in scheduleLabels.keys)
        key: TextEditingController(text: values[key] ?? ''),
    });
  }

  Future<void> pick() async {
    if (!validateSemester()) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await OcrService().pickAndRecognize();
      if (!mounted || result == null) return;
      setState(() {
        imagePath = result.path;
        raw.text = result.text;
        clearRows();
        parsed = false;
        confirmed = false;
      });
      parse();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void parse() {
    if (!validateSemester()) return;
    setState(() {
      clearRows();
      for (final draft in ScheduleParser().parse(
        raw.text,
        useNvhTimes: useNvhTimes,
      )) {
        addRow(draft.fields);
        if (rows.last['semester']!.text.isEmpty) {
          rows.last['semester']!.text = semester.text.trim().toUpperCase();
        }
        // Missing fields are visible in the editable form; parser warnings
        // predate the semester default and would otherwise report stale gaps.
        warnings.last = draft.warnings
            .where((warning) => !warning.startsWith('Cần bổ sung:'))
            .toList();
      }
      parsed = true;
      confirmed = false;
      message = rows.isEmpty
          ? 'Không nhận diện được dòng lịch. Bạn có thể thêm dòng và nhập thông tin từ ảnh.'
          : 'Đã nhận diện ${rows.length} dòng. Bổ sung ô trống và kiểm tra từng trường với ảnh gốc.';
    });
  }

  Future<void> save() async {
    if (busy || !confirmed || !parsed || rows.isEmpty) return;
    if (!validateSemester()) return;
    final schedules = <Schedule>[];
    for (var i = 0; i < rows.length; i++) {
      final f = rows[i];
      String value(String k) => f[k]!.text.trim();
      final schedule = Schedule(
        scheduleId: ids[i],
        lecturerId: widget.lecturerId,
        semester: value('semester'),
        subjectCode: value('subjectCode'),
        subjectName: value('subjectName').isNotEmpty
            ? value('subjectName')
            : value('subjectCode').toUpperCase(),
        classCode: value('classCode'),
        dayOfWeek: int.tryParse(value('dayOfWeek')) ?? 0,
        slot: int.tryParse(value('slot')) ?? 0,
        startTime: value('startTime'),
        endTime: value('endTime'),
        room: value('room'),
        sourceType: 'IMAGE',
      );
      final errors = schedule.validate();
      if (errors.isNotEmpty) {
        showSaveError('Dòng ${i + 1}: ${errors.join(' ')}');
        return;
      }
      schedules.add(schedule);
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.repository.save(schedules);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showSaveError(
          'Lưu thất bại. ${e is AppException ? e.message : 'Kiểm tra kết nối rồi thử lại.'} Dữ liệu đã nhập vẫn được giữ.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showSaveError(String text) {
    setState(() => message = text);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 12)),
      );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nhập ảnh • Duyệt thời khóa biểu'),
        actions: [
          FilledButton.icon(
            onPressed: busy || !confirmed || !parsed || rows.isEmpty
                ? null
                : save,
            icon: const Icon(Icons.check),
            label: const Text('Xác nhận & lưu'),
          ),
          const SizedBox(width: 24),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SectionHeader(
            eyebrow: 'NHẬP LỊCH DẠY',
            title: 'Duyệt thời khóa biểu',
            subtitle: 'Chọn học kỳ, tải ảnh và kiểm tra lịch trước khi lưu.',
          ),
          const SizedBox(height: 24),
          const Text(
            '01  CHỌN ẢNH     →     02  OCR / PHÂN TÍCH     →     03  DUYỆT & LƯU',
            style: TextStyle(
              color: AppPalette.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'A1/A2: thứ 2, 5 · A3/A4: thứ 3, 6 · A5/A6: thứ 4, 7. '
            'Mã lẻ/chẵn tương ứng slot 1/2; P tương tự với slot 3/4. '
            'Ảnh lịch tuần dùng trực tiếp thứ, slot và giờ trong từng ô. '
            'Ảnh phân công thiếu lớp/phòng/giờ: cần bổ sung, không ghép lớp chỉ theo mã môn.',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: useNvhTimes,
            onChanged: busy
                ? null
                : (value) => setState(() {
                    useNvhTimes = value!;
                    parsed = false;
                    confirmed = false;
                  }),
            title: const Text('Điền giờ còn thiếu theo khung NVH trong ảnh'),
            subtitle: const Text(
              'Slot 1: 07:00–09:15 · 2: 09:30–11:45 · 3: 12:30–14:45 · 4: 15:00–17:15. Bấm Phân tích lại để áp dụng.',
            ),
          ),
          TextFormField(
            key: semesterKey,
            controller: semester,
            enabled: !busy,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Vui lòng nhập học kỳ trước khi phân tích.'
                : null,
            onChanged: (_) => setState(() {
              parsed = false;
              confirmed = false;
            }),
            decoration: const InputDecoration(
              labelText: 'Học kỳ cho lần phân tích tiếp theo (ví dụ FA26) *',
              hintText: 'FA26',
              prefixIcon: Icon(Icons.school_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : pick,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Chọn ảnh và chạy OCR'),
              ),
              OutlinedButton(
                onPressed: busy || raw.text.trim().isEmpty ? null : parse,
                child: const Text('Phân tích lại văn bản'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () {
                        if (!validateSemester()) return;
                        setState(() {
                          addRow({
                            'semester': semester.text.trim().toUpperCase(),
                          });
                          parsed = true;
                          confirmed = false;
                        });
                      },
                child: const Text('Thêm dòng'),
              ),
            ],
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 16),
          if (imagePath != null)
            SizedBox(
              height: 260,
              child: InteractiveViewer(
                child: Image.file(
                  File(imagePath!),
                  errorBuilder: (_, error, stack) =>
                      const Text('Không hiển thị được ảnh gốc.'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: raw,
            key: const ValueKey('ocrText'),
            enabled: !busy,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {
              confirmed = false;
              parsed = false;
            }),
            decoration: const InputDecoration(
              labelText:
                  'Văn bản OCR — có thể chỉnh sửa / dán từ công cụ OCR khác',
              hintText:
                  'FA26 PRM393 SE1848 Thu 2 Slot 1 07:30-09:00 Room AL-201',
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(message!),
            ),
          if (!parsed && rows.isNotEmpty)
            const Text(
              'Văn bản đã thay đổi. Bấm Phân tích lại trước khi xác nhận.',
            ),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Dòng ${i + 1}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Bỏ dòng này',
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    final removed = rows.removeAt(i);
                                    ids.removeAt(i);
                                    warnings.removeAt(i);
                                    for (final c in removed.values) {
                                      c.dispose();
                                    }
                                    confirmed = false;
                                  }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (warnings[i].isNotEmpty) Text(warnings[i].join('\n')),
                      Wrap(
                        spacing: 12,
                        runSpacing: 16,
                        children: [
                          for (final entry in scheduleLabels.entries.where(
                            (e) => e.key != 'subjectName',
                          ))
                            SizedBox(
                              width: 230,
                              child: TextField(
                                controller: rows[i][entry.key],
                                enabled: !busy,
                                onChanged: (_) =>
                                    setState(() => confirmed = false),
                                decoration: InputDecoration(
                                  labelText: entry.value,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (rows.isNotEmpty)
            CheckboxListTile(
              value: confirmed,
              onChanged: busy || !parsed
                  ? null
                  : (value) => setState(() => confirmed = value!),
              title: const Text(
                'Tôi đã đối chiếu và chỉnh sửa tất cả các dòng trước khi lưu.',
              ),
              subtitle: const Text(
                'OCR có thể nhận sai thứ, slot, giờ và mã lớp. Dữ liệu chưa được lưu khi chưa xác nhận.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    ),
  );
}

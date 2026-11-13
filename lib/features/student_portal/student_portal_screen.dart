import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../services/grade_excel_import.dart';
import '../../services/excel_export_service.dart';
import 'excel_grade_import_dialog.dart';
import '../../core/app_config.dart';
import '../../repositories/student_portal_repository.dart';
import 'leave_request_panel.dart';
import '../../grade_forecast/grade_forecast_page.dart';

class StudentPortalScreen extends StatefulWidget {
  final StudentPortalRepository repository;
  final bool leaveRequests;
  const StudentPortalScreen({
    super.key,
    required this.repository,
    this.leaveRequests = false,
  });
  @override
  State<StudentPortalScreen> createState() => _StudentPortalScreenState();
}

class _StudentPortalScreenState extends State<StudentPortalScreen> {
  List<PortalRow> classes = [];
  String? classId, error;
  bool busy = false, dirty = false;
  PortalRow? book;
  String? publishKey;
  int bookRevision = 0;
  List<PortalRow> get components =>
      (book?['components'] as List? ?? []).cast<PortalRow>();
  List<PortalRow> get students =>
      (book?['students'] as List? ?? []).cast<PortalRow>();
  @override
  void initState() {
    super.initState();
    loadClasses();
  }

  Future<void> loadClasses() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rows = await widget.repository.call('listClasses') as List;
      if (!mounted) return;
      classes = rows.map((r) => PortalRow.from(r as Map)).toList();
      classId = classes.isEmpty ? null : classes.first['classId'] as String;
      if (classId != null && !widget.leaveRequests) await loadBook();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadBook() async {
    final result = PortalRow.from(
      await widget.repository.call('getGradebook', {'classId': classId}) as Map,
    );
    result['components'] = (result['components'] as List)
        .map((r) => PortalRow.from(r as Map))
        .toList();
    result['students'] = (result['students'] as List)
        .map((r) => PortalRow.from(r as Map))
        .toList();
    if (mounted) {
      setState(() {
        book = result;
        dirty = false;
        publishKey = null;
        bookRevision++;
      });
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> discardChanges() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bỏ thay đổi chưa lưu?'),
            content: const Text('Bạn có thay đổi điểm chưa lưu.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Tiếp tục sửa'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Bỏ thay đổi'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> editComponent([PortalRow? old]) async {
    final name = TextEditingController(text: old?['name'] as String? ?? '');
    final max = TextEditingController(text: '${old?['maxScore'] ?? 10}');
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? 'Thêm cột điểm' : 'Sửa cột điểm'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Tên cột'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ||
                          components.any(
                            (c) =>
                                c['id'] != old?['id'] && c['name'] == v!.trim(),
                          )
                      ? 'Tên cột trống hoặc trùng'
                      : null,
                ),
                TextFormField(
                  controller: max,
                  decoration: const InputDecoration(labelText: 'Thang điểm'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || !n.isFinite || n <= 0 || n > 1000
                        ? 'Nhập số lớn hơn 0, tối đa 1000'
                        : null;
                  },
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
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        final value = <String, dynamic>{
          'id': old?['id'] ?? 'c_${const Uuid().v4().replaceAll('-', '')}',
          'name': name.text.trim(),
          'maxScore': double.parse(max.text),
        };
        if (old == null) {
          components.add(value);
        } else {
          components[components.indexOf(old)] = value;
        }
        dirty = true;
      });
    }
    Future.delayed(const Duration(seconds: 1), () {
      name.dispose();
      max.dispose();
    });
  }

  Future<void> importExcelGrades() async {
    if (busy || book == null || classId == null) return;
    await run(() async {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (selection == null || !mounted) return;
      final path = selection.files.single.path;
      if (path == null) {
        throw const AppException('Không đọc được đường dẫn file Excel.');
      }
      final sheets = await GradeExcelReader.read(path);
      if (!mounted) return;
      final imported = await showDialog<PortalRow>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExcelGradeImportDialog(
          sheets: sheets,
          target: classes.singleWhere((c) => c['classId'] == classId),
          current: book!,
          fileName: selection.files.single.name,
        ),
      );
      if (imported != null && mounted) {
        setState(() {
          book = imported;
          dirty = true;
          bookRevision++;
          publishKey = null;
        });
      }
    });
  }

  Future<void> exportExcelTemplate() async {
    if (busy || book == null || classId == null) return;
    await run(() async {
      final target = classes.singleWhere((c) => c['classId'] == classId);
      final columns = components.isEmpty
          ? <PortalRow>[
              {'id': 'new_grade', 'name': 'Điểm', 'maxScore': 10},
            ]
          : components;
      final bytes = ExcelExportService.generateXlsx(
        sheetName: 'Điểm',
        headers: [
          'Học kỳ',
          'Mã môn',
          'Mã lớp',
          'MSSV',
          'Họ tên',
          ...columns.map((c) => '${c['name']}'),
          'Nhận xét',
        ],
        rows: students
            .map(
              (s) => [
                '${target['semester']}',
                '${target['subjectCode']}',
                '${target['classCode']}',
                '${s['studentCode']}',
                '${s['fullName']}',
                ...columns.map((c) => '${(s['grades'] as Map)[c['id']] ?? ''}'),
                '${s['comment'] ?? ''}',
              ],
            )
            .toList(),
      );
      final name =
          'diem-${target['subjectCode']}-${target['classCode']}-${target['semester']}'
              .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu file mẫu nhập điểm',
        fileName: '$name.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu file mẫu Excel theo lớp đang chọn.'),
          ),
        );
      }
    });
  }

  Future<void> save() => run(() async {
    final rows = students.map((s) {
      final grades = <String, dynamic>{};
      for (final c in components) {
        final value = (s['grades'] as Map)[c['id']];
        final number = value == null || '$value'.trim().isEmpty
            ? null
            : double.tryParse('$value');
        if (value != null &&
            '$value'.trim().isNotEmpty &&
            (number == null ||
                !number.isFinite ||
                number < 0 ||
                number > (c['maxScore'] as num))) {
          throw AppException(
            'Điểm không hợp lệ: ${s['studentCode']} / ${c['name']}',
          );
        }
        grades[c['id'] as String] = number ?? '';
      }
      return {
        'studentId': s['studentId'],
        'grades': grades,
        'comment': s['comment'] ?? '',
      };
    }).toList();
    await widget.repository.call('saveGradebook', {
      'classId': classId,
      'version': book!['version'],
      'components': components,
      'students': rows,
    });
    await loadBook();
  });
  Future<void> publish() async {
    final blanks = students.fold<int>(
      0,
      (sum, s) =>
          sum +
          components.where((c) {
            final v = (s['grades'] as Map)[c['id']];
            return v == null || v == '';
          }).length,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xem trước công bố điểm'),
        content: Text(
          'Công bố cho ${students.length} sinh viên, ${components.length} cột điểm.\n${components.map((c) => c['name']).join(', ')}\nCó $blanks ô chưa nhập điểm. Nhận xét cũng được công bố.\nSinh viên sẽ xem bản này cho đến khi bạn công bố lại hoặc thu hồi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Công bố điểm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await run(() async {
      publishKey ??= const Uuid().v4();
      await widget.repository.call('publishGrades', {
        'classId': classId,
        'version': book!['version'],
        'requestKey': publishKey,
        'studentIds': students.map((s) => s['studentId']).toList(),
      });
      await loadBook();
    });
  }

  Future<void> revoke() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thu hồi điểm đã công bố?'),
        content: const Text(
          'Sinh viên sẽ không đọc được bản này từ lần tải tiếp theo. Lịch sử công bố vẫn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await run(() async {
        await widget.repository.call('revokeGrades', {
          'classId': classId,
          'version': book!['version'],
        });
        await loadBook();
      });
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.leaveRequests
              ? 'Quản lý đơn xin nghỉ'
              : 'Quản lý và công bố điểm',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (widget.repository is DemoStudentPortalRepository)
          const Text('DEMO: dữ liệu mẫu trong bộ nhớ, không công bố lên web.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: classId,
              hint: const Text('Chọn lớp'),
              items: classes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c['classId'] as String,
                      child: Text(
                        '${c['semester']} · ${c['subjectCode']} · ${c['classCode']}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) async {
                      if (!await discardChanges() || !mounted) return;
                      setState(() {
                        classId = v;
                        book = null;
                      });
                      if (!widget.leaveRequests) await run(loadBook);
                    },
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!await discardChanges() || !mounted) return;
                      await run(() async {
                        if (classId == null) {
                          await loadClasses();
                        } else if (!widget.leaveRequests) {
                          await loadBook();
                        }
                      });
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Tải lại'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!busy && classes.isEmpty)
          const Text(
            'Chưa có lớp. Nhập danh sách sinh viên tại mục Lớp học trước.',
          ),
        if (classId != null && widget.leaveRequests)
          LeaveRequestPanel(
            key: ValueKey(classId),
            repository: widget.repository,
            classId: classId!,
          ),
        if (!widget.leaveRequests && book != null) ...[
          Text(
            '${book!['activePublicationId'] == '' ? 'Chưa có điểm đang công bố' : 'Có bản điểm đang công bố'} · Phiên bản ${book!['version']}${dirty ? ' · Có thay đổi chưa lưu' : ''}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy || components.length >= 30
                    ? null
                    : () => editComponent(),
                child: const Text('Thêm cột điểm'),
              ),
              FilledButton(
                onPressed: busy || !dirty || components.isEmpty ? null : save,
                child: const Text('Lưu bản nháp'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : importExcelGrades,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Nhập điểm từ Excel'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : exportExcelTemplate,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Tải file mẫu Excel'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        final target = classes.singleWhere(
                          (c) => c['classId'] == classId,
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GradeForecastPage(
                              contextLabel:
                                  '${target['semester']} · ${target['subjectCode']} · ${target['classCode']}',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Tính điểm FE/PE'),
              ),
              FilledButton.icon(
                onPressed:
                    busy || dirty || components.isEmpty || students.isEmpty
                    ? null
                    : publish,
                icon: const Icon(Icons.publish),
                label: const Text('Xem trước / Công bố'),
              ),
              TextButton(
                onPressed: busy || dirty || book!['activePublicationId'] == ''
                    ? null
                    : revoke,
                child: const Text('Thu hồi công bố'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: components
                .map(
                  (c) => InputChip(
                    label: Text('${c['name']} / ${c['maxScore']}'),
                    onPressed: busy ? null : () => editComponent(c),
                    onDeleted: busy
                        ? null
                        : () => setState(() {
                            components.remove(c);
                            dirty = true;
                          }),
                  ),
                )
                .toList(),
          ),
          const Text(
            'Lưu bản nháp trước khi công bố. Sửa nháp không thay đổi bản sinh viên đang xem.',
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('MSSV')),
                const DataColumn(label: Text('Họ tên')),
                ...components.map(
                  (c) => DataColumn(
                    label: Text('${c['name']} / ${c['maxScore']}'),
                  ),
                ),
                const DataColumn(label: Text('Nhận xét')),
              ],
              rows: students
                  .map(
                    (s) => DataRow(
                      cells: [
                        DataCell(Text('${s['studentCode']}')),
                        DataCell(Text('${s['fullName']}')),
                        ...components.map(
                          (c) => DataCell(
                            SizedBox(
                              width: 90,
                              child: TextFormField(
                                key: ValueKey(
                                  '$bookRevision/${s['studentId']}/${c['id']}',
                                ),
                                enabled: !busy,
                                initialValue:
                                    '${(s['grades'] as Map)[c['id']] ?? ''}',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (v) => setState(() {
                                  (s['grades'] as Map)[c['id']] = v;
                                  dirty = true;
                                }),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 250,
                            child: TextFormField(
                              key: ValueKey(
                                '$bookRevision/${s['studentId']}/comment',
                              ),
                              enabled: !busy,
                              initialValue: '${s['comment'] ?? ''}',
                              maxLength: 1000,
                              decoration: const InputDecoration(
                                counterText: '',
                              ),
                              onChanged: (v) => setState(() {
                                s['comment'] = v;
                                dirty = true;
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    ),
  );
}

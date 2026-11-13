import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/app_config.dart';
import '../../repositories/student_portal_repository.dart';
import '../../services/grade_excel_import.dart';

class _ColumnChoice {
  final int column;
  final String newId;
  final String matchStatus;
  String name, max = '10';
  String? targetId;
  bool selected;
  _ColumnChoice(
    this.column,
    this.name,
    this.selected,
    this.targetId,
    this.matchStatus,
  ) : newId = 'c_${const Uuid().v4().replaceAll('-', '')}';
}

class ExcelGradeImportDialog extends StatefulWidget {
  final List<GradeExcelSheet> sheets;
  final PortalRow target, current;
  final String fileName;
  const ExcelGradeImportDialog({
    super.key,
    required this.sheets,
    required this.target,
    required this.current,
    required this.fileName,
  });
  @override
  State<ExcelGradeImportDialog> createState() => _ExcelGradeImportDialogState();
}

class _ExcelGradeImportDialogState extends State<ExcelGradeImportDialog> {
  int sheetIndex = 0,
      headerIndex = 0,
      rollColumn = 0,
      commentColumn = -1,
      revision = 0;
  bool clearBlanks = false, cachedFormulas = false;
  final lastRow = TextEditingController();
  List<_ColumnChoice> choices = [];
  ExcelGradePreview? preview;
  String? error;
  GradeExcelSheet get sheet => widget.sheets[sheetIndex];
  GradeExcelRow get header => sheet.rows[headerIndex];
  List<PortalRow> get components =>
      (widget.current['components'] as List).cast<PortalRow>();
  String get classLabel =>
      '${widget.target['semester']} · ${widget.target['subjectCode']} · ${widget.target['classCode']}';
  @override
  void initState() {
    super.initState();
    bool hasStudentCodes(GradeExcelSheet sheet) => sheet
        .rows[sheet.headerIndex]
        .cells
        .any((cell) => gradeRollHeaders.contains(gradeHeader(cell.text)));
    final template = widget.sheets.indexWhere(
      (sheet) => gradeHeader(sheet.name) == 'diem' && hasStudentCodes(sheet),
    );
    final detected = template >= 0
        ? template
        : widget.sheets.indexWhere(hasStudentCodes);
    if (detected >= 0) sheetIndex = detected;
    resetSheet();
  }

  @override
  void dispose() {
    lastRow.dispose();
    super.dispose();
  }

  void resetSheet() {
    headerIndex = sheet.headerIndex;
    lastRow.text = '${sheet.rows.last.number}';
    resetHeader();
  }

  void resetHeader() {
    rollColumn = header.cells.indexWhere(
      (c) => gradeRollHeaders.contains(gradeHeader(c.text)),
    );
    if (rollColumn >= 0 &&
        header.cells.lastIndexWhere(
              (c) => gradeRollHeaders.contains(gradeHeader(c.text)),
            ) !=
            rollColumn) {
      rollColumn = -1;
    }
    commentColumn = -1;
    resetMappings();
  }

  void resetMappings() {
    choices = [];
    const ignored = {
      'hoten',
      'hovaten',
      'fullname',
      'studentname',
      'name',
      'stt',
      'no',
      'email',
      'schoolemail',
      'nhanxet',
      'comment',
      'comments',
      'note',
    };
    final headerKeys = header.cells.map((c) => gradeHeader(c.text)).toList();
    for (var i = 0; i < header.cells.length; i++) {
      final name = header.cell(i).text, key = headerKeys[i];
      if (i == rollColumn ||
          key.isEmpty ||
          gradeRollHeaders.contains(key) ||
          ignored.contains(key) ||
          gradeMetadataHeaders.containsKey(key)) {
        continue;
      }
      final matching = components
          .where((c) => gradeHeader('${c['name']}') == key)
          .toList();
      final duplicatedHeader =
          headerKeys.indexOf(key) != headerKeys.lastIndexOf(key);
      final existing = !duplicatedHeader && matching.length == 1
          ? matching.single
          : null;
      final status = switch ((duplicatedHeader, matching.length)) {
        (true, _) => 'Tên cột lặp trong Excel. Kiểm tra và chọn cột đích.',
        (false, 0) => 'Chưa tìm thấy cột cùng tên trong bảng điểm.',
        (false, 1) => 'Đã ghép với cột ${existing!['name']} trong bảng điểm.',
        _ => 'Có nhiều cột cùng tên trong bảng điểm. Hãy chọn cột đích.',
      };
      choices.add(
        _ColumnChoice(
          i,
          name,
          existing != null,
          existing?['id'] as String?,
          status,
        ),
      );
    }
    revision++;
    check();
  }

  void check() {
    preview = null;
    error = null;
    if (rollColumn < 0) {
      error = 'Chọn cột MSSV trong phần tùy chọn để đối chiếu danh sách lớp.';
      return;
    }
    if (!choices.any((c) => c.selected)) return;
    try {
      final mappings = <GradeColumnMapping>[];
      for (final c in choices.where((c) => c.selected)) {
        final old = components.where((p) => p['id'] == c.targetId).firstOrNull;
        final max =
            old?['maxScore'] as num? ??
            num.tryParse(c.max.replaceAll(',', '.'));
        if (max == null) {
          throw const AppException('Nhập thang điểm hợp lệ cho cột mới.');
        }
        mappings.add(
          GradeColumnMapping(
            column: c.column,
            id: old?['id'] ?? c.newId,
            name: old?['name'] ?? c.name,
            maxScore: max,
          ),
        );
      }
      final end = int.tryParse(lastRow.text.trim());
      if (end == null) {
        throw const AppException('Nhập số dòng kết thúc hợp lệ.');
      }
      final result = prepareExcelGradeImport(
        sheet: sheet,
        headerIndex: headerIndex,
        rollColumn: rollColumn,
        mappings: mappings,
        target: widget.target,
        current: widget.current,
        endRow: end,
        commentColumn: commentColumn < 0 ? null : commentColumn,
        clearBlanks: clearBlanks,
        allowCachedFormulas: cachedFormulas,
      );
      preview = result;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Chưa kiểm tra được file. Kiểm tra lại sheet và cách ghép cột.';
    }
  }

  String get applyLabel {
    final result = preview;
    if (result == null || !result.canApply) return 'Đưa vào bảng nháp';
    final hasOverwrite = result.changes.any(
      (change) => change['old'] != null && change['old'] != '',
    );
    if (result.newComponents > 0) {
      return hasOverwrite ? 'Xác nhận ghi đè và thêm cột' : 'Xác nhận thêm cột';
    }
    return hasOverwrite
        ? 'Xác nhận ghi đè vào bản nháp'
        : 'Xác nhận nhập vào bản nháp';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nhập điểm từ Excel'),
    content: SizedBox(
      width: 720,
      height: MediaQuery.sizeOf(context).height * .65,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(classLabel, style: Theme.of(context).textTheme.titleMedium),
            Text(widget.fileName),
            const Text('Điểm được ghép theo MSSV và đưa vào bảng nháp.'),
            const SizedBox(height: 12),
            if (preview != null)
              Text(
                '${preview!.matchedStudents}/${(widget.current['students'] as List).length} sinh viên khớp · ${preview!.changes.length} ô thay đổi · ${preview!.newComponents} cột mới',
                style: Theme.of(context).textTheme.titleSmall,
              )
            else if (error == null)
              const Text('Chọn cách nhập cho ít nhất một cột bên dưới.'),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (preview?.errors.isNotEmpty == true) ...[
              Text(
                preview!.errors.first,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (preview!.errors.length > 1)
                ExpansionTile(
                  title: const Text('Xem các lỗi khác'),
                  children: [
                    for (final issue in preview!.errors.skip(1))
                      ListTile(dense: true, title: Text(issue)),
                  ],
                ),
            ],
            if (preview?.errors.isEmpty == true && !preview!.canApply)
              const Text('Không có thay đổi điểm để nhập.'),
            if (preview?.errors.isEmpty == true && preview!.changes.isNotEmpty)
              ExpansionTile(
                initiallyExpanded: true,
                title: const Text('Điểm sẽ thay đổi'),
                children: [
                  SizedBox(
                    height: preview!.changes.length > 5 ? 180 : null,
                    child: ListView.builder(
                      shrinkWrap: true,
                      primary: false,
                      itemCount: preview!.changes.length,
                      itemBuilder: (context, index) {
                        final change = preview!.changes[index];
                        final old = change['old'] == ''
                            ? 'Trống'
                            : change['old'];
                        final next = change['new'] == ''
                            ? 'Trống'
                            : change['new'];
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${change['studentCode']} · ${change['column']}',
                          ),
                          trailing: Text(
                            '$old → $next',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            const Divider(),
            for (final c in choices) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('target/$revision/${c.column}'),
                initialValue: !c.selected
                    ? null
                    : c.targetId == null
                    ? ''
                    : 'id/${c.targetId}',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: header.cell(c.column).text,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  helperText: c.selected ? null : c.matchStatus,
                ),
                hint: const Text('Bỏ qua cột này'),
                items: [
                  const DropdownMenuItem(
                    value: 'skip',
                    child: Text('Bỏ qua cột này'),
                  ),
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Thêm cột điểm mới'),
                  ),
                  ...components.map(
                    (p) => DropdownMenuItem(
                      value: 'id/${p['id']}',
                      child: Text('Ghép với ${p['name']} / ${p['maxScore']}'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  c.selected = value != 'skip';
                  c.targetId = value!.startsWith('id/')
                      ? value.substring(3)
                      : null;
                  check();
                }),
              ),
              if (c.selected && c.targetId == null) ...[
                TextFormField(
                  key: ValueKey('name/$revision/${c.column}'),
                  initialValue: c.name,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Tên cột mới'),
                  onChanged: (v) => setState(() {
                    c.name = v;
                    check();
                  }),
                ),
                TextFormField(
                  key: ValueKey('max/$revision/${c.column}'),
                  initialValue: c.max,
                  decoration: const InputDecoration(
                    labelText: 'Thang điểm cột mới',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) => setState(() {
                    c.max = v;
                    check();
                  }),
                ),
              ],
              const SizedBox(height: 8),
            ],
            ExpansionTile(
              title: const Text('Tùy chọn đọc Excel'),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: sheetIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sheet dữ liệu'),
                  items: List.generate(
                    widget.sheets.length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(widget.sheets[i].name),
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    sheetIndex = v!;
                    resetSheet();
                  }),
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('header/$sheetIndex'),
                  initialValue: headerIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Dòng tiêu đề'),
                  items: List.generate(
                    sheet.rows.take(50).length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        'Dòng ${sheet.rows[i].number}: ${sheet.rows[i].cells.take(4).map((c) => c.text).join(' · ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    headerIndex = v!;
                    resetHeader();
                  }),
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('roll/$sheetIndex/$headerIndex'),
                  initialValue: rollColumn < 0 ? null : rollColumn,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cột MSSV'),
                  items: List.generate(
                    header.cells.length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text('${i + 1}. ${header.cell(i).text}'),
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    rollColumn = v!;
                    resetMappings();
                  }),
                ),
                TextField(
                  controller: lastRow,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dòng dữ liệu cuối',
                    helperText:
                        'Giới hạn trước các dòng tổng kết/ghi chú cuối file.',
                  ),
                  onChanged: (_) => setState(check),
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('comment/$revision'),
                  initialValue: commentColumn,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nhận xét'),
                  items: [
                    const DropdownMenuItem(
                      value: -1,
                      child: Text('Giữ nhận xét hiện tại'),
                    ),
                    ...List.generate(
                      header.cells.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text('${i + 1}. ${header.cell(i).text}'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    commentColumn = v!;
                    check();
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Xóa điểm cũ khi ô Excel trống'),
                  subtitle: const Text(
                    'Mặc định giữ điểm cũ và sinh viên không có trong file.',
                  ),
                  value: clearBlanks,
                  onChanged: (v) => setState(() {
                    clearBlanks = v;
                    check();
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Dùng kết quả công thức đã lưu trong Excel',
                  ),
                  subtitle: const Text(
                    'App không tính lại công thức. Mở Excel, tính lại và lưu file trước khi bật tùy chọn này.',
                  ),
                  value: cachedFormulas,
                  onChanged: (v) => setState(() {
                    cachedFormulas = v!;
                    check();
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: preview?.canApply == true
            ? () => Navigator.pop(context, preview!.book)
            : null,
        child: Text(applyLabel),
      ),
    ],
  );
}

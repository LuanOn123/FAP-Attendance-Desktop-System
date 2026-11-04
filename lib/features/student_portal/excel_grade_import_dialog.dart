import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/app_config.dart';
import '../../repositories/student_portal_repository.dart';
import '../../services/grade_excel_import.dart';

class _ColumnChoice {
  final int column;
  final String newId;
  String name, max = '10';
  String? targetId;
  bool selected;
  _ColumnChoice(this.column, this.name, this.selected, this.targetId)
    : newId = 'c_${const Uuid().v4().replaceAll('-', '')}';
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
  bool clearBlanks = false, cachedFormulas = false, confirmedClass = false;
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
    resetSheet();
  }

  @override
  void dispose() {
    lastRow.dispose();
    super.dispose();
  }

  void invalidate() {
    preview = null;
    error = null;
    confirmedClass = false;
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
    if (rollColumn < 0) rollColumn = 0;
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
    for (var i = 0; i < header.cells.length; i++) {
      final name = header.cell(i).text, key = gradeHeader(name);
      if (i == rollColumn ||
          name.isEmpty ||
          ignored.contains(key) ||
          gradeMetadataHeaders.containsKey(key)) {
        continue;
      }
      final existing = components
          .where((c) => gradeHeader('${c['name']}') == key)
          .firstOrNull;
      final recognized = RegExp(
        r'^(lab|quiz|assignment|asm|pt|pe|fe|final|midterm|practical|project|diem|score|grade)',
      ).hasMatch(key);
      choices.add(
        _ColumnChoice(
          i,
          name,
          existing != null || recognized,
          existing?['id'] as String?,
        ),
      );
    }
    revision++;
    invalidate();
  }

  void check() {
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
      setState(() {
        preview = result;
        error = null;
        confirmedClass = false;
      });
    } catch (e) {
      setState(() {
        preview = null;
        error = e is AppException
            ? e.message
            : 'Chưa kiểm tra được file. Kiểm tra lại sheet và cách ghép cột.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nhập điểm từ Excel'),
    content: SizedBox(
      width: 1000,
      height: MediaQuery.sizeOf(context).height * .7,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(classLabel, style: Theme.of(context).textTheme.titleMedium),
            Text(widget.fileName),
            const Text(
              'Ghép theo MSSV. Điểm nhập chỉ vào bảng nháp; lưu và công bố là các bước riêng.',
            ),
            const SizedBox(height: 12),
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
              initialValue: rollColumn,
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
              onChanged: (_) => setState(invalidate),
            ),
            const SizedBox(height: 16),
            Text(
              'Cột điểm cần nhập',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final c in choices)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Cột ${c.column + 1}: ${header.cell(c.column).text}',
                        ),
                        value: c.selected,
                        onChanged: (v) => setState(() {
                          c.selected = v!;
                          invalidate();
                        }),
                      ),
                      if (c.selected) ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey('target/$revision/${c.column}'),
                          initialValue: c.targetId ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Đưa vào cột điểm',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Tạo cột mới'),
                            ),
                            ...components.map(
                              (p) => DropdownMenuItem(
                                value: p['id'] as String,
                                child: Text('${p['name']} / ${p['maxScore']}'),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            c.targetId = v!.isEmpty ? null : v;
                            invalidate();
                          }),
                        ),
                        if (c.targetId == null) ...[
                          TextFormField(
                            key: ValueKey('name/$revision/${c.column}'),
                            initialValue: c.name,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: 'Tên cột mới',
                            ),
                            onChanged: (v) => setState(() {
                              c.name = v;
                              invalidate();
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
                              invalidate();
                            }),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
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
                invalidate();
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
                invalidate();
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dùng kết quả công thức đã lưu trong Excel'),
              subtitle: const Text(
                'App không tính lại công thức. Mở Excel, tính lại và lưu file trước khi bật tùy chọn này.',
              ),
              value: cachedFormulas,
              onChanged: (v) => setState(() {
                cachedFormulas = v!;
                invalidate();
              }),
            ),
            OutlinedButton(
              onPressed: check,
              child: const Text('Kiểm tra / Xem trước'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (preview != null) ...[
              const Divider(),
              Text(
                '${preview!.matchedStudents}/${(widget.current['students'] as List).length} sinh viên khớp · ${preview!.changes.length} ô thay đổi · ${preview!.newComponents} cột mới',
              ),
              Text(
                'Giữ nguyên ${preview!.untouchedStudents} sinh viên ngoài file · ${preview!.blankCellsKept} ô trống giữ điểm cũ · ${preview!.cachedFormulas} kết quả công thức đã lưu',
              ),
              if (preview!.errors.isNotEmpty) ...[
                Text(
                  'Cần sửa lỗi trước khi nhập (hiển thị tối đa 100 lỗi):',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                for (final issue in preview!.errors) Text(issue),
              ],
              if (preview!.errors.isEmpty && !preview!.canApply)
                const Text('Không có thay đổi điểm để nhập.'),
              if (preview!.changes.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('MSSV')),
                      DataColumn(label: Text('Cột')),
                      DataColumn(label: Text('Điểm cũ')),
                      DataColumn(label: Text('Điểm mới')),
                    ],
                    rows: preview!.changes
                        .take(100)
                        .map(
                          (r) => DataRow(
                            cells: [
                              DataCell(Text('${r['studentCode']}')),
                              DataCell(Text('${r['column']}')),
                              DataCell(Text('${r['old']}')),
                              DataCell(Text('${r['new']}')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (preview!.changes.length > 100)
                const Text('Đang hiển thị 100 thay đổi đầu tiên.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Tôi xác nhận file điểm thuộc $classLabel'),
                value: confirmedClass,
                onChanged: preview!.canApply
                    ? (v) => setState(() => confirmedClass = v!)
                    : null,
              ),
            ],
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
        onPressed: preview?.canApply == true && confirmedClass
            ? () => Navigator.pop(context, preview!.book)
            : null,
        child: const Text('Đưa vào bảng nháp'),
      ),
    ],
  );
}

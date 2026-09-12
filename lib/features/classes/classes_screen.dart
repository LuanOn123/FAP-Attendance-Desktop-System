import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../models/class_model.dart';
import '../../models/roster.dart';
import '../../models/schedule.dart';
import '../../repositories/schedule_repository.dart';
import '../../services/markbook_reader.dart';

class ClassesScreen extends StatefulWidget {
  final List<ClassModel> classes;
  final List<Schedule> schedules;
  final String lecturerId;
  final ScheduleRepository repository;
  final Future<void> Function() onChanged;
  const ClassesScreen({
    super.key,
    required this.classes,
    required this.schedules,
    required this.lecturerId,
    required this.repository,
    required this.onChanged,
  });
  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  String? selectedKey, error;
  List<RosterStudent> students = [];
  bool busy = false;
  int generation = 0;
  List<ClassTarget> get targets =>
      classTargets(widget.classes, widget.schedules, widget.lecturerId);
  Future<void> select(ClassTarget target) async {
    final request = ++generation;
    setState(() {
      selectedKey = target.key;
      busy = true;
      error = null;
      students = [];
    });
    try {
      final data = await widget.repository.getRoster(target);
      if (mounted && request == generation) setState(() => students = data);
    } catch (e) {
      if (mounted && request == generation) {
        setState(
          () => error = e is AppException
              ? e.message
              : 'Không tải được danh sách sinh viên.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    final result = await Navigator.push<ClassTarget>(
      context,
      MaterialPageRoute(
        builder: (_) => RosterImportScreen(
          targets: targets,
          repository: widget.repository,
          initialKey: selectedKey,
        ),
      ),
    );
    if (result != null && mounted) {
      await widget.onChanged();
      if (mounted) await select(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = targets;
    final selected = options.where((t) => t.key == selectedKey).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          'Lớp học & sinh viên',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Danh sách lớp từ lịch dạy. Nhập markbook để thêm sinh viên vào đúng lớp và môn học.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: options.isEmpty ? null : import,
              icon: const Icon(Icons.upload_file),
              label: const Text('Nhập sinh viên từ Excel / ODS'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await widget.onChanged();
                if (mounted && selected != null) await select(selected);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Tải lại'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (options.isEmpty)
          const Text('Chưa có lớp. Hãy nhập lịch dạy có mã lớp trước.'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in options)
              ChoiceChip(
                label: Text(t.label),
                selected: selectedKey == t.key,
                onSelected: (_) => select(t),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (selected == null && options.isNotEmpty)
          const Text('Chọn một lớp để xem sinh viên hoặc nhập danh sách mới.'),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          SelectableText(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (selected != null && !busy && error == null) ...[
          Text(
            '${selected.label} · ${students.length} sinh viên',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (students.isEmpty)
            const Text(
              'Lớp chưa có sinh viên. Chọn Nhập sinh viên từ Excel / ODS để thêm danh sách.',
            ),
          if (students.isNotEmpty) StudentTable(students: students),
        ],
      ],
    );
  }
}

class RosterImportScreen extends StatefulWidget {
  final List<ClassTarget> targets;
  final ScheduleRepository repository;
  final String? initialKey;
  final Future<Markbook?> Function()? pickBook;
  const RosterImportScreen({
    super.key,
    required this.targets,
    required this.repository,
    this.initialKey,
    this.pickBook,
  });
  @override
  State<RosterImportScreen> createState() => _RosterImportScreenState();
}

class _RosterImportScreenState extends State<RosterImportScreen> {
  Markbook? book;
  int sheetIndex = 0;
  String? classCode, semester, targetKey, error;
  bool busy = false;
  MarkbookSheet? get sheet => book?.sheets[sheetIndex];
  List<RosterStudent> get rows =>
      sheet?.students.where((s) => s.classCode == classCode).toList() ?? [];
  List<ClassTarget> get candidates => widget.targets
      .where((t) => t.classCode == classCode && t.semester == semester)
      .toList();
  ClassTarget? get target =>
      candidates.where((t) => t.key == targetKey).firstOrNull;

  void match() {
    final exact = candidates
        .where((t) => t.subjectCode == sheet?.subjectHint)
        .toList();
    // A conflicting sheet subject must be resolved explicitly, even with one class candidate.
    targetKey = exact.length == 1
        ? exact.single.key
        : (sheet?.subjectHint.isEmpty == true && candidates.length == 1
              ? candidates.single.key
              : null);
  }

  void selectSheet(int i) {
    sheetIndex = i;
    classCode = sheet?.students.firstOrNull?.classCode;
    match();
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Markbook? loaded;
      if (widget.pickBook != null) {
        loaded = await widget.pickBook!();
      } else {
        final file = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx', 'ods'],
        );
        if (file?.files.single.path != null) {
          loaded = await MarkbookReader.read(file!.files.single.path!);
        }
      }
      if (!mounted || loaded == null) return;
      setState(() {
        book = loaded;
        final semesters = widget.targets.map((t) => t.semester).toSet();
        semester = semesters.contains(loaded!.semesterHint)
            ? loaded.semesterHint
            : semesters.length == 1
            ? semesters.single
            : null;
        final initial = widget.targets
            .where((t) => t.key == widget.initialKey)
            .firstOrNull;
        var index = initial == null
            ? -1
            : loaded.sheets.indexWhere(
                (s) =>
                    s.subjectHint == initial.subjectCode &&
                    s.students.any((r) => r.classCode == initial.classCode),
              );
        if (index < 0 && initial != null) {
          index = loaded.sheets.indexWhere(
            (s) => s.students.any((r) => r.classCode == initial.classCode),
          );
        }
        if (index < 0) {
          index = loaded.sheets.indexWhere(
            (s) => s.students.isNotEmpty && s.errors.isEmpty,
          );
        }
        selectSheet(index < 0 ? 0 : index);
        if (initial != null &&
            sheet!.students.any((s) => s.classCode == initial.classCode)) {
          classCode = initial.classCode;
          match();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AppException ? e.message : 'Không đọc được file.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final destination = target;
    if (busy ||
        destination == null ||
        rows.isEmpty ||
        sheet!.errors.isNotEmpty) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.importRoster(destination, rows);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, destination);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm ${result.added} sinh viên vào ${destination.label}; ${result.existing} đã có, không thêm trùng.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AppException
              ? e.message
              : 'Không nhập được danh sách. Dữ liệu duyệt vẫn còn, hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        target != null &&
        rows.isNotEmpty &&
        sheet!.errors.isEmpty &&
        rows.length <= 1000;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nhập danh sách sinh viên'),
          actions: [
            FilledButton.icon(
              onPressed: !busy && valid ? save : null,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text('Thêm ${rows.length} sinh viên vào lớp'),
            ),
            const SizedBox(width: 20),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text(
              'Chọn file → Đối chiếu lớp → Thêm sinh viên',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Hỗ trợ .xlsx và .ods có cột Class, RollNumber, FullName; Email là tùy chọn. Chỉ nhập danh sách sinh viên, không nhập điểm. File .xls cần lưu lại thành .xlsx.',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : pick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Chọn file Excel / ODS'),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SelectableText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (book != null) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 300,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(book),
                      initialValue: sheetIndex,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sheet trong file',
                      ),
                      items: [
                        for (var i = 0; i < book!.sheets.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(book!.sheets[i].name),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (i) => setState(() => selectSheet(i!)),
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('semester-${book.hashCode}'),
                      initialValue: semester,
                      decoration: const InputDecoration(labelText: 'Học kỳ'),
                      items: widget.targets
                          .map((t) => t.semester)
                          .toSet()
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (s) => setState(() {
                              semester = s;
                              match();
                            }),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('class-$sheetIndex-${book.hashCode}'),
                      initialValue: classCode,
                      decoration: const InputDecoration(
                        labelText: 'Mã lớp trong file',
                      ),
                      items: sheet!.students
                          .map((s) => s.classCode)
                          .toSet()
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (c) => setState(() {
                              classCode = c;
                              match();
                            }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'target-$targetKey-$sheetIndex-$classCode-$semester',
                ),
                initialValue: targetKey,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Lớp / môn đích trong lịch đã nhập',
                ),
                items: candidates
                    .map(
                      (t) =>
                          DropdownMenuItem(value: t.key, child: Text(t.label)),
                    )
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => targetKey = v),
              ),
              const SizedBox(height: 12),
              if (candidates.isEmpty)
                const Text(
                  'Chưa có lớp khớp mã lớp và học kỳ. Hãy kiểm tra học kỳ hoặc thêm lịch dạy cho lớp này trước.',
                ),
              if (sheet!.subjectHint.isNotEmpty)
                Text('Mã môn trong tên sheet: ${sheet!.subjectHint}'),
              if (target == null && candidates.isNotEmpty)
                const Text(
                  'Chưa xác định được môn đích. Chọn lớp / môn ở trên sau khi đối chiếu tên sheet.',
                ),
              if (target != null &&
                  sheet!.subjectHint.isNotEmpty &&
                  target!.subjectCode != sheet!.subjectHint)
                Text(
                  'Bạn đã chọn ${target!.subjectCode}, khác mã ${sheet!.subjectHint} trong tên sheet. Kiểm tra trước khi thêm sinh viên.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (target != null)
                Text(
                  'Sẽ thêm vào ${target!.label}. Sinh viên đã có được giữ nguyên và không thêm trùng.',
                ),
              if (sheet!.duplicates > 0)
                Text(
                  'Đã gộp ${sheet!.duplicates} dòng lặp giống nhau trong sheet.',
                ),
              if (rows.length > 1000)
                const Text(
                  'Quá 1.000 sinh viên. Hãy tách danh sách trước khi nhập.',
                ),
              for (final e in sheet!.errors)
                Text(
                  e,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 20),
              Text(
                '${rows.length} sinh viên thuộc ${classCode ?? 'lớp chưa xác định'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (rows.isNotEmpty) StudentTable(students: rows),
            ],
          ],
        ),
      ),
    );
  }
}

class StudentTable extends StatefulWidget {
  final List<RosterStudent> students;
  const StudentTable({super.key, required this.students});
  @override
  State<StudentTable> createState() => _StudentTableState();
}

class _StudentTableState extends State<StudentTable> {
  late _StudentSource source;
  @override
  void initState() {
    super.initState();
    source = _StudentSource(widget.students);
  }

  @override
  void didUpdateWidget(StudentTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.students != widget.students) {
      source.dispose();
      source = _StudentSource(widget.students);
    }
  }

  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PaginatedDataTable(
    key: ValueKey(widget.students),
    showCheckboxColumn: false,
    rowsPerPage: 10,
    columns: const [
      DataColumn(label: Text('STT')),
      DataColumn(label: Text('Mã sinh viên')),
      DataColumn(label: Text('Họ và tên')),
      DataColumn(label: Text('Email')),
      DataColumn(label: Text('Mã lớp')),
    ],
    source: source,
  );
}

class _StudentSource extends DataTableSource {
  final List<RosterStudent> students;
  _StudentSource(this.students);
  @override
  DataRow? getRow(int index) {
    if (index >= students.length) return null;
    final s = students[index];
    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text('${index + 1}')),
        DataCell(SelectableText(s.studentCode)),
        DataCell(SelectableText(s.fullName)),
        DataCell(SelectableText(s.email)),
        DataCell(Text(s.classCode)),
      ],
    );
  }

  @override
  int get rowCount => students.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}

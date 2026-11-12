import 'package:flutter/material.dart';
import '../repositories/student_portal_repository.dart';
import 'study_groups.dart';

class GroupScreen extends StatefulWidget {
  final StudentPortalRepository repository;
  const GroupScreen({super.key, required this.repository});
  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  List<Map<String, dynamic>>? classes;
  String? selected, error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await widget.repository.call('listClasses');
      if (mounted) {
        setState(() {
          classes = (rows as List)
              .map((c) => Map<String, dynamic>.from(c as Map))
              .toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(
            labelText: 'Lớp học - nhóm học tập',
          ),
          items: (classes ?? [])
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c['classId'],
                  child: Text(
                    '${c['subjectCode']} · ${c['classCode']} · ${c['semester']}',
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => selected = v),
        ),
      ),
      if (error != null)
        TextButton(onPressed: load, child: Text('$error · Thử lại')),
      if (classes == null && error == null) const LinearProgressIndicator(),
      if (selected != null)
        Expanded(
          child: StudyGroups(
            key: ValueKey(selected),
            classId: selected!,
            startInChat: true,
            call: (method, data) => widget.repository.call(method, data),
          ),
        ),
    ],
  );
}

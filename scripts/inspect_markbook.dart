import 'dart:io';
import 'package:fap_attendance/services/markbook_reader.dart';

Future<void> main(List<String> args) async {
  final book = await MarkbookReader.read(args.single);
  stdout.writeln('Semester: ${book.semesterHint}');
  for (final s in book.sheets) {
    stdout.writeln(
      '${s.name}: ${s.students.length} students, ${s.duplicates} duplicates, ${s.errors.length} errors; classes: ${s.students.map((s) => s.classCode).toSet().join(', ')}',
    );
    for (final e in s.errors) {
      stdout.writeln(e);
    }
  }
}

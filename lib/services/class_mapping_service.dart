import '../models/class_model.dart';
import '../models/schedule.dart';

class MappingResult {
  final List<ClassModel> matches;
  const MappingResult(this.matches);
  ClassModel? get mappedClass => matches.length == 1 ? matches.single : null;
  String get label => matches.isEmpty
      ? 'Chưa có lớp'
      : matches.length > 1
      ? 'Trùng khóa lớp — cần xử lý'
      : 'Đã ghép ${matches.single.classCode}';
}

class ClassMappingService {
  MappingResult map(Schedule schedule, List<ClassModel> classes) =>
      MappingResult(
        classes
            .where(
              (c) =>
                  c.key == schedule.key && c.lecturerId == schedule.lecturerId,
            )
            .toList(),
      );
}

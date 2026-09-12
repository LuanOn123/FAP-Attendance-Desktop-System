import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/schedule.dart';

class WeeklyTimetable extends StatelessWidget {
  final List<Schedule> schedules;
  final ValueChanged<Schedule> onSelect;
  final List<String>? subjectCodes;
  const WeeklyTimetable({
    super.key,
    required this.schedules,
    required this.onSelect,
    this.subjectCodes,
  });
  static const palette = [
    Color(0xFF126B5B),
    Color(0xFF355EC3),
    Color(0xFF8850A5),
    Color(0xFFAC5B24),
    Color(0xFF227B91),
  ];
  Color color(String subject) {
    final subjects = subjectCodes ?? (schedules.map((s) => s.subjectCode).toSet().toList()..sort());
    return palette[math.max(0, subjects.indexOf(subject)) % palette.length];
  }
  @override
  Widget build(BuildContext context) {
    final slots = schedules.map((s) => s.slot).toSet().toList()..sort();
    final subjects = schedules.map((s) => s.subjectCode).toSet().toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            for (final subject in subjects)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color(subject),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(subject),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(1170.0, constraints.maxWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Table(
                  columnWidths: const {0: FixedColumnWidth(72)},
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  border: TableBorder.all(
                    color: const Color(0xFFE0E6ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFEEF3F8)),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: Text(
                              'SLOT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        for (var day = 1; day <= 7; day++) dayHeader(day),
                      ],
                    ),
                    for (final slot in slots)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: Column(
                              children: [
                                const Text(
                                  'Slot',
                                  style: TextStyle(
                                    color: Color(0xFF748093),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '$slot',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (var day = 1; day <= 7; day++)
                            cell(context, day, slot),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Lịch lặp hằng tuần · Bấm vào buổi học để xem, sửa hoặc xóa. Cuộn ngang nếu màn hình nhỏ.',
          style: TextStyle(fontSize: 12, color: Color(0xFF657387)),
        ),
      ],
    );
  }

  Widget dayHeader(int day) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(
        day == 7 ? 'CHỦ NHẬT' : 'THỨ ${day + 1}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: day == DateTime.now().weekday
              ? const Color(0xFF126B5B)
              : const Color(0xFF536174),
        ),
      ),
    ),
  );
  Widget cell(BuildContext context, int day, int slot) {
    final lessons =
        schedules.where((s) => s.dayOfWeek == day && s.slot == slot).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return Container(
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(7),
      color: day == 7 ? const Color(0xFFF8FAFC) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lessons.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 62),
              child: Center(
                child: Text('—', style: TextStyle(color: Color(0xFFCCD3DD))),
              ),
            ),
          for (final s in lessons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: color(s.subjectCode).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => onSelect(s),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: color(s.subjectCode), width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s.startTime} – ${s.endTime}',
                          style: TextStyle(
                            color: color(s.subjectCode),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${s.subjectCode}  •  ${s.classCode}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          s.subjectName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF647184),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          s.room,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (lessons.length > 1)
                          Text(
                            s.semester,
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

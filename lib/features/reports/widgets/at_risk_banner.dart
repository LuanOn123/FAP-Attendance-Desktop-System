import 'package:flutter/material.dart';
import '../../../repositories/report_repository.dart';

/// Banner cảnh báo sinh viên At-risk (tỷ lệ có mặt < 80%)
class AtRiskBanner extends StatelessWidget {
  final List<StudentAttendanceSummary> atRiskStudents;
  final VoidCallback? onViewAll;

  const AtRiskBanner({
    super.key,
    required this.atRiskStudents,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (atRiskStudents.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade700,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${atRiskStudents.length} sinh viên có nguy cơ cấm thi',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tỷ lệ có mặt dưới 80%: '
                    '${atRiskStudents.map((s) => s.studentCode).take(3).join(", ")}'
                    '${atRiskStudents.length > 3 ? " và ${atRiskStudents.length - 3} sinh viên khác" : ""}',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (onViewAll != null)
              TextButton(
                onPressed: onViewAll,
                child: const Text('Xem chi tiết'),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'teaching_occurrence.dart';

/// Statuses a lecturer can choose in quick attendance, in display order.
const quickStatuses = ['present', 'absent'];

class QuickStudent {
  final String id, code, name;
  final String? historyUid;

  /// Official status already saved on the server (QR or manual), if any.
  final String? existing;
  const QuickStudent({
    required this.id,
    required this.code,
    required this.name,
    this.existing,
    this.historyUid,
  });
  factory QuickStudent.fromMap(AttendanceData d) => QuickStudent(
    id: '${d['studentId'] ?? '${d['studentUid']}'.replaceFirst('student-', '')}',
    code: '${d['studentCode'] ?? ''}',
    name: '${d['displayName'] ?? ''}',
    existing: d['status'] == null ? null : '${d['status']}'.toLowerCase(),
    historyUid: d['studentUid'] as String?,
  );

  /// What the draft starts with: the saved result, otherwise PRESENT.
  String get baseline =>
      existing == 'absent' || existing == 'excused' ? 'absent' : 'present';
}

enum QuickFilter { all, exceptions }

/// Pure, persistable draft. Nothing here talks to the server; the screen
/// decides when to submit [payload].
class QuickAttendanceDraft {
  final List<QuickStudent> students;

  /// Server revision the draft was built on ('' when no session existed).
  final String revision;
  final Map<String, String> _status;
  final List<(String, String)> _undo = [];
  QuickAttendanceDraft(this.students, {required this.revision})
    : _status = {for (final s in students) s.id: s.baseline};

  String statusOf(String id) => _status[id] ?? 'present';
  bool get canUndo => _undo.isNotEmpty;

  /// Changes one student only. Returns false when nothing changed.
  bool set(String id, String status) {
    if (!quickStatuses.contains(status) || !_status.containsKey(id)) {
      return false;
    }
    final previous = _status[id]!;
    if (previous == status) return false;
    _undo.add((id, previous));
    _status[id] = status;
    return true;
  }

  /// Reverts the last change; returns the student id it touched.
  String? undo() {
    if (_undo.isEmpty) return null;
    final (id, previous) = _undo.removeLast();
    _status[id] = previous;
    return id;
  }

  Map<String, int> get counts {
    final out = {for (final s in quickStatuses) s: 0};
    for (final s in students) {
      out[statusOf(s.id)] = (out[statusOf(s.id)] ?? 0) + 1;
    }
    return out;
  }

  /// Students the lecturer has to look at: anyone not PRESENT.
  List<QuickStudent> get exceptions =>
      students.where((s) => statusOf(s.id) != 'present').toList();

  /// True when the draft differs from what the server already holds.
  bool get dirty => students.any((s) => statusOf(s.id) != s.baseline);

  bool get hasExistingResults => students.any((s) => s.existing != null);

  /// Filtering never changes stored choices or the original order.
  List<QuickStudent> visible(QuickFilter filter, String query) {
    final q = attendanceSearchText(query);
    return students.where((s) {
      if (filter == QuickFilter.exceptions && statusOf(s.id) == 'present') {
        return false;
      }
      return q.isEmpty ||
          attendanceSearchText(s.name).contains(q) ||
          attendanceSearchText(s.code).contains(q);
    }).toList();
  }

  /// "40 sinh viên: 38 Có mặt, 2 Vắng".
  String summary() {
    final c = counts;
    final parts = [
      for (final s in quickStatuses)
        if (c[s]! > 0) '${c[s]} ${quickStatusLabel(s)}',
    ];
    return '${students.length} sinh viên: ${parts.join(', ')}';
  }

  /// Backend contract: everyone defaults to the saved result or PRESENT;
  /// only explicit differences are sent, on the exact roster shown.
  AttendanceData payload(AttendanceData selector, String requestId) => {
    ...selector,
    'expectedRevision': revision,
    'clientRequestId': requestId,
    'studentIds': [for (final s in students) s.id],
    'exceptions': [
      for (final s in students)
        if (statusOf(s.id) != s.baseline)
          {'studentId': s.id, 'status': statusOf(s.id).toUpperCase()},
    ],
  };

  String encode() => jsonEncode({
    'version': 1,
    'revision': revision,
    'roster': [for (final s in students) s.id],
    'status': _status,
  });

  /// Restores saved choices only when the roster and server revision still
  /// match; otherwise the draft would apply to data the lecturer never saw.
  bool restore(String? source) {
    if (source == null) return false;
    try {
      final d = jsonDecode(source) as Map;
      final roster = (d['roster'] as List).map((e) => '$e').toList();
      if (d['version'] != 1 ||
          d['revision'] != revision ||
          roster.length != students.length ||
          !students.every((s) => roster.contains(s.id))) {
        return false;
      }
      final saved = Map<String, dynamic>.from(d['status'] as Map);
      for (final s in students) {
        final v = '${saved[s.id]}';
        if (quickStatuses.contains(v)) _status[s.id] = v;
      }
      _undo.clear();
      return true;
    } catch (_) {
      return false;
    }
  }
}

String quickStatusLabel(String status) => switch (status) {
  'present' => 'Có mặt',
  'absent' => 'Vắng',
  'late' => 'Đi trễ',
  'excused' => 'Vắng có phép',
  _ => 'Chưa điểm danh',
};

/// Stable key for one lesson: class + date + slot (+ schedule/exception).
String quickDraftKey(String uid, AttendanceData selector) =>
    'quickAttendance/v1/$uid/${jsonEncode([selector['classId'], selector['sessionDate'], selector['slot'], selector['scheduleId'] ?? '', selector['exceptionId'] ?? ''])}';

String attendanceSearchText(String value) {
  var text = value.toLowerCase();
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  for (final entry in groups.entries) {
    for (final letter in entry.value.split('')) {
      text = text.replaceAll(letter, entry.key);
    }
  }
  return text
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

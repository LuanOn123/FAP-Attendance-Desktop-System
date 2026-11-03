import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/models/quick_attendance_draft.dart';

List<QuickStudent> roster(int n, {Map<int, String> existing = const {}}) => [
  for (var i = 1; i <= n; i++)
    QuickStudent(
      id: 's$i',
      code: 'SE${i.toString().padLeft(3, '0')}',
      name: 'Sinh viên $i',
      existing: existing[i],
    ),
];

void main() {
  const selector = {'classId': 'c1', 'sessionDate': '2026-10-19', 'slot': 2};

  test('40 students with 2 absent only needs 2 changes', () {
    final draft = QuickAttendanceDraft(roster(40), revision: '');
    expect(draft.counts['present'], 40);
    expect(draft.set('s3', 'absent'), isTrue);
    expect(draft.set('s17', 'absent'), isTrue);
    expect(draft.summary(), '40 sinh viên: 38 Có mặt, 2 Vắng');
    final payload = draft.payload(selector, 'r1');
    expect(payload['studentIds'], hasLength(40));
    expect(payload['exceptions'], [
      {'studentId': 's3', 'status': 'ABSENT'},
      {'studentId': 's17', 'status': 'ABSENT'},
    ]);
    expect(payload['expectedRevision'], '');
    expect(payload['classId'], 'c1');
  });

  test('full class submits no exceptions', () {
    final draft = QuickAttendanceDraft(roster(40), revision: '');
    expect(draft.summary(), '40 sinh viên: 40 Có mặt');
    expect(draft.payload(selector, 'r1')['exceptions'], isEmpty);
    expect(draft.dirty, isFalse);
  });

  test('changing one student never touches the others; undo restores', () {
    final draft = QuickAttendanceDraft(roster(5), revision: 'v1');
    draft.set('s2', 'absent');
    draft.set('s2', 'present');
    expect(
      [for (final s in draft.students) draft.statusOf(s.id)],
      ['present', 'present', 'present', 'present', 'present'],
    );
    expect(draft.undo(), 's2');
    expect(draft.statusOf('s2'), 'absent');
    expect(draft.undo(), 's2');
    expect(draft.statusOf('s2'), 'present');
    expect(draft.canUndo, isFalse);
    expect(draft.set('s2', 'present'), isFalse);
    expect(draft.set('unknown', 'absent'), isFalse);
    expect(draft.set('s1', 'maybe'), isFalse);
  });

  test('filter and search hide rows without losing their choices', () {
    final draft = QuickAttendanceDraft(roster(10), revision: '');
    draft.set('s4', 'absent');
    draft.set('s9', 'absent');
    expect(draft.visible(QuickFilter.exceptions, '').map((s) => s.id), [
      's4',
      's9',
    ]);
    expect(draft.visible(QuickFilter.all, 'SE001').map((s) => s.id), ['s1']);
    expect(draft.visible(QuickFilter.all, 'sinh viên 4').map((s) => s.id), [
      's4',
    ]);
    expect(draft.statusOf('s9'), 'absent');
    expect(draft.visible(QuickFilter.all, '').map((s) => s.id).first, 's1');
  });

  test('existing QR/manual results are kept as baseline, not overwritten', () {
    final draft = QuickAttendanceDraft(
      roster(3, existing: {1: 'absent', 2: 'present'}),
      revision: 'v2',
    );
    expect(draft.statusOf('s1'), 'absent');
    expect(draft.hasExistingResults, isTrue);
    expect(draft.payload(selector, 'r')['exceptions'], isEmpty);
    draft.set('s1', 'present');
    expect(draft.payload(selector, 'r')['exceptions'], [
      {'studentId': 's1', 'status': 'PRESENT'},
    ]);
    expect(draft.exceptions.map((s) => s.id), isEmpty);
  });

  test('saved draft restores only on the same roster and revision', () {
    final draft = QuickAttendanceDraft(roster(4), revision: 'v1')
      ..set('s2', 'absent');
    final saved = draft.encode();
    final same = QuickAttendanceDraft(roster(4), revision: 'v1');
    expect(same.restore(saved), isTrue);
    expect(same.statusOf('s2'), 'absent');
    expect(
      QuickAttendanceDraft(roster(4), revision: 'v2').restore(saved),
      isFalse,
    );
    expect(
      QuickAttendanceDraft(roster(5), revision: 'v1').restore(saved),
      isFalse,
    );
    expect(
      QuickAttendanceDraft(roster(4), revision: 'v1').restore('{bad'),
      isFalse,
    );
  });

  test('draft key separates two slots of the same class on one day', () {
    expect(
      quickDraftKey('u', {...selector, 'slot': 1}),
      isNot(quickDraftKey('u', {...selector, 'slot': 2})),
    );
  });

  test(
    'quick search supports unaccented Vietnamese names and extra spaces',
    () {
      final draft = QuickAttendanceDraft(const [
        QuickStudent(id: 's1', code: 'SE01', name: 'Nguyễn  Đức An'),
        QuickStudent(id: 's2', code: 'SE02', name: 'Bình'),
      ], revision: '');
      expect(draft.visible(QuickFilter.all, '  NGUYEN DUC ').map((s) => s.id), [
        's1',
      ]);
      expect(draft.visible(QuickFilter.all, 'se02').single.id, 's2');
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/groups/study_groups.dart';

void main() {
  testWidgets(
    'desktop opens tasks for a saved group/version and blocks entry with unsaved group edits',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyGroups(
              classId: 'c1',
              call: (method, data) async {
                calls.add({'method': method, ...data});
                if (method == 'getGroupPlan') {
                  return {
                    'version': 7,
                    'groups': [
                      {
                        'id': 'g1',
                        'name': 'Nhóm 1',
                        'memberIds': ['s1'],
                      },
                    ],
                    'students': [
                      {
                        'studentId': 's1',
                        'fullName': 'Student',
                        'studentCode': 'SE1',
                      },
                    ],
                  };
                }
                if (method == 'getGroupSignupSheet') {
                  return {'state': 'NONE', 'currentPlanVersion': 7};
                }
                if (method == 'listGroupTasks') return {'tasks': []};
                return {'messages': [], 'older': null};
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhóm 1 · 1 thành viên'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Giao việc cho nhóm'));
      await tester.tap(find.text('Giao việc cho nhóm'));
      await tester.pumpAndSettle();
      expect(find.text('Giao việc · Nhóm 1'), findsOneWidget);
      expect(calls.last, {
        'method': 'listGroupTasks',
        'classId': 'c1',
        'groupId': 'g1',
      });
      await tester.pageBack();
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('g1-name'));
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Nhóm sửa');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Giao việc cho nhóm'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('Giao việc cho nhóm'),
                matching: find.byWidgetPredicate((w) => w is OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(calls.where((c) => c['method'] == 'createGroupTask'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

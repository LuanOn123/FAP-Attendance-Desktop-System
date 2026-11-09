import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/groups/group_signup_panel.dart';
import 'package:fap_attendance/groups/group_tasks.dart';
import 'package:fap_attendance/groups/study_groups.dart';

void main() {
  testWidgets(
    'opens tasks for the saved group and reads its shared inbox status',
    (tester) async {
      final reads = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyGroups(
              classId: 'c1',
              call: (method, data) async {
                switch (method) {
                  case 'getGroupPlan':
                    return {
                      'version': 3,
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
                          'studentCode': 'SE1',
                          'fullName': 'One',
                        },
                      ],
                    };
                  case 'getGroupMessages':
                    return {'messages': [], 'older': null};
                  case 'getGroupSignupSheet':
                    return {'state': 'NONE', 'currentPlanVersion': 3};
                  case 'listGroupTasks':
                    reads.add(Map.of(data));
                    return {
                      'tasks': [
                        {
                          'title': 'Đọc yêu cầu PRM',
                          'description': 'Chuẩn bị bản demo',
                          'dueAt': '2026-11-10T03:00:00.000Z',
                          'readCount': 1,
                          'recipientCount': 1,
                          'emailSentCount': 0,
                        },
                      ],
                    };
                  default:
                    throw StateError('Unexpected method: $method');
                }
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Giao việc cho nhóm'));
      await tester.tap(find.text('Giao việc cho nhóm'));
      await tester.pumpAndSettle();
      expect(reads, [
        {'classId': 'c1', 'groupId': 'g1'},
      ]);
      await tester.scrollUntilVisible(
        find.text('Đọc yêu cầu PRM'),
        150,
        scrollable: find.descendant(
          of: find.byType(GroupTasksPage),
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(find.text('Đã đọc 1/1 · Email đã gửi 0/1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'creating a sheet requires confirmation and retries the same registered request',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupSignupPanel(
              classId: 'c1',
              version: 0,
              groupCount: 2,
              existingGroupCount: 0,
              disabled: false,
              onChanged: () async {},
              onLockChanged: (_) {},
              call: (method, data) async {
                if (method == 'getGroupSignupSheet') {
                  return {'state': 'NONE', 'currentPlanVersion': 0};
                }
                writes.add(Map.of(data));
                if (writes.length == 1) throw StateError('timeout');
                return {
                  'state': 'OPEN',
                  'currentPlanVersion': 1,
                  'assignedCount': 0,
                  'studentCount': 35,
                  'groupCount': 2,
                  'url':
                      'https://docs.google.com/spreadsheets/d/doc-1/edit#gid=100',
                };
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tạo Sheet chọn nhóm'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(find.text('Mở đăng ký nhóm bằng Google Sheets?'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(writes.length, 1);
      await tester.tap(find.text('Thử tạo lại cùng Sheet'));
      await tester.pumpAndSettle();
      expect(writes[1], writes[0]);
      expect(writes[0]['classId'], 'c1');
      expect(find.text('Sao chép link'), findsOneWidget);
      expect(find.text('Chốt đăng ký'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background sheet sync refreshes the displayed group roster without writing a plan',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var version = 1;
      final methods = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyGroups(
              classId: 'c1',
              call: (method, data) async {
                methods.add(method);
                if (method == 'getGroupPlan') {
                  return {
                    'version': version,
                    'groups': [
                      {
                        'id': 'g1',
                        'name': 'Nhóm 1',
                        'memberIds': version == 1 ? ['s1'] : ['s1', 's2'],
                      },
                    ],
                    'students': [
                      {
                        'studentId': 's1',
                        'studentCode': 'SE1',
                        'fullName': 'One',
                      },
                      {
                        'studentId': 's2',
                        'studentCode': 'SE2',
                        'fullName': 'Two',
                      },
                    ],
                  };
                }
                if (method == 'getGroupSignupSheet') {
                  return {
                    'state': 'OPEN',
                    'currentPlanVersion': version,
                    'assignedCount': version,
                    'studentCount': 2,
                    'groupCount': 1,
                  };
                }
                if (method == 'getGroupMessages') {
                  return {'messages': [], 'older': null};
                }
                throw StateError('Unexpected write: $method');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nhóm 1 · 1 thành viên'), findsOneWidget);
      version = 2;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Nhóm 1 · 2 thành viên'), findsOneWidget);
      expect(methods, isNot(contains('saveGroupPlan')));
      await tester.enterText(find.byType(TextField), 'Bản nháp');
      version = 3;
      final calls = methods.where((m) => m == 'getGroupPlan').length;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(methods.where((m) => m == 'getGroupPlan').length, calls);
      expect(find.text('Bản nháp'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

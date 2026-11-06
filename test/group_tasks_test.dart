import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/groups/group_tasks.dart';

void main() {
  test('deadline displays Vietnam calendar date regardless of device zone', () {
    expect(
      groupTaskDeadline(DateTime.parse('2026-11-04T18:00:00Z')),
      '05/11/2026 01:00',
    );
  });
  testWidgets('empty form cannot create task and load failure can retry', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: GroupTasksPage(
          classId: 'c1',
          groupId: 'g1',
          groupName: 'Nhóm 1',
          version: 1,
          memberCount: 3,
          call: (method, data) async {
            calls.add(method);
            if (calls.length == 1) throw StateError('offline');
            return {'tasks': []};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa tải được công việc'), findsOneWidget);
    await tester.tap(find.text('Giao việc'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tên việc'), findsOneWidget);
    expect(calls, ['listGroupTasks']);
    await tester.ensureVisible(find.text('Tải lại công việc'));
    await tester.tap(find.text('Tải lại công việc'));
    await tester.pumpAndSettle();
    expect(calls, ['listGroupTasks', 'listGroupTasks']);
    expect(find.text('Chưa có việc được giao.'), findsOneWidget);
  });
  testWidgets(
    'confirmation precedes create; uncertain retry reuses frozen payload',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final writes = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: GroupTasksPage(
            classId: 'c1',
            groupId: 'g1',
            groupName: 'Nhóm 1',
            version: 7,
            memberCount: 3,
            call: (method, data) async {
              if (method == 'listGroupTasks') return {'tasks': []};
              writes.add(Map.of(data));
              if (writes.length == 1) throw StateError('timeout');
              return {'recipientCount': 3};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên việc'),
        'Lab nhóm',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Yêu cầu'),
        'Hoàn thành lab',
      );
      await tester.tap(find.text('Chọn hạn · Giờ Việt Nam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giao việc'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận giao việc'), findsOneWidget);
      expect(writes, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Giao việc').last);
      await tester.pumpAndSettle();
      expect(writes.length, 1);
      expect(writes.first['version'], 7);
      await tester.tap(find.text('Thử lại cùng lần giao việc'));
      await tester.pumpAndSettle();
      expect(writes.length, 2);
      expect(writes[1], writes[0]);
      expect(find.textContaining('Đã giao việc · 3'), findsOneWidget);
    },
  );
}

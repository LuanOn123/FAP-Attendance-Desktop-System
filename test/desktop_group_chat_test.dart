import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/groups/study_groups.dart';

void main() {
  testWidgets(
    'chat separates speakers, pins composer and sends to the selected group',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sent = <Map<String, dynamic>>[];
      final groupTwoMessages = Completer<Map<String, dynamic>>();
      Map<String, dynamic> save(Map<String, dynamic> data) {
        sent.add(data);
        return {'saved': true};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyGroups(
              classId: 'c1',
              startInChat: true,
              call: (method, data) async => switch (method) {
                'getGroupPlan' => {
                  'version': 1,
                  'groups': [
                    {
                      'id': 'g1',
                      'name': 'Nhóm 1',
                      'memberIds': ['s1'],
                    },
                    {
                      'id': 'g2',
                      'name': 'Nhóm 2',
                      'memberIds': ['s2'],
                    },
                  ],
                  'students': [],
                },
                'getGroupSignupSheet' => {'state': 'NONE'},
                'getGroupMessages' when data['groupId'] == 'g2' =>
                  groupTwoMessages.future,
                'getGroupMessages' => {
                  'messages': [
                    if (data['groupId'] == 'g1') ...[
                      {
                        'id': 'm1',
                        'mine': false,
                        'text': 'Xin chào thầy',
                        'senderName': 'Sinh viên',
                      },
                      {'id': 'm2', 'mine': true, 'text': 'Chào em'},
                    ],
                  ],
                },
                'sendGroupMessage' => save(data),
                _ => throw StateError(method),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('HỘI THOẠI'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Xin chào thầy')).dx,
        lessThan(tester.getTopLeft(find.text('Chào em')).dx),
      );
      await tester.tap(find.text('Nhóm 2'));
      await tester.pump();
      expect(find.text('Đang tải tin nhắn…'), findsOneWidget);
      expect(find.text('Chưa có tin nhắn trong hội thoại này.'), findsNothing);
      groupTwoMessages.complete({'messages': []});
      await tester.pumpAndSettle();
      expect(find.text('Đang tải tin nhắn…'), findsNothing);
      expect(
        find.text('Chưa có tin nhắn trong hội thoại này.'),
        findsOneWidget,
      );
      final composer = find.byType(TextField);
      await tester.enterText(composer, 'Trao đổi nhóm hai');
      await tester.pump();
      await tester.tap(find.byTooltip('Gửi tin nhắn'));
      await tester.pumpAndSettle();
      expect(sent.single['classId'], 'c1');
      expect(sent.single['groupId'], 'g2');
      expect(sent.single['text'], 'Trao đổi nhóm hai');
      expect(sent.single['requestKey'], isNotEmpty);
      await tester.binding.setSurfaceSize(const Size(600, 500));
      await tester.pumpAndSettle();
      expect(find.text('HỘI THOẠI'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

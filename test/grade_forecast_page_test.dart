import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/grade_forecast/grade_forecast.dart';
import 'package:fap_attendance/grade_forecast/grade_forecast_page.dart';

const fixture = [
  ForecastColumn(name: 'Assignment', weight: '20', score: '5'),
  ForecastColumn(name: 'PT', weight: '20', score: '5'),
  ForecastColumn(name: 'Quiz', weight: '20', score: '5'),
  ForecastColumn(name: 'FE', kind: 'FE', weight: '40'),
];
void main() {
  for (final width in [375.0, 1200.0]) {
    testWidgets(
      'calculator renders and calculates without overflow at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          const MaterialApp(
            home: GradeForecastPage(
              initialColumns: fixture,
              contextLabel: 'PRM393 · SE1848',
            ),
          ),
        );
        final calculate = find.text('Tính điểm cần đạt');
        await tester.ensureVisible(calculate);
        await tester.tap(calculate);
        await tester.pumpAndSettle();
        expect(find.text('FE cần ít nhất 5,1 / 10'), findsOneWidget);
        expect(find.textContaining('5,04 / 10'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('forecast-score-1')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('forecast-score-1')),
          '9',
        );
        await tester.pump();
        expect(find.text('Kết quả tính điểm'), findsNothing);
        expect(fixture.first.score, '5');
      },
    );
  }
  testWidgets(
    'can add PE, calculate paired scenarios, remove it and retain FE data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: GradeForecastPage(initialColumns: fixture)),
      );
      await tester.ensureVisible(find.text('+ PE'));
      await tester.tap(find.text('+ PE'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+ PE'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('forecast-weight-4')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forecast-weight-4')),
        '20',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('forecast-weight-5')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forecast-weight-5')),
        '20',
      );
      await tester.ensureVisible(find.text('Tính điểm cần đạt'));
      await tester.tap(find.text('Tính điểm cần đạt'));
      await tester.pumpAndSettle();
      expect(find.text('FE và PE đều từ 5,1 / 10'), findsOneWidget);
      expect(find.text('Giả sử điểm PE, tính FE tối thiểu'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Xóa cột 5'));
      await tester.tap(find.byTooltip('Xóa cột 5'));
      await tester.pumpAndSettle();
      expect(find.text('Kết quả tính điểm'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('forecast-weight-4')))
            .controller!
            .text,
        '20',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing regular scores block calculation instead of becoming zero',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GradeForecastPage()));
      await tester.ensureVisible(find.text('Tính điểm cần đạt'));
      await tester.tap(find.text('Tính điểm cần đạt'));
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra lại dữ liệu'), findsOneWidget);
      expect(find.textContaining('Cột 1: nhập điểm đã có'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/grade_forecast/grade_forecast.dart';

ForecastColumn known(String score, String weight) =>
    ForecastColumn(name: 'Quiz', weight: weight, score: score);
ForecastColumn exam(String kind, String weight, [String score = '']) =>
    ForecastColumn(name: kind, kind: kind, weight: weight, score: score);
void main() {
  test('combines FE and PE floors with the strict overall target', () {
    final result = forecastGrades([
      known('10', '50'),
      const ForecastColumn(
        name: 'FE',
        kind: 'FE',
        weight: '25',
        minimum: '4,55',
      ),
      const ForecastColumn(name: 'PE', kind: 'PE', weight: '25', minimum: '6'),
    ]);
    expect(result.status, ForecastStatus.pair);
    expect(result.sameScore, 6);
    expect(result.scenarios[5].fe, isNull);
    expect(result.scenarios[6].fe, 4.6);
  });
  test(
    'strictly greater than five; smallest passing tenth rather than equality',
    () {
      final r = forecastGrades([known('5', '60'), exam('FE', '40')]);
      expect(r.status, ForecastStatus.single);
      expect(r.needed, 5.1);
      expect(r.total, 5.04);
      expect(
        forecastGrades([known('5', '60'), exam('FE', '40', '5')]).status,
        ForecastStatus.failed,
      );
    },
  );
  test(
    'zero is known, decimal comma accepted, previously graded exam is fixed',
    () {
      expect(forecastHundredths('0'), 0);
      expect(forecastHundredths('8,5'), 850);
      expect(
        forecastGrades([
          known('0', '10'),
          known('8,5', '50'),
          exam('PE', '40'),
        ]).needed,
        1.9,
      );
      expect(
        forecastGrades([
          known('5', '60'),
          exam('PE', '20', '6'),
          exam('FE', '20'),
        ]).needed,
        4.1,
      );
      expect(
        forecastGrades([known('10', '60'), exam('FE', '40', '0')]).status,
        ForecastStatus.passed,
      );
    },
  );
  test(
    'decimal percentages sum exactly; result displayed without hiding a boundary',
    () {
      expect(
        forecastGrades([
          known('5', '33,33'),
          known('5', '33.33'),
          exam('FE', '33.34'),
        ]).needed,
        5.1,
      );
      expect(
        forecastGrades([known('5', '99.99'), known('5.01', '0.01')]).total,
        5.000001,
      );
      expect(forecastNumber(5.000001), '5,000001');
      expect(forecastNumber(10), '10');
      expect(forecastNumber(0), '0');
    },
  );
  test(
    'maximum equal to five is impossible; required exam may be zero or ten',
    () {
      expect(
        forecastGrades([known('0', '50'), exam('FE', '50')]).status,
        ForecastStatus.impossible,
      );
      expect(forecastGrades([known('9', '60'), exam('FE', '40')]).needed, 0);
      expect(
        forecastGrades([known('0.01', '50'), exam('PE', '50')]).needed,
        10,
      );
    },
  );
  test(
    'two unknowns produce coupled scenarios, not independent minimum marks',
    () {
      final r = forecastGrades([
        known('5', '60'),
        exam('FE', '25'),
        exam('PE', '15'),
      ]);
      expect(r.status, ForecastStatus.pair);
      expect(r.sameScore, 5.1);
      expect(r.total, 5.04);
      for (final pair in r.scenarios) {
        if (pair.fe == null) {
          expect(
            3000000 + 1000 * 2500 + pair.pe * 100 * 1500,
            lessThanOrEqualTo(5000000),
          );
        } else {
          expect(pair.total, greaterThan(5));
          if (pair.fe! > 0) {
            expect(
              3000000 +
                  ((pair.fe! - .1) * 100).round() * 2500 +
                  pair.pe * 100 * 1500,
              lessThanOrEqualTo(5000000),
            );
          }
        }
      }
    },
  );
  test(
    'invalid scores, weights, empty regular scores and duplicate exams are blocked',
    () {
      for (final value in [
        '-1',
        '10.01',
        'NaN',
        'Infinity',
        '1e1',
        '8/10',
        '5.123',
        'abc',
        '',
      ]) {
        expect(
          forecastGrades([known(value, '60'), exam('FE', '40')]).status,
          ForecastStatus.invalid,
          reason: value,
        );
      }
      for (final weight in ['0', '-1', '101', '', '1e2', '50.001', '59.99']) {
        expect(
          forecastGrades([known('5', weight), exam('FE', '40')]).status,
          ForecastStatus.invalid,
          reason: weight,
        );
      }
      expect(
        forecastGrades([exam('FE', '50'), exam('FE', '50')]).status,
        ForecastStatus.invalid,
      );
      expect(forecastGrades([]).status, ForecastStatus.invalid);
      expect(
        forecastGrades(List.generate(31, (_) => known('5', '1'))).status,
        ForecastStatus.invalid,
      );
    },
  );
  test(
    'recommendations are sufficient and minimal across a grid of scores/weights',
    () {
      for (var score = 0; score <= 10; score++) {
        for (var weight = 10; weight < 100; weight += 10) {
          final r = forecastGrades([
            known('$score', '${100 - weight}'),
            exam('FE', '$weight'),
          ]);
          if (r.status == ForecastStatus.impossible) {
            expect(r.maximum, lessThanOrEqualTo(5));
          } else {
            expect(r.total, greaterThan(5));
            expect(r.needed, lessThanOrEqualTo(10));
            if (r.needed! > 0) {
              expect(
                score * 100 * (100 - weight) * 100 +
                    ((r.needed! - .1) * 100).round() * weight * 100,
                lessThanOrEqualTo(5000000),
              );
            }
          }
        }
      }
    },
  );
}

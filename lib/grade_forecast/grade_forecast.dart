/// Same calculation contract as Student Web: total strictly > 5, scores /10,
/// weights sum to 100%, recommendations on a 0.1 grid. No network or persistence.
class ForecastColumn {
  final String name, kind, weight, score, minimum;
  const ForecastColumn({
    required this.name,
    this.kind = 'known',
    required this.weight,
    this.score = '',
    this.minimum = '0',
  });
}

List<ForecastColumn> defaultForecastColumns() => const [
  ForecastColumn(name: 'Assignment', weight: ''),
  ForecastColumn(name: 'PT', weight: ''),
  ForecastColumn(name: 'Quiz', weight: ''),
  ForecastColumn(name: 'FE', kind: 'FE', weight: ''),
];

int? forecastHundredths(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(text)) return null;
  final number = double.tryParse(text.replaceAll(',', '.'));
  if (number == null || !number.isFinite || number > 1000000) return null;
  return (number * 100).round();
}

enum ForecastStatus { invalid, single, pair, impossible, passed, failed }

class ForecastScenario {
  final int pe;
  final double? fe, total;
  final String? reason;
  const ForecastScenario(this.pe, this.fe, this.total, [this.reason]);
}

class ForecastResult {
  final ForecastStatus status;
  final List<String> errors;
  final double current, maximum;
  final double? needed, sameScore, total;
  final String? exam;
  final List<ForecastScenario> scenarios;
  const ForecastResult({
    required this.status,
    this.errors = const [],
    this.current = 0,
    this.maximum = 0,
    this.needed,
    this.sameScore,
    this.total,
    this.exam,
    this.scenarios = const [],
  });
}

ForecastResult forecastGrades(List<ForecastColumn> rows) {
  const scale = 1000000, pass = 5000000;
  final errors = <String>[], examTypes = <String>{};
  final weights = <int>[], scores = <int?>[], minima = <int>[];
  if (rows.isEmpty || rows.length > 30) {
    return const ForecastResult(
      status: ForecastStatus.invalid,
      errors: ['Cần từ 1 đến 30 cột điểm.'],
    );
  }
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i], label = 'Cột ${i + 1}';
    final weight = forecastHundredths(row.weight), text = row.score.trim();
    final score = text.isEmpty ? null : forecastHundredths(text);
    final minimum = forecastHundredths(row.minimum);
    if (!['known', 'FE', 'PE'].contains(row.kind)) {
      errors.add('$label: chọn loại điểm hợp lệ.');
    }
    if (row.name.trim().isEmpty || row.name.length > 80) {
      errors.add('$label: nhập tên tối đa 80 ký tự.');
    }
    if (weight == null || weight <= 0 || weight > 10000) {
      errors.add('$label: trọng số phải lớn hơn 0 và không quá 100%.');
    }
    if (text.isNotEmpty && (score == null || score > 1000)) {
      errors.add('$label: điểm phải từ 0 đến 10, tối đa 2 chữ số thập phân.');
    }
    if (row.kind == 'known' && text.isEmpty) {
      errors.add('$label: nhập điểm đã có; chỉ FE/PE được để trống để tính.');
    }
    if (row.kind == 'FE' || row.kind == 'PE') {
      if (minimum == null || minimum < 0 || minimum > 1000) {
        errors.add('$label: điểm tối thiểu ${row.kind} phải từ 0 đến 10.');
      } else if (score != null && score < minimum) {
        errors.add(
          '${row.kind} đang dưới ngưỡng ${forecastNumber(minimum / 100)} theo đề cương đã nhập. Xóa điểm bài thi để tính mức cần đạt.',
        );
      }
      if (!examTypes.add(row.kind)) {
        errors.add('Chỉ được có một cột ${row.kind}.');
      }
    }
    weights.add(weight ?? 0);
    scores.add(score);
    minima.add(minimum ?? 0);
  }
  final totalWeight = weights.fold<int>(0, (sum, w) => sum + w);
  if (totalWeight != 10000) {
    errors.add(
      'Tổng trọng số phải đúng 100% (hiện tại ${forecastNumber(totalWeight / 100)}%).',
    );
  }
  if (errors.isNotEmpty) {
    return ForecastResult(status: ForecastStatus.invalid, errors: errors);
  }
  final unknown = <int>[];
  var base = 0;
  for (var i = 0; i < rows.length; i++) {
    if (scores[i] == null) unknown.add(i);
    base += (scores[i] ?? 0) * weights[i];
  }
  final maximum =
      base + unknown.fold<int>(0, (sum, i) => sum + 1000 * weights[i]);
  if (unknown.isEmpty) {
    return ForecastResult(
      status: base > pass ? ForecastStatus.passed : ForecastStatus.failed,
      current: base / scale,
      maximum: maximum / scale,
      total: base / scale,
    );
  }
  if (maximum <= pass) {
    return ForecastResult(
      status: ForecastStatus.impossible,
      current: base / scale,
      maximum: maximum / scale,
    );
  }
  int? minimumTenth(int extraBase, int weight, [int floor = 0]) {
    for (var tenth = 0; tenth <= 100; tenth++) {
      if (tenth * 10 >= floor && extraBase + tenth * 10 * weight > pass) {
        return tenth;
      }
    }
    return null;
  }

  if (unknown.length == 1) {
    final i = unknown.single,
        needed = minimumTenth(base, weights[i], minima[i])!;
    return ForecastResult(
      status: ForecastStatus.single,
      current: base / scale,
      maximum: maximum / scale,
      exam: rows[i].kind,
      needed: needed / 10,
      total: (base + needed * 10 * weights[i]) / scale,
    );
  }
  final fe = unknown.singleWhere((i) => rows[i].kind == 'FE'),
      pe = unknown.singleWhere((i) => rows[i].kind == 'PE');
  final same = minimumTenth(
    base,
    weights[fe] + weights[pe],
    minima[fe] > minima[pe] ? minima[fe] : minima[pe],
  )!;
  final scenarios = List.generate(11, (peScore) {
    if (peScore * 100 < minima[pe]) {
      return ForecastScenario(peScore, null, null, 'PE dưới ngưỡng đã nhập');
    }
    final extra = base + peScore * 100 * weights[pe],
        feTenth = minimumTenth(extra, weights[fe], minima[fe]);
    return ForecastScenario(
      peScore,
      feTenth == null ? null : feTenth / 10,
      feTenth == null ? null : (extra + feTenth * 10 * weights[fe]) / scale,
    );
  });
  return ForecastResult(
    status: ForecastStatus.pair,
    current: base / scale,
    maximum: maximum / scale,
    sameScore: same / 10,
    total: (base + same * 10 * (weights[fe] + weights[pe])) / scale,
    scenarios: scenarios,
  );
}

String forecastNumber(num number) => number
    .toStringAsFixed(6)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');

import 'package:flutter/material.dart';
import 'grade_forecast.dart';

class _Entry {
  final int id;
  final String kind;
  final TextEditingController name, weight, score, minimum;
  _Entry(this.id, ForecastColumn column)
    : kind = column.kind,
      name = TextEditingController(text: column.name),
      weight = TextEditingController(text: column.weight),
      score = TextEditingController(text: column.score),
      minimum = TextEditingController(text: column.minimum);
  ForecastColumn get value => ForecastColumn(
    name: name.text,
    kind: kind,
    weight: weight.text,
    score: score.text,
    minimum: minimum.text,
  );
  void dispose() {
    name.dispose();
    weight.dispose();
    score.dispose();
    minimum.dispose();
  }
}

class GradeForecastPage extends StatefulWidget {
  final String? contextLabel;
  final List<ForecastColumn>? initialColumns;
  const GradeForecastPage({super.key, this.contextLabel, this.initialColumns});
  @override
  State<GradeForecastPage> createState() => _GradeForecastPageState();
}

class _GradeForecastPageState extends State<GradeForecastPage> {
  final entries = <_Entry>[];
  final scroll = ScrollController();
  final resultKey = GlobalKey();
  ForecastResult? result;
  int nextId = 1;
  @override
  void initState() {
    super.initState();
    for (final column in widget.initialColumns ?? defaultForecastColumns()) {
      entries.add(_Entry(nextId++, column));
    }
  }

  @override
  void dispose() {
    for (final entry in entries) {
      entry.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  void add(String kind) {
    setState(() {
      entries.add(
        _Entry(
          nextId++,
          ForecastColumn(
            name: kind == 'known' ? 'Lab' : kind,
            kind: kind,
            weight: '',
          ),
        ),
      );
      result = null;
    });
  }

  void calculate() {
    FocusScope.of(context).unfocus();
    setState(
      () => result = forecastGrades(entries.map((e) => e.value).toList()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || resultKey.currentContext == null) return;
      Scrollable.ensureVisible(
        resultKey.currentContext!,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalWeight =
        entries.fold<int>(
          0,
          (sum, entry) => sum + (forecastHundredths(entry.weight.text) ?? 0),
        ) /
        100;
    return Scaffold(
      appBar: AppBar(title: const Text('Tính điểm FE/PE')),
      body: SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.contextLabel != null)
                  Text(
                    widget.contextLabel!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                Text(
                  'Tư vấn điểm cần đạt',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nhập điểm đã có và trọng số theo syllabus. Để trống điểm FE hoặc PE cần tính.',
                ),
                const Text(
                  'Bảng tính thử · Không ghi vào bảng điểm chính thức',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Chip(label: Text('Thang 10')),
                    Chip(
                      label: Text(
                        'Trọng số ${forecastNumber(totalWeight)} / 100%',
                      ),
                    ),
                    const Chip(label: Text('Mục tiêu tổng > 5')),
                  ],
                ),
                for (var i = 0; i < entries.length; i++)
                  entryCard(entries[i], i + 1),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: entries.length >= 30
                          ? null
                          : () => add('known'),
                      child: const Text('+ Cột điểm'),
                    ),
                    for (final kind in ['FE', 'PE'])
                      OutlinedButton(
                        onPressed:
                            entries.length >= 30 ||
                                entries.any((e) => e.kind == kind)
                            ? null
                            : () => add(kind),
                        child: Text('+ $kind'),
                      ),
                    FilledButton.icon(
                      onPressed: calculate,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Tính điểm cần đạt'),
                    ),
                  ],
                ),
                if (result != null) resultCard(result!),
                const SizedBox(height: 16),
                const Text(
                  'Xét tổng > 5 và ngưỡng FE/PE theo đề cương đã nhập. Chuyên cần và điều kiện khác cần kiểm tra riêng trong syllabus.',
                ),
                const ExpansionTile(
                  title: Text('Công thức & điều kiện'),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Tổng = Σ (điểm × trọng số / 100).\n\nMột bài thi: điểm phải lớn hơn (5 − tổng đã quy đổi) ÷ (trọng số bài thi / 100), đồng thời đạt ngưỡng FE/PE đã nhập.\n\nĐiểm thi gợi ý theo bước 0,1. Tổng đúng 5 chưa đạt mục tiêu “trên 5”; tính bằng tổng chưa làm tròn.\n\nDữ liệu chỉ ở màn hình hiện tại, mất khi đóng. Không gửi lên server hay thay đổi điểm đã công bố.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget entryCard(_Entry entry, int index) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cột $index${entry.kind == 'known' ? '' : ' · ${entry.kind}'}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Xóa cột $index',
                onPressed: entries.length == 1
                    ? null
                    : () {
                        setState(() {
                          entries.remove(entry);
                          result = null;
                        });
                        // Wait until the old TextFields detach before disposing their controllers.
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => entry.dispose(),
                        );
                      },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              Widget field(
                String label,
                TextEditingController controller,
                String key, {
                bool readOnly = false,
                String? hint,
                bool numeric = false,
              }) => TextField(
                key: ValueKey(key),
                controller: controller,
                readOnly: readOnly,
                maxLength: numeric ? 12 : 80,
                keyboardType: numeric
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  counterText: '',
                ),
                onChanged: (_) => setState(() => result = null),
              );
              final name = field(
                'Tên cột $index',
                entry.name,
                'forecast-name-${entry.id}',
                readOnly: entry.kind != 'known',
              );
              final weight = field(
                'Trọng số cột $index (%)',
                entry.weight,
                'forecast-weight-${entry.id}',
                hint: 'VD: 20',
                numeric: true,
              );
              final score = field(
                'Điểm cột $index / 10',
                entry.score,
                'forecast-score-${entry.id}',
                hint: entry.kind == 'known' ? 'VD: 8,5' : 'Trống = cần tính',
                numeric: true,
              );
              if (constraints.maxWidth >= 650) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: 12),
                    Expanded(child: weight),
                    const SizedBox(width: 12),
                    Expanded(child: score),
                  ],
                );
              }
              return Column(
                children: [
                  name,
                  const SizedBox(height: 12),
                  weight,
                  const SizedBox(height: 12),
                  score,
                ],
              );
            },
          ),
          if (entry.kind != 'known')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                key: ValueKey('forecast-minimum-${entry.id}'),
                controller: entry.minimum,
                maxLength: 12,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Điểm tối thiểu ${entry.kind} (theo đề cương)',
                  helperText: '0 = không áp dụng ngưỡng riêng',
                  counterText: '',
                ),
                onChanged: (_) => setState(() => result = null),
              ),
            ),
        ],
      ),
    ),
  );
  Widget resultCard(ForecastResult r) {
    final problem = [
      ForecastStatus.invalid,
      ForecastStatus.impossible,
      ForecastStatus.failed,
    ].contains(r.status);
    return Card(
      key: resultKey,
      margin: const EdgeInsets.only(top: 20),
      color: problem
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kết quả tính điểm',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (r.status == ForecastStatus.invalid) ...[
              const Text('Kiểm tra lại dữ liệu'),
              ...r.errors.map((e) => Text('• $e')),
            ],
            if (r.status == ForecastStatus.single) ...[
              Text(
                '${r.exam} cần ít nhất ${forecastNumber(r.needed!)} / 10',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Tổng dự kiến: ${forecastNumber(r.total!)} / 10 khi các điểm khác giữ nguyên.',
              ),
            ],
            if (r.status == ForecastStatus.pair) ...[
              Text(
                'FE và PE đều từ ${forecastNumber(r.sameScore!)} / 10',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Tổng dự kiến: ${forecastNumber(r.total!)} / 10. Hoặc chọn một cặp điểm bên dưới; hai mức phải đi cùng nhau.',
              ),
              const SizedBox(height: 12),
              const Text('Giả sử điểm PE, tính FE tối thiểu'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('PE giả định')),
                    DataColumn(label: Text('FE cần đạt')),
                    DataColumn(label: Text('Tổng dự kiến')),
                  ],
                  rows: r.scenarios
                      .map(
                        (s) => DataRow(
                          cells: [
                            DataCell(Text('${s.pe}')),
                            DataCell(
                              Text(
                                s.fe == null
                                    ? s.reason ?? 'Không đủ dù FE = 10'
                                    : forecastNumber(s.fe!),
                              ),
                            ),
                            DataCell(
                              Text(
                                s.total == null
                                    ? '—'
                                    : forecastNumber(s.total!),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            if (r.status == ForecastStatus.impossible) ...[
              const Text('Chưa thể vượt 5 với các điểm đã nhập'),
              Text(
                'Dù phần thi còn lại đều đạt 10, tổng tối đa là ${forecastNumber(r.maximum)} / 10. Kiểm tra trọng số hoặc trao đổi về cách cải thiện điểm.',
              ),
            ],
            if (r.status == ForecastStatus.passed ||
                r.status == ForecastStatus.failed) ...[
              Text(
                r.status == ForecastStatus.passed
                    ? 'Tổng điểm đã vượt 5'
                    : 'Tổng điểm chưa vượt 5',
              ),
              Text(
                'Tổng theo dữ liệu đã nhập: ${forecastNumber(r.total!)} / 10. Xóa điểm FE/PE để tính mức cần đạt.',
              ),
            ],
            if (r.status != ForecastStatus.invalid)
              const Text('Gợi ý theo bước 0,1 · Tính trên tổng chưa làm tròn.'),
          ],
        ),
      ),
    );
  }
}

/// Reconstruct table cells before parsing; plain OCR lines lose column context.
class OcrLayout {
  static String reconstruct(Map<String, dynamic> data) {
    final words = (data['words'] as List? ?? [])
        .map((w) => Map<String, dynamic>.from(w as Map))
        .toList();
    double x(Map w) => (w['x'] as num).toDouble();
    double y(Map w) => (w['y'] as num).toDouble();
    String text(Map w) => '${w['text']}';
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final headers =
        words.where((w) => days.contains(text(w).toUpperCase())).toList()
          ..sort((a, b) => x(a).compareTo(x(b)));
    final seenDays = <String>{};
    headers.removeWhere((w) => !seenDays.add(text(w).toUpperCase()));
    final slots = <Map<String, dynamic>>[];
    if (headers.length == 7) {
      for (final w in words.where((w) => text(w).toUpperCase() == 'SLOT')) {
        final numbers =
            words
                .where(
                  (n) =>
                      x(n) > x(w) &&
                      x(n) < x(w) + 100 &&
                      (y(n) - y(w)).abs() < 10 &&
                      RegExp(r'^\d{1,2}$').hasMatch(text(n)),
                )
                .toList()
              ..sort((a, b) => x(a).compareTo(x(b)));
        if (numbers.isNotEmpty) slots.add({...w, 'slot': text(numbers.first)});
      }
      slots.sort((a, b) => y(a).compareTo(y(b)));
      if (slots.isNotEmpty) {
        final lines = <String>[];
        for (var r = 0; r < slots.length; r++) {
          for (var c = 0; c < headers.length; c++) {
            final cell =
                words
                    .where(
                      (w) =>
                          x(w) >= x(headers[c]) - 8 &&
                          (c + 1 == headers.length ||
                              x(w) < x(headers[c + 1]) - 8) &&
                          y(w) >= y(slots[r]) - 8 &&
                          (r + 1 == slots.length || y(w) < y(slots[r + 1]) - 8),
                    )
                    .toList()
                  ..sort(
                    (a, b) => (y(a) - y(b)).abs() < 8
                        ? x(a).compareTo(x(b))
                        : y(a).compareTo(y(b)),
                  );
            if (cell.isNotEmpty) {
              lines.add(
                '${text(headers[c])} Slot ${slots[r]['slot']} ${cell.map(text).join(' ')}',
              );
            }
          }
        }
        return lines.join('\n');
      }
    }
    // Assignment tables: OCR can split each row into separate column lines.
    final subjects = words
        .where(
          (w) => RegExp(r'^[A-Z]{2,6}\d{3}$').hasMatch(text(w).toUpperCase()),
        )
        .toList();
    if (subjects.isNotEmpty &&
        words.any((w) => text(w).toUpperCase() == 'SLOT')) {
      return subjects
          .map((s) {
            final row = words.where((w) => (y(w) - y(s)).abs() < 10).toList()
              ..sort((a, b) => x(a).compareTo(x(b)));
            return row.map(text).join(' ');
          })
          .join('\n');
    }
    return '${data['text'] ?? ''}';
  }
}

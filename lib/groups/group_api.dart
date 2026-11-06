import 'dart:math';

typedef GroupCall =
    Future<dynamic> Function(String method, Map<String, dynamic> data);

String groupRequestKey() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

import 'package:flutter/material.dart';

class ModulePlaceholder extends StatelessWidget {
  final String title, owner, description;
  const ModulePlaceholder({
    super.key,
    required this.title,
    required this.owner,
    required this.description,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_outlined, size: 60),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            '$owner • Chờ tích hợp',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(description, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

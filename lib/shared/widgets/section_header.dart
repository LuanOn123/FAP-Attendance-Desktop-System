import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

class SectionHeader extends StatelessWidget {
  final String eyebrow, title, subtitle;
  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: AppPalette.orangeSoft,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppPalette.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppPalette.orangeDark,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: AppPalette.muted)),
      ],
    ),
  );
}

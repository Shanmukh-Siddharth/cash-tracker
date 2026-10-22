/// Phase-1 stub bottom sheet: "Coming in Phase N". Shared by Add/Subtract
/// and the center + chooser so every dead-end looks intentional.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

Future<void> showStubSheet(
  BuildContext context, {
  required String title,
  required int phase,
  String? body,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body ?? 'This screen arrives with the full build.',
            style: const TextStyle(fontSize: 14, color: AppColors.text2),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(
              'Coming in Phase $phase',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

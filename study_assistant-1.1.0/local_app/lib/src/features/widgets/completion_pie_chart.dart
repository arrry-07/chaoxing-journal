import 'package:flutter/material.dart';

import '../../app/journal.dart';

/// Shared palette and labels for the four statistics status buckets
/// (completed, pending, overdue, unknown).
class CompletionPieChart {
  const CompletionPieChart._();

  static List<Color> colorsFor(JournalPalette journal) => journal.isDark
      ? const [
          Color(0xFF88A8F8),
          Color(0xFF5F7DB8),
          Color(0xFFE8827D),
          Color(0xFF6E6A63),
        ]
      : const [
          Color(0xFF4B6CB7),
          Color(0xFF9EB5E5),
          Color(0xFFD47474),
          Color(0xFFD8DCE2),
        ];

  static const labels = ['已完成', '待完成', '已逾期', '提交未知'];
}

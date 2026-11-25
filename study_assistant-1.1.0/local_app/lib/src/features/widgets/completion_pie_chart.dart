import 'package:flutter/material.dart';

import '../../app/journal.dart';

/// Shared palette and labels for the four statistics status buckets
/// (completed, pending, overdue, unknown).
class CompletionPieChart {
  const CompletionPieChart._();

  static List<Color> colorsFor(JournalPalette journal) => journal.isDark
      ? [
          const Color(0xFF7B9DF6),
          const Color(0xFF3E4F75),
          journal.overdueSky,
          const Color(0xFF6E6A63),
        ]
      : [
          const Color(0xFF3D63DD),
          const Color(0xFFC5D5F5),
          journal.overdueSky,
          const Color(0xFFDBDCE0),
        ];

  static const labels = ['已完成', '待完成', '已逾期', '提交未知'];
}

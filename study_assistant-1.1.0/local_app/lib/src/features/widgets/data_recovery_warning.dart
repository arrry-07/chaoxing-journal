import 'package:flutter/material.dart';

import '../../app/journal.dart';

class DataRecoveryWarning extends StatelessWidget {
  const DataRecoveryWarning({super.key, required this.warning});

  final String warning;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Card(
      color: journal.berryBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: journal.berryBorder, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_outlined,
                color: journal.berry,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '数据恢复警告：$warning',
                  style: TextStyle(color: journal.berry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

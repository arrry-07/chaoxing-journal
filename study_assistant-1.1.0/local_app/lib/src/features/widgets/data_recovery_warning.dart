import 'package:flutter/material.dart';

class DataRecoveryWarning extends StatelessWidget {
  const DataRecoveryWarning({super.key, required this.warning});

  final String warning;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '数据恢复警告：$warning',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

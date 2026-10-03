import 'package:flutter/material.dart';

class SyncProgressBar extends StatelessWidget {
  final int completed;
  final int total;
  final int percentage;
  final String? currentRecordName;

  const SyncProgressBar({
    super.key,
    required this.completed,
    required this.total,
    required this.percentage,
    this.currentRecordName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Syncing $completed of $total records — $percentage%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: total == 0 ? 0 : completed / total),
          if (currentRecordName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Uploading: $currentRecordName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/form_record.dart' show FormRecord, SyncStatus;

class RecordTile extends StatelessWidget {
  final FormRecord record;
  final VoidCallback? onTap;

  const RecordTile({super.key, required this.record, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _buildThumbnail(),
        ),
        title: Text(
          record.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${record.category} • '
              '${DateFormat('dd MMM yyyy').format(record.visitDate)}',
            ),
            if (record.syncError != null)
              Text(
                record.syncError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        trailing: StatusChip(status: record.syncStatus),
      ),
    );
  }

  Widget _buildThumbnail() {
    if (record.imagePath != null) {
      return Image.file(
        File(record.imagePath!),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _placeholder(Icons.broken_image),
      );
    }
    if (record.imageUrl != null) {
      return Image.network(
        record.imageUrl!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _placeholder(Icons.cloud_off),
      );
    }
    return _placeholder(Icons.image_not_supported);
  }

  Widget _placeholder(IconData icon) {
    return Container(
      width: 56,
      height: 56,
      color: Colors.grey.shade300,
      child: Icon(icon),
    );
  }
}

class StatusChip extends StatelessWidget {
  final SyncStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case SyncStatus.pending:
        color = Colors.orange;
        label = 'Pending';
        break;
      case SyncStatus.syncing:
        color = Colors.blue;
        label = 'Syncing';
        break;
      case SyncStatus.synced:
        color = Colors.green;
        label = 'Synced';
        break;
      case SyncStatus.failed:
        color = Colors.red;
        label = 'Failed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

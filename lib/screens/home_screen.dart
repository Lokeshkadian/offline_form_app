import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/form_record.dart';
import '../providers/record_provider.dart';
import '../widgets/record_tile.dart';
import 'form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openForm({FormRecord? existing}) async {
    final provider = context.read<RecordProvider>();

    final record = await Navigator.push<FormRecord>(
      context,
      MaterialPageRoute(builder: (_) => FormScreen(record: existing)),
    );

    if (record == null) return;

    try {
      if (existing == null) {
        await provider.addRecord(record);
        _showMessage('Record saved');
      } else {
        await provider.updateRecord(record);
        _showMessage('Record updated');
      }
    } catch (e) {
      _showMessage('Could not save record: $e');
    }
  }

  Future<bool> _confirmDelete(FormRecord record) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text('"${record.fullName}" will be removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteRecord(FormRecord record) async {
    try {
      await context.read<RecordProvider>().deleteRecord(record);
      _showMessage('Record deleted');
    } catch (e) {
      _showMessage('Could not delete record: $e');
    }
  }

  Future<void> _onLongPress(FormRecord record) async {
    if (await _confirmDelete(record)) {
      await _deleteRecord(record);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _comingSoon(String feature) {
    _showMessage('$feature will be added in a later step');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordProvider>();
    final records = provider.records;

    final pendingCount = records
        .where((r) => r.syncStatus == SyncStatus.pending)
        .length;

    Widget body;
    if (provider.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (records.isEmpty) {
      body = _buildEmptyState();
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: records.length,
        itemBuilder: (context, index) => _buildRow(records[index]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Records')),
      body: Column(
        children: [
          _buildSyncBar(pendingCount),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New Record'),
      ),
    );
  }

  Widget _buildRow(FormRecord record) {
    return Dismissible(
      key: ValueKey(record.localId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(record),
      onDismissed: (_) => _deleteRecord(record),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onLongPress: () => _onLongPress(record),
        child: RecordTile(
          record: record,
          onTap: () => _openForm(existing: record),
        ),
      ),
    );
  }

  Widget _buildSyncBar(int pendingCount) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: Text('Pending: $pendingCount')),
          OutlinedButton.icon(
            onPressed: () => _comingSoon('Retry'),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Failed'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _comingSoon('Sync'),
            icon: const Icon(Icons.sync),
            label: const Text('Sync'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('No records yet. Tap "New Record" to add one.'),
        ],
      ),
    );
  }
}

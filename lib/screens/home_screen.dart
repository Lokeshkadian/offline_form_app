import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/form_record.dart';
import '../providers/record_provider.dart';
import '../providers/sync_provider.dart';
import '../services/sync_service.dart';
import '../widgets/offline_banner.dart';
import '../widgets/record_tile.dart';
import '../widgets/sync_progress_bar.dart';
import 'form_screen.dart';
import 'server_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openForm({FormRecord? existing}) async {
    if (existing != null && _blockedBySync()) return;

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
    if (_blockedBySync()) return;
    if (await _confirmDelete(record)) {
      await _deleteRecord(record);
    }
  }

  Future<void> _openServerSettings() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ServerSettingsScreen()),
    );
    if (saved == true) _showMessage('Server address saved');
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _blockedBySync() {
    if (context.read<SyncProvider>().isBusy) {
      _showMessage('Please wait until the sync finishes');
      return true;
    }
    return false;
  }

  Future<void> _syncPending() async {
    final result = await context.read<SyncProvider>().syncPending();
    _showSyncResult(result);
  }

  Future<void> _retryFailed() async {
    final result = await context.read<SyncProvider>().retryFailed();
    _showSyncResult(result);
  }

  Future<void> _refreshFromServer() async {
    final result = await context.read<SyncProvider>().refreshFromServer();
    _showSyncResult(result);
  }

  void _showSyncResult(SyncResult? result) {
    if (result == null) return;

    final parts = <String>[];
    if (result.syncedCount > 0 || result.failedCount > 0) {
      parts.add('${result.syncedCount} synced, ${result.failedCount} failed');
    }
    if (result.newFromServer > 0) {
      parts.add('${result.newFromServer} new from server');
    }
    if (result.errorMessage != null) {
      parts.add(result.errorMessage!);
    }

    _showMessage(
      parts.isEmpty ? 'Everything is up to date' : parts.join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordProvider>();
    final sync = context.watch<SyncProvider>();
    final records = provider.records;

    final pendingCount = records
        .where((r) => r.syncStatus == SyncStatus.pending)
        .length;
    final failedCount = records
        .where((r) => r.syncStatus == SyncStatus.failed)
        .length;

    Widget body;
    if (provider.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (records.isEmpty) {
      body = _buildEmptyState();
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: records.length,
        itemBuilder: (context, index) => _buildRow(records[index]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Records'),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Icons.settings),
            onPressed: _openServerSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!sync.isOnline) const OfflineBanner(),
          _buildSyncBar(sync, pendingCount, failedCount),
          if (sync.isSyncing)
            SyncProgressBar(
              completed: sync.completed,
              total: sync.total,
              percentage: sync.percentage,
              currentRecordName: sync.currentRecordName,
            ),
          Expanded(
            child: RefreshIndicator(onRefresh: _refreshFromServer, child: body),
          ),
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
      confirmDismiss: (_) async {
        if (_blockedBySync()) return false;
        return _confirmDelete(record);
      },
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

  Widget _buildSyncBar(SyncProvider sync, int pendingCount, int failedCount) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: Text('Pending: $pendingCount\nFailed: $failedCount')),
          OutlinedButton.icon(
            onPressed: sync.isBusy || failedCount == 0 ? null : _retryFailed,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Failed'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: sync.isBusy ? null : _syncPending,
            icon: const Icon(Icons.sync),
            label: const Text('Sync'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.inbox, size: 64, color: Colors.grey),
        SizedBox(height: 12),
        Center(child: Text('No records yet. Tap "New Record" to add one.')),
        SizedBox(height: 4),
        Center(
          child: Text(
            'Pull down to load records from the server.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

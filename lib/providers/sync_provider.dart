import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/form_record.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import 'record_provider.dart';

class SyncProvider extends ChangeNotifier {
  SyncProvider({
    required this.recordProvider,
    SyncService? syncService,
    ConnectivityService? connectivityService,
    DatabaseHelper? db,
  }) : _syncService = syncService ?? SyncService(),
       _connectivity = connectivityService ?? ConnectivityService(),
       _db = db ?? DatabaseHelper.instance;

  final RecordProvider recordProvider;
  final SyncService _syncService;
  final ConnectivityService _connectivity;
  final DatabaseHelper _db;

  bool _isSyncing = false;
  bool _isFetching = false;
  int _total = 0;
  int _completed = 0;
  String? _currentRecordName;

  bool? _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  Timer? _checkTimer;

  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline ?? true;
  int get total => _total;
  int get completed => _completed;
  String? get currentRecordName => _currentRecordName;

  bool get isBusy => _isSyncing || _isFetching;

  int get percentage {
    if (_total == 0) return 0;
    return (_completed * 100 / _total).round();
  }

  void startMonitoring() {
    _networkSubscription = _connectivity.onChanged.listen((_) {
      checkConnection();
    });

    _checkTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isOnline != true) checkConnection();
    });

    checkConnection();
  }

  Future<bool> checkConnection() async {
    final online = await _connectivity.isOnline();
    final cameBackOnline = online && _isOnline != true;

    if (online != _isOnline) {
      _isOnline = online;
      notifyListeners();
    }

    if (cameBackOnline) {
      await _autoSync();
    }
    return online;
  }

  Future<void> _autoSync() async {
    final pending = await _db.getPendingRecords();
    final deletes = await _db.getDeletedServerIds();
    if (pending.isNotEmpty || deletes.isNotEmpty) {
      await syncPending();
    }
  }

  void _setOffline() {
    _isOnline = false;
    notifyListeners();
  }

  Future<SyncResult?> syncPending() async {
    return _run(loadRecords: _db.getPendingRecords);
  }

  Future<SyncResult?> retryFailed() async {
    return _run(loadRecords: _db.getFailedRecords);
  }

  Future<SyncResult?> _run({
    required Future<List<FormRecord>> Function() loadRecords,
  }) async {
    if (isBusy) return null;
    _isSyncing = true;
    _total = 0;
    _completed = 0;
    _currentRecordName = null;
    notifyListeners();

    try {
      if (!await checkConnection()) {
        return SyncResult(
          errorMessage:
              'You are offline. Records are saved and will sync '
              'when you are back online.',
        );
      }

      await _syncService.syncDeletes();

      final records = await loadRecords();
      _total = records.length;
      notifyListeners();
      final result = await _syncService.syncRecords(records, _onProgress);

      if (result.errorMessage != null) {
        _setOffline();
        return result;
      }

      result.newFromServer = await _syncService.fetchAndMerge();
      return result;
    } on ApiException catch (e) {
      if (e.isConnectionError) _setOffline();
      return SyncResult(errorMessage: 'Sync stopped: ${e.message}');
    } finally {
      _isSyncing = false;
      _currentRecordName = null;
      notifyListeners();
      await recordProvider.refresh();
    }
  }

  Future<SyncResult?> refreshFromServer() async {
    if (isBusy) return null;
    _isFetching = true;
    notifyListeners();

    try {
      if (!await checkConnection()) {
        return SyncResult(errorMessage: 'You are offline — showing saved data');
      }
      await _syncService.syncDeletes();
      final added = await _syncService.fetchAndMerge();
      return SyncResult(newFromServer: added);
    } on ApiException catch (e) {
      if (e.isConnectionError) _setOffline();
      return SyncResult(errorMessage: 'Could not refresh: ${e.message}');
    } finally {
      _isFetching = false;
      notifyListeners();
      await recordProvider.refresh();
    }
  }

  Future<void> _onProgress(
    int completed,
    int total,
    String? currentName,
  ) async {
    _completed = completed;
    _total = total;
    _currentRecordName = currentName;
    notifyListeners();

    await recordProvider.refresh();
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }
}

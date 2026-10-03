import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/form_record.dart';
import 'api_service.dart';

typedef SyncProgressCallback =
    Future<void> Function(int completed, int total, String? currentName);

class SyncResult {
  int syncedCount;
  int failedCount;
  int newFromServer;
  String? errorMessage;

  SyncResult({
    this.syncedCount = 0,
    this.failedCount = 0,
    this.newFromServer = 0,
    this.errorMessage,
  });
}

class SyncService {
  SyncService({ApiService? api, DatabaseHelper? db})
    : _api = api ?? ApiService(),
      _db = db ?? DatabaseHelper.instance;

  final ApiService _api;
  final DatabaseHelper _db;

  Future<SyncResult> syncRecords(
    List<FormRecord> records,
    SyncProgressCallback onProgress,
  ) async {
    final result = SyncResult();
    final total = records.length;

    for (int i = 0; i < total; i++) {
      final record = records[i];

      await _db.markAsSyncing(record.localId);
      await onProgress(i, total, record.fullName);

      try {
        await _syncOneRecord(record);
        result.syncedCount++;
      } on ApiException catch (e) {
        await _db.markAsFailed(record.localId, e.message);
        result.failedCount++;

        if (e.isConnectionError) {
          result.errorMessage = 'Sync stopped: connection lost';
          break;
        }
      } catch (e) {
        await _db.markAsFailed(record.localId, 'Unexpected error: $e');
        result.failedCount++;
      }
    }

    await onProgress(result.syncedCount + result.failedCount, total, null);

    return result;
  }

  Future<void> _syncOneRecord(FormRecord record) async {
    String? serverId = record.serverId;

    if (serverId == null) {
      serverId = await _createOnServer(record);
    } else {
      try {
        await _api.updateRecord(serverId, record);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        serverId = await _createOnServer(record);
        record.imageUploaded = false;
      }
    }

    final imagePath = record.imagePath;
    if (!record.imageUploaded && imagePath != null) {
      final data = await _api.uploadImage(serverId, imagePath);
      await _db.markImageUploaded(record.localId, data['imageUrl'] as String?);
    }

    await _db.markAsSynced(record.localId, serverId);
  }

  Future<String> _createOnServer(FormRecord record) async {
    final data = await _api.createRecord(record);
    final serverId = data['id'].toString();
    await _db.saveServerId(record.localId, serverId);
    return serverId;
  }

  Future<void> syncDeletes() async {
    final serverIds = await _db.getDeletedServerIds();

    for (final serverId in serverIds) {
      try {
        await _api.deleteRecord(serverId);
      } on ApiException catch (e) {
        if (e.isConnectionError) rethrow;
        if (e.statusCode != 404) continue;
      }
      await _db.removeDeletedServerId(serverId);
    }
  }

  Future<int> fetchAndMerge() async {
    final serverRecords = await _api.fetchRecords();
    final deletedIds = await _db.getDeletedServerIds();
    int added = 0;

    for (final data in serverRecords) {
      final serverId = data['id'].toString();

      if (deletedIds.contains(serverId)) continue;

      final localId = data['localId'] as String?;

      FormRecord? local = await _db.getRecordByServerId(serverId);
      if (local == null && localId != null) {
        local = await _db.getRecordByLocalId(localId);
      }

      if (local == null) {
        final record = _recordFromServer(data, localId ?? const Uuid().v4());
        if (record != null) {
          await _db.insertRecord(record);
          added++;
        }
      } else if (local.syncStatus == SyncStatus.synced) {
        final record = _recordFromServer(data, local.localId);
        if (record != null) {
          record.imagePath = local.imagePath;
          record.createdAt = local.createdAt;
          await _db.updateRecord(record);
        }
      } else if (local.serverId == null) {
        await _db.saveServerId(local.localId, serverId);
      }
    }

    return added;
  }

  FormRecord? _recordFromServer(Map<String, dynamic> data, String localId) {
    String? text(String key) {
      final value = data[key];
      return value is String ? value : null;
    }

    final fullName = text('fullName');
    final mobile = text('mobile');
    final email = text('email');
    final category = text('category');
    final description = text('description');
    final visitDate = DateTime.tryParse(text('visitDate') ?? '');

    if (fullName == null ||
        mobile == null ||
        email == null ||
        category == null ||
        description == null ||
        visitDate == null) {
      return null;
    }

    final now = DateTime.now();
    return FormRecord(
      localId: localId,
      serverId: data['id'].toString(),
      fullName: fullName,
      mobile: mobile,
      email: email,
      category: category,
      description: description,
      visitDate: visitDate,
      imagePath: null,
      imageUrl: text('imageUrl'),
      imageUploaded: true,
      syncStatus: SyncStatus.synced,
      createdAt: DateTime.tryParse(text('createdAt') ?? '') ?? now,
      updatedAt: DateTime.tryParse(text('updatedAt') ?? '') ?? now,
    );
  }
}

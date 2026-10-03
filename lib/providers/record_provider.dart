import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/form_record.dart';
import '../services/image_service.dart';

class RecordProvider extends ChangeNotifier {
  RecordProvider({DatabaseHelper? db, ImageService? imageService})
    : _db = db ?? DatabaseHelper.instance,
      _imageService = imageService ?? ImageService();

  final DatabaseHelper _db;
  final ImageService _imageService;

  List<FormRecord> _records = [];
  bool _isLoading = false;

  List<FormRecord> get records => _records;
  bool get isLoading => _isLoading;

  Future<void> loadRecords() async {
    _isLoading = true;
    notifyListeners();

    await _db.resetStuckSyncing();
    await _fixImagePaths();
    _records = await _db.getAllRecords();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fixImagePaths() async {
    final all = await _db.getAllRecords();
    for (final record in all) {
      final oldPath = record.imagePath;
      if (oldPath == null) continue;

      final newPath = await _imageService.fixImagePath(oldPath);
      if (newPath != oldPath) {
        record.imagePath = newPath;
        await _db.updateRecord(record);
      }
    }
  }

  Future<void> refresh() async {
    _records = await _db.getAllRecords();
    notifyListeners();
  }

  Future<void> addRecord(FormRecord record) async {
    if (record.imagePath != null) {
      record.imagePath = await _imageService.saveImage(
        record.imagePath!,
        record.localId,
      );
    }
    await _db.insertRecord(record);
    await refresh();
  }

  Future<void> updateRecord(FormRecord record) async {
    final oldRecord = await _db.getRecordByLocalId(record.localId);

    final photoChanged =
        record.imagePath != null && record.imagePath != oldRecord?.imagePath;

    if (photoChanged) {
      record.imagePath = await _imageService.saveImage(
        record.imagePath!,
        record.localId,
      );
      await _imageService.deleteImage(oldRecord?.imagePath);
      record.imageUploaded = false;
    }

    record.syncStatus = SyncStatus.pending;
    record.syncError = null;
    record.updatedAt = DateTime.now();

    await _db.updateRecord(record);
    await refresh();
  }

  Future<void> deleteRecord(FormRecord record) async {
    _records.removeWhere((r) => r.localId == record.localId);
    notifyListeners();

    final serverId = record.serverId;
    if (serverId != null) {
      await _db.addDeletedServerId(serverId);
    }

    await _db.deleteRecord(record.localId);
    await _imageService.deleteImage(record.imagePath);
    await refresh();
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_form_app/database/database_helper.dart';
import 'package:offline_form_app/models/form_record.dart';
import 'package:offline_form_app/providers/record_provider.dart';
import 'package:offline_form_app/providers/sync_provider.dart';
import 'package:offline_form_app/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_server.dart';

DateTime _time = DateTime(2026, 1, 1);
FormRecord makeRecord(String localId, String name, {String? imagePath}) {
  _time = _time.add(const Duration(minutes: 1));
  return FormRecord(
    localId: localId,
    fullName: name,
    mobile: '9876543210',
    email: 'test@mail.com',
    category: 'Sales Visit',
    description: 'Visit notes',
    visitDate: DateTime(2026, 10, 1),
    imagePath: imagePath,
    createdAt: _time,
    updatedAt: _time,
  );
}

void main() {
  late DatabaseHelper db;
  late FakeServer server;
  late FakeConnectivity network;
  late SyncProvider sync;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    db = DatabaseHelper(
      dbFactory: databaseFactoryFfi,
      dbPath: inMemoryDatabasePath,
    );
    server = FakeServer();
    network = FakeConnectivity();
    sync = SyncProvider(
      recordProvider: RecordProvider(db: db),
      syncService: SyncService(api: server.api, db: db),
      connectivityService: network,
      db: db,
    );
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  Future<SyncStatus> statusOf(String localId) async {
    return (await db.getRecordByLocalId(localId))!.syncStatus;
  }

  test(
    'progress goes 0 to N and one failure does not stop the others',
    () async {
      await db.insertRecord(makeRecord('A', 'Asha'));
      await db.insertRecord(makeRecord('B', 'Please fail'));
      await db.insertRecord(makeRecord('C', 'Chetan'));

      final progress = <String>[];
      sync.addListener(() {
        if (sync.isSyncing && sync.total > 0) {
          progress.add('${sync.completed}/${sync.total} ${sync.percentage}%');
        }
      });

      final result = await sync.syncPending();

      expect(progress.first, '0/3 0%');
      expect(progress.last, '3/3 100%');
      expect(progress, contains('2/3 67%'));

      expect(result!.syncedCount, 2);
      expect(result.failedCount, 1);
      expect(await statusOf('A'), SyncStatus.synced);
      expect(await statusOf('B'), SyncStatus.failed);
      expect(
        await statusOf('C'),
        SyncStatus.synced,
        reason: 'C still synced after B failed',
      );

      final failed = await db.getRecordByLocalId('B');
      expect(failed!.syncError, 'Server error (500)');
      expect(sync.isSyncing, false);
    },
  );

  test('Retry Failed sends only the failed record', () async {
    await db.insertRecord(makeRecord('A', 'Asha'));
    await db.insertRecord(makeRecord('B', 'Please fail'));
    await sync.syncPending();
    server.requests.clear();

    final record = (await db.getRecordByLocalId('B'))!;
    record.fullName = 'Bala';
    await db.updateRecord(record);

    final result = await sync.retryFailed();

    expect(result!.syncedCount, 1);
    expect(result.failedCount, 0);
    expect(server.count('POST /records'), 1, reason: 'only B was sent');
    expect(await statusOf('B'), SyncStatus.synced);
  });

  test('the image is uploaded once and not again on later syncs', () async {
    final photo = File('${Directory.systemTemp.path}/sync_test_photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    await db.insertRecord(makeRecord('A', 'Asha', imagePath: photo.path));

    await sync.syncPending();
    final synced = (await db.getRecordByLocalId('A'))!;
    expect(synced.imageUploaded, true);
    expect(synced.imageUrl, '/uploads/1.jpg');

    synced.description = 'Edited';
    synced.syncStatus = SyncStatus.pending;
    await db.updateRecord(synced);
    await sync.syncPending();

    expect(server.count('PUT /records/1'), 1);
    expect(server.count('POST /records/1/image'), 1);
  });

  test('syncing the same record twice never makes a duplicate', () async {
    await db.insertRecord(makeRecord('A', 'Asha'));
    await sync.syncPending();

    final record = (await db.getRecordByLocalId('A'))!;
    record.serverId = null;
    record.syncStatus = SyncStatus.pending;
    await db.updateRecord(record);

    await sync.syncPending();
    await sync.syncPending();

    expect(server.records.length, 1);
  });

  test('a second tap on Sync while syncing is ignored', () async {
    await db.insertRecord(makeRecord('A', 'Asha'));

    final first = sync.syncPending();
    final second = await sync.syncPending();

    expect(second, isNull);
    expect((await first)!.syncedCount, 1);
    expect(server.count('POST /records'), 1);
  });

  test('server records are merged in without duplicates', () async {
    server.records['99'] = {
      'id': '99',
      'localId': 'other-phone',
      'fullName': 'From another phone',
      'mobile': '9876543210',
      'email': 'other@mail.com',
      'category': 'Inspection',
      'description': 'Remote',
      'visitDate': '2026-10-02T00:00:00.000',
      'imageUrl': '/uploads/99.jpg',
    };

    final first = await sync.refreshFromServer();
    final second = await sync.refreshFromServer();

    expect(first!.newFromServer, 1);
    expect(second!.newFromServer, 0, reason: 'second refresh adds nothing');

    final all = await db.getAllRecords();
    expect(all.length, 1);
    expect(all.single.serverId, '99');
    expect(all.single.syncStatus, SyncStatus.synced);
    expect(all.single.imageUrl, '/uploads/99.jpg');
  });

  test('unsynced local changes are not overwritten by the server', () async {
    await db.insertRecord(makeRecord('A', 'Asha'));
    await sync.syncPending();

    final local = (await db.getRecordByLocalId('A'))!;
    local.fullName = 'Asha (phone edit)';
    local.syncStatus = SyncStatus.pending;
    await db.updateRecord(local);
    server.records['1']!['fullName'] = 'Asha (server edit)';

    await sync.refreshFromServer();

    expect((await db.getRecordByLocalId('A'))!.fullName, 'Asha (phone edit)');
  });

  test(
    'a deleted record is deleted on the server and not downloaded again',
    () async {
      await db.insertRecord(makeRecord('A', 'Asha'));
      await sync.syncPending();

      final record = (await db.getRecordByLocalId('A'))!;
      await sync.recordProvider.deleteRecord(record);
      await sync.syncPending();

      expect(server.count('DELETE /records/1'), 1);
      expect(server.records, isEmpty);
      expect(await db.getAllRecords(), isEmpty);
    },
  );

  test('Sync while offline does nothing and keeps records Pending', () async {
    network.online = false;
    await db.insertRecord(makeRecord('A', 'Asha'));

    final result = await sync.syncPending();

    expect(result!.errorMessage, contains('offline'));
    expect(server.requests, isEmpty);
    expect(await statusOf('A'), SyncStatus.pending);
    expect(sync.isOnline, false);
  });

  test(
    'connection lost mid-sync stops the loop; back online syncs the rest',
    () async {
      await db.insertRecord(makeRecord('A', 'Asha'));
      await db.insertRecord(makeRecord('B', 'Bala'));
      await db.insertRecord(makeRecord('C', 'Chetan'));

      sync.addListener(() {
        if (sync.currentRecordName == 'Bala') server.connectionLost = true;
      });

      final result = await sync.syncPending();

      expect(result!.errorMessage, 'Sync stopped: connection lost');
      expect(await statusOf('A'), SyncStatus.synced);
      expect(await statusOf('B'), SyncStatus.failed);
      expect(await statusOf('C'), SyncStatus.pending, reason: 'not tried');
      expect(sync.isOnline, false);

      server.connectionLost = false;
      await sync.checkConnection();

      expect(sync.isOnline, true);
      expect(await statusOf('C'), SyncStatus.synced);
      expect(server.records.length, 2, reason: 'A and C; B waits for Retry');
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_form_app/database/database_helper.dart';
import 'package:offline_form_app/models/form_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime _time = DateTime(2026, 1, 1);
FormRecord makeRecord(String localId, {String name = 'Asha Kumar'}) {
  _time = _time.add(const Duration(minutes: 1));
  return FormRecord(
    localId: localId,
    fullName: name,
    mobile: '9876543210',
    email: 'asha@mail.com',
    category: 'Sales Visit',
    description: 'First visit',
    visitDate: DateTime(2026, 10, 1),
    createdAt: _time,
    updatedAt: _time,
  );
}

void main() {
  late DatabaseHelper db;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    db = DatabaseHelper(
      dbFactory: databaseFactoryFfi,
      dbPath: inMemoryDatabasePath,
    );
  });

  tearDown(() => db.close());

  test('insert a record and read it back with every field', () async {
    final record = makeRecord('A');
    record.imagePath = '/images/a.jpg';
    await db.insertRecord(record);

    final saved = await db.getRecordByLocalId('A');
    expect(saved, isNotNull);
    expect(saved!.fullName, 'Asha Kumar');
    expect(saved.mobile, '9876543210');
    expect(saved.visitDate, DateTime(2026, 10, 1));
    expect(saved.imagePath, '/images/a.jpg');
    expect(saved.imageUploaded, false);
    expect(saved.syncStatus, SyncStatus.pending);
    expect(saved.serverId, isNull);
  });

  test('getAllRecords returns newest first', () async {
    await db.insertRecord(makeRecord('OLD'));
    await db.insertRecord(makeRecord('NEW'));

    final all = await db.getAllRecords();
    expect(all.map((r) => r.localId), ['NEW', 'OLD']);
  });

  test('getPendingRecords and getFailedRecords filter by status', () async {
    await db.insertRecord(makeRecord('P1'));
    await db.insertRecord(makeRecord('P2'));
    await db.insertRecord(makeRecord('F1'));
    await db.markAsFailed('F1', 'Server error (500)');

    final pending = await db.getPendingRecords();
    expect(pending.map((r) => r.localId), ['P1', 'P2']);

    final failed = await db.getFailedRecords();
    expect(failed.single.localId, 'F1');
    expect(failed.single.syncError, 'Server error (500)');
  });

  test('markAsSynced saves the server ID and clears the old error', () async {
    await db.insertRecord(makeRecord('A'));
    await db.markAsFailed('A', 'Request timed out');
    await db.markAsSynced('A', 'server-1');

    final record = await db.getRecordByLocalId('A');
    expect(record!.syncStatus, SyncStatus.synced);
    expect(record.serverId, 'server-1');
    expect(record.syncError, isNull);
    expect((await db.getRecordByServerId('server-1'))!.localId, 'A');
  });

  test('markImageUploaded remembers the image is on the server', () async {
    await db.insertRecord(makeRecord('A'));
    await db.markImageUploaded('A', '/uploads/a.jpg');

    final record = await db.getRecordByLocalId('A');
    expect(record!.imageUploaded, true);
    expect(record.imageUrl, '/uploads/a.jpg');
  });

  test('updateRecord saves edited fields', () async {
    final record = makeRecord('A');
    await db.insertRecord(record);

    record.fullName = 'Asha K';
    record.description = 'Edited';
    await db.updateRecord(record);

    final saved = await db.getRecordByLocalId('A');
    expect(saved!.fullName, 'Asha K');
    expect(saved.description, 'Edited');
  });

  test('deleteRecord removes the record', () async {
    await db.insertRecord(makeRecord('A'));
    await db.deleteRecord('A');

    expect(await db.getRecordByLocalId('A'), isNull);
    expect(await db.getAllRecords(), isEmpty);
  });

  test('resetStuckSyncing puts Syncing records back to Pending', () async {
    await db.insertRecord(makeRecord('A'));
    await db.markAsSyncing('A');

    await db.resetStuckSyncing();

    expect((await db.getRecordByLocalId('A'))!.syncStatus, SyncStatus.pending);
  });

  test('deleted server IDs are stored once and can be removed', () async {
    await db.addDeletedServerId('server-1');
    await db.addDeletedServerId('server-1');
    expect(await db.getDeletedServerIds(), ['server-1']);

    await db.removeDeletedServerId('server-1');
    expect(await db.getDeletedServerIds(), isEmpty);
  });
}

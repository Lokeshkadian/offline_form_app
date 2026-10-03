# Offline-First Form App

A Flutter Android app for collecting visit records in the field, even with no internet.
Records and photos are saved on the phone first and uploaded to a REST API later with a **Sync** button. The upload shows live progress, handles failures one record at a time, and never creates duplicates on the server.

The repository has two parts:

| Folder | What it is |
| --- | --- |
| `lib/` | The Flutter app |
| `mock_server/` | A small Node.js (Express) server that acts as the REST API |

## Features

- **Form** with full name, mobile, email, category (dropdown), description, visit date (date picker) and a photo (camera or gallery). Every field is required and checked before saving.
- **Works offline.** Records and photos are saved in a local SQLite database, so add, edit and delete all work in airplane mode.
- **Records list** with a status for each record: **Pending**, **Syncing**, **Synced** or **Failed**. Failed records show their error message.
- **Sync** uploads pending records with a progress bar, for example `Syncing 3 of 10 records — 30%`, plus the name of the record being uploaded.
- **One failure doesn't stop the sync.** The failed record is marked Failed with its error, and the rest continue.
- **Retry Failed** uploads only the failed records.
- **No duplicates** on the server, even if Sync is tapped repeatedly or the app is killed mid-sync.
- **Download and merge.** Records on the server are added to the phone without duplicates. Pull down on the list to refresh.
- **Offline banner,** plus automatic sync when the connection comes back.
- **Server address can be changed in the app** (⚙️ Server settings), so one APK works on any network.

## Setup

### Requirements

- Flutter 3.44 or newer (developed with Flutter 3.44.8 and Dart 3.12)
- Node.js 18 or newer, for the mock server
- An Android emulator or an Android phone

### 1. Start the mock server

```bash
cd mock_server
npm install
npm start
```

It prints `Mock server running on http://localhost:3000`. To check it, open <http://localhost:3000/health>; it should show `{"status":"ok"}`.

### 2. Run the app

```bash
flutter pub get
flutter run
```

Or install the release APK: `build/app/outputs/flutter-apk/app-release.apk`. To build it yourself:

```bash
flutter build apk --release
```

### 3. Set the server address

The app needs the address of the computer running the mock server.

| Where the app runs | Server address |
| --- | --- |
| Android emulator | `http://10.0.2.2:3000` (the default, so nothing to change) |
| Real phone on the same Wi-Fi or hotspot as the computer | `http://<computer's IP>:3000` |
| Real phone connected by USB, after running `adb reverse tcp:3000 tcp:3000` | `http://localhost:3000` |

To change it on the phone:

1. Tap **⚙️** in the top-right corner of the records screen.
2. Enter the address, e.g. `http://192.168.1.5:3000`.
3. Tap **Test connection**. A green tick means the phone can reach the server.
4. Tap **Save**. The address is kept after the app restarts.

To find the computer's IP, run `ipconfig getifaddr en0` on macOS, or `ipconfig` on Windows and look for the IPv4 address. Some office or public Wi-Fi networks block devices from reaching each other. If **Test connection** fails there, use a phone hotspot or the USB option.

The default can also be set when building: `flutter build apk --release --dart-define=BASE_URL=http://192.168.1.5:3000`.

## How to test the main scenarios

| Scenario | Steps |
| --- | --- |
| Offline save | Turn on airplane mode. Add, edit and delete records. The offline banner shows, and the records stay **Pending**. |
| Sync with progress | Turn airplane mode off. Pending records upload automatically within a few seconds, or tap **Sync**. The progress bar shows each record. |
| Failed record | Add a record with **"fail"** in the name (e.g. "Fail Test"). Sync: that record turns **Failed** with "Server error (500)", and the others sync. |
| Retry | Edit the failed record to remove "fail", then tap **Retry Failed**. Only that record is sent. |
| No duplicates | Tap **Sync** several times, or close the app during a sync and sync again. `mock_server/db.json` has one copy of each record. |
| Large photo | Take a full-size camera photo. It is compressed to at most 1280 px at 70% quality before saving, then uploaded. |
| Merge | Add a record directly on the server (example below), then pull down on the list. It appears as **Synced**. Pull again and nothing is duplicated. |
| Connection lost mid-sync | Start the server with `DELAY_MS=3000 npm start`, add 3 records, tap **Sync** and stop the server during the second record. The sync stops with "Sync stopped: connection lost". The remaining records stay Pending and upload when the server is back. |

Adding a record directly on the server (for the merge test):

```bash
curl -H "Content-Type: application/json" \
  -d '{"localId":"web-1","fullName":"Added on server","mobile":"9876543210","email":"a@b.co","category":"Inspection","description":"Created with curl","visitDate":"2026-10-01"}' \
  http://localhost:3000/records
```

### Simulating failures

| Method | How |
| --- | --- |
| Fail one record | Put **"fail"** anywhere in its full name (any case). Create, update and image requests for it return 500. |
| Random failures | `FAIL_RATE=0.3 npm start` makes about 30% of create, update and image requests fail. |
| Server down | Stop the server with Ctrl+C. The app shows "Server unavailable / no internet" and the offline banner. |
| Slow server | `DELAY_MS=3000 npm start` waits 3 seconds before every response (default 800 ms, so the progress bar is visible). |
| Clear server data | `npm run reset` empties `db.json`. |

## Architecture

```
lib/
  main.dart                      Starts the app: loads settings and records, starts network monitoring
  models/
    form_record.dart             FormRecord + SyncStatus, and conversion to/from a database row
  database/
    database_helper.dart         All SQLite code (sqflite)
  services/
    api_service.dart             HTTP calls to the server + ApiException
    sync_service.dart            Upload loop, deletes, download and merge
    connectivity_service.dart    "Can we reach the server right now?"
    image_service.dart           Copies photos into the app's folder
    server_config.dart           Server address, saved on the phone
  providers/
    record_provider.dart         Records list for the UI: add, edit, delete
    sync_provider.dart           Sync progress, online/offline state, auto sync
  screens/
    home_screen.dart             Records list, sync buttons, progress bar, offline banner
    form_screen.dart             Add / edit form with validation
    server_settings_screen.dart  Change the server address
  widgets/
    record_tile.dart             One row in the list + status chip
    sync_progress_bar.dart       "Syncing 3 of 10 records — 30%"
    offline_banner.dart          "You are offline — showing saved data"
  utils/
    validators.dart              Form validation rules
    constants.dart               Default server address and timeouts
```

The code is split into layers:

- **Screens and widgets** only show data and react to taps. They never talk to the database or the server directly.
- **Providers** (`ChangeNotifier`) hold the state the screens show. They call `notifyListeners()` when it changes, so the screens rebuild.
- **Services** do the actual work: HTTP, syncing, photos, connectivity. They contain no UI code, which makes them easy to test.
- **DatabaseHelper** holds all the SQL in one class.

Services, providers and the database helper take their dependencies in the constructor (for example `ApiService(client: ...)` and `DatabaseHelper(dbPath: ...)`), so the tests can pass a fake server and an in-memory database.

### Design decisions

| Area | Choice | Why |
| --- | --- | --- |
| Local database | **SQLite (`sqflite`)** | Records fit naturally in a table. Simple queries like `WHERE sync_status = 'pending'` are exactly what sync needs. It's mature and well documented, and needs no code generation. |
| State management | **Provider (`ChangeNotifier`)** | Recommended by the Flutter team for apps of this size. Small amount of code, easy to follow, and easy to test without a UI. |
| HTTP | **`http` package** | The official Dart package, small and simple. `.timeout()` limits every request, `MultipartRequest` uploads photos, and `MockClient` lets tests run without a server. |
| Record IDs | **UUID v4 made on the phone (`localId`)** | The ID exists before the record ever reaches the server and never changes, so the server can use it to recognise a record it already has. |
| Connectivity | **`connectivity_plus` + a call to `/health`** | `connectivity_plus` only knows if Wi-Fi or mobile data is on. The `/health` call checks the server is actually reachable. |
| Photos | **`image_picker` (max 1280 px, 70% quality), copied into the app's documents folder** | Compression keeps uploads fast. The picker's file lives in a cache folder the system may clear, so it is copied somewhere safe. |
| Server address | **Saved with `shared_preferences`, editable in the app** | The computer's IP changes between networks, so the address shouldn't need a new APK. |
| Mock server | **Express + multer** | A plain JSON mock can't do idempotent create or multipart image upload. A small Express server can, and it adds a delay and a failure switch for testing. |

## Local database

Table `records`:

| Column | Type | Notes |
| --- | --- | --- |
| `local_id` | TEXT PRIMARY KEY | UUID made on the phone; never changes |
| `server_id` | TEXT | Server's ID; empty until the first successful upload |
| `full_name`, `mobile`, `email`, `category`, `description` | TEXT NOT NULL | Form fields |
| `visit_date` | TEXT NOT NULL | ISO-8601 |
| `image_path` | TEXT | Photo on the phone (empty for records downloaded from the server) |
| `image_url` | TEXT | Photo on the server, e.g. `/uploads/<file>.jpg` |
| `image_uploaded` | INTEGER (0/1) | 1 once the photo is on the server, so it isn't sent again |
| `sync_status` | TEXT NOT NULL | `pending`, `syncing`, `synced` or `failed` |
| `sync_error` | TEXT | Last error message, shown under the record |
| `created_at`, `updated_at` | TEXT NOT NULL | ISO-8601 |

Table `deleted_records` (`server_id TEXT PRIMARY KEY`) holds the server IDs of records deleted on the phone whose delete hasn't reached the server yet.

## Mock server API

Base URL: `http://<host>:3000`. Errors are returned as JSON: `{"error": "..."}`.

| Method | Endpoint | Description |
| --- | --- | --- |
| GET | `/health` | `{"status":"ok"}`, used for the online check |
| POST | `/records` | Create a record. **Idempotent:** if a record with the same `localId` exists, it is returned with 200 instead of creating a new one; otherwise 201. 400 if a required field is missing. |
| GET | `/records` | All records |
| GET | `/records/:id` | One record, or 404 |
| PUT | `/records/:id` | Update the form fields, or 404 |
| DELETE | `/records/:id` | Delete the record and its photo, or 404 |
| POST | `/records/:id/image` | Multipart upload, field name `image`, images only, max 10 MB. Sets `imageUrl` and returns the record. |

Record JSON:

```json
{
  "id": "6f1c…",
  "localId": "3a9e…",
  "fullName": "Asha Kumar",
  "mobile": "9876543210",
  "email": "asha@mail.com",
  "category": "Sales Visit",
  "description": "First visit",
  "visitDate": "2026-10-01T00:00:00.000",
  "imageUrl": "/uploads/6f1c…_1791028456092.jpg",
  "createdAt": "2026-10-01T10:00:00.000Z",
  "updatedAt": "2026-10-01T10:00:00.000Z"
}
```

`imageUrl` is a path, not a full address, so the same record works whichever address the phone uses. The app adds the server address in front.

## Sync flow

When **Sync** is tapped (or the app comes back online):

1. **Check the connection.** If the server can't be reached, show a message and stop. Nothing changes.
2. **Send deletes** made on the phone (`DELETE /records/:id`). A 404 counts as done.
3. **Upload each Pending record,** one at a time, oldest first:
   1. Mark it **Syncing** and update the progress bar.
   2. If it has no `server_id`, send `POST /records` and **save the returned `server_id` immediately**. Otherwise send `PUT /records/:server_id`.
   3. If the photo isn't uploaded yet, send `POST /records/:id/image`, then save `image_url` and set `image_uploaded = 1`.
   4. Mark it **Synced** and clear any old error.
   5. If any step fails, save the error message, mark it **Failed**, and **continue with the next record**.
4. **Download and merge** server records (see below).
5. **Show a summary,** for example "8 synced, 2 failed · 1 new from server".

**Retry Failed** runs the same flow for Failed records only. Sync and Retry Failed are disabled while a sync is running, so a second sync can never start at the same time. Editing and deleting are also blocked during a sync.

### Duplicate protection

1. **Stable `localId`.** Every create sends the phone's UUID. If the server already has a record with that `localId` (for example, the app was killed after the upload but before it saved the reply), it returns that record instead of creating a second one.
2. **`server_id` saved straight away.** It is saved right after the create, before the photo upload. If the photo then fails, the next sync sends a PUT, never a second POST.
3. **`image_uploaded` flag.** A retry or later edit doesn't upload the same photo again.
4. **No two syncs at once.** The sync flag is set before any waiting, so even very fast double taps start only one sync.
5. **App killed mid-sync.** Records left as Syncing are set back to Pending when the app starts. Because of points 1 and 2, sending them again is safe.

### Fetch and merge

Server records are downloaded after every sync and on pull-to-refresh. For each one, the app looks for the same record on the phone, first by `server_id`, then by `localId`:

| On the phone | Result |
| --- | --- |
| Not found | Added as **Synced**. Its photo is shown from the server. |
| Found, Synced | Replaced with the server's version; the photo saved on the phone is kept |
| Found, Pending or Failed (has changes not yet uploaded) | The phone's version is kept and uploaded by the next sync. A missing `server_id` is filled in, so that upload is a PUT. |
| Waiting to be deleted | Skipped |
| Missing required fields | Skipped, so one broken record doesn't stop the merge |

## Error handling

Every network problem is turned into an `ApiException` with a message the user can understand:

| Problem | Message shown |
| --- | --- |
| No response in time (15 s; 30 s for photo uploads; 5 s for the online check) | Request timed out |
| No network, wrong address, server stopped | Server unavailable / no internet |
| 404 | Record not found on server (404) |
| Other 4xx | Request rejected by server (4xx) |
| 5xx | Server error (5xx) |
| Reply isn't JSON, or a record without an `id` | Invalid server response |
| Photo file deleted from the phone | Image file not found on phone |

Special cases:

- **A PUT returns 404** (the server lost the record, e.g. after `npm run reset`): the record is created again, with its photo.
- **Connection lost during a sync:** the current record is marked Failed, the loop **stops**, and the remaining records stay Pending. The offline banner appears, with the message "Sync stopped: connection lost". The remaining records upload automatically when the connection returns.

## Offline behaviour

- Saving, editing and deleting only use the local database, so they always work offline.
- The list always shows the records saved on the phone. When the server can't be reached, a banner says **"You are offline — showing saved data"**.
- The app listens for network changes, such as airplane mode turning on or off, with `connectivity_plus`. While offline, it also checks the server every 10 seconds, so it notices when a stopped server starts again.
- When the connection comes back (or the app opens online), Pending records and deletes are uploaded automatically.
- Tapping **Sync** while offline shows a message and changes nothing.
- A record deleted while offline is remembered and deleted on the server at the next sync. It is not downloaded again in the meantime.

## Tests

```bash
flutter test
```

37 tests, none of which need a phone, a server or the internet:

| File | What it covers |
| --- | --- |
| `test/validators_test.dart` | Every form validation rule, plus a widget test: tapping **Save** on an empty form shows all 7 error messages |
| `test/database_test.dart` | Insert and read back, newest-first order, Pending/Failed queries, mark synced/failed, photo flag, update, delete, resetting stuck Syncing records, delete queue. Uses an in-memory SQLite database (`sqflite_common_ffi`). |
| `test/api_service_test.dart` | Request format, the friendly error message for each problem (500, 404, 400, no connection, timeout, invalid reply), missing photo file. Uses `MockClient`. |
| `test/sync_provider_test.dart` | Progress goes 0 → N; one failure doesn't stop the others; Retry sends only failed records; the photo is uploaded once; no duplicates after a repeated or interrupted sync; a second tap is ignored; merge without duplicates; local changes win; deletes reach the server; offline Sync does nothing; connection lost mid-sync stops and resumes. Uses a fake in-memory server (`test/helpers/fake_server.dart`). |

## Known limitations

- **No login.** Anyone who can reach the server can read and change all records.
- **Simple conflict rule.** If a record is changed on the phone and on the server, the phone's unsynced change wins. There is no field-by-field merge.
- **Deletes on the server aren't pulled down.** A record deleted directly on the server stays on phones that already have it.
- **Progress counts records, not bytes.** A large photo shows as one step.
- **Photos downloaded from the server need a connection to display.** Only records created on the phone keep a local copy of their photo.
- **The mock server is for testing only.** It is single-user, stores data in one JSON file, and uses plain HTTP, which is why Android cleartext traffic is enabled.
- **Some networks block the phone from reaching the computer.** Office and public Wi-Fi often do. Use a hotspot or `adb reverse` instead.

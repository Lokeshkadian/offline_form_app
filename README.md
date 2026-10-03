# Offline Form App

Flutter app for filling a visit form offline and syncing it to a server later.

Records and photos are saved on the phone first (SQLite). When you tap Sync, they are uploaded to a small Node.js mock server. Each record shows its status: Pending, Syncing, Synced or Failed.

## Features

- Form with name, mobile, email, category, description, visit date and photo (camera or gallery), with validation
- Works in airplane mode: add, edit and delete are all local
- Sync button with progress (`Syncing 3 of 10 records — 30%`)
- If one record fails, it is marked Failed with the error and the rest continue
- Retry Failed button sends only the failed records
- No duplicate records on the server
- Downloads records from the server and merges them (pull down to refresh)
- Offline banner, and auto sync when the internet comes back
- Server address can be changed inside the app

## How to run

You need Flutter (3.44+) and Node.js (18+).

Start the mock server:

```bash
cd mock_server
npm install
npm start
```

Run the app:

```bash
flutter pub get
flutter run
```

Or install the APK from `build/app/outputs/flutter-apk/app-release.apk` (build it with `flutter build apk --release`).

### Server address

On the Android emulator it works without any change (`http://10.0.2.2:3000`).

On a real phone, the phone and the computer must be on the same Wi-Fi or hotspot. Then:

1. Find the computer's IP (`ipconfig getifaddr en0` on Mac, `ipconfig` on Windows).
2. In the app, tap the gear icon (top right).
3. Enter `http://<your-ip>:3000`, tap Test connection, then Save.

If Test connection fails, the network may be blocking devices from talking to each other (common on office Wi-Fi). A mobile hotspot usually works.

## Testing failures

- Put "fail" in a record's name, and the server returns an error for it. Good for testing Failed and Retry.
- `FAIL_RATE=0.3 npm start` makes about 30% of requests fail.
- `DELAY_MS=3000 npm start` slows the server down so the progress bar is easy to see (default is 800 ms).
- Stop the server to test the offline banner and auto sync.
- `npm run reset` clears all server data.

## Tech choices

- **sqflite** for the local database. The data is a simple table, and queries like "get all pending records" are easy in SQL.
- **Provider** for state management. It's simple and enough for an app this size.
- **http** for API calls, with `.timeout()` on each request and `MultipartRequest` for photo upload.
- **uuid** to give each record an ID on the phone (`localId`) that never changes.
- **connectivity_plus** plus a call to the server's `/health` endpoint, because Wi-Fi being on doesn't mean the server is reachable.
- **image_picker** with compression (max 1280 px, 70% quality). The photo is copied into the app's folder so it isn't lost from the cache.
- **Express + multer** for the mock server. json-server can't handle the image upload or check for duplicates.

## How sync works

For each pending record:

1. Mark it Syncing.
2. If it has no server ID, `POST /records`, and save the server ID right away. Otherwise `PUT /records/:id`.
3. Upload the photo if it isn't uploaded yet.
4. Mark it Synced. If anything fails, save the error, mark it Failed and move on to the next record.

After uploading, the app downloads all server records and merges them. A record that exists only on the server is added. A synced record is updated from the server. A record with local changes not yet uploaded keeps the local version.

Deleting a record that is already on the server deletes it there on the next sync.

### Avoiding duplicates

- Every record is sent with its `localId`. If the server already has that `localId`, it returns the existing record instead of creating a new one. This covers the case where the app is closed in the middle of a sync.
- The server ID is saved straight after the record is created, so the next sync uses PUT, not POST.
- An `image_uploaded` flag stops the same photo being uploaded twice.
- Sync can't run twice at the same time. The buttons are disabled while it runs.

### Errors and offline

- Every request has a timeout: 15 s, or 30 s for photo uploads.
- Errors are shown as simple messages, e.g. "Request timed out", "Server unavailable / no internet", "Server error (500)".
- If the connection is lost during a sync, the sync stops and the remaining records stay Pending. They upload automatically when the connection is back.
- When offline, the app shows the saved records with a banner. Tapping Sync just shows a message.

## API (mock server)

| Method | Endpoint | |
| --- | --- | --- |
| GET | /health | server check |
| POST | /records | create (returns the existing record if the `localId` is already there) |
| GET | /records | all records |
| GET | /records/:id | one record |
| PUT | /records/:id | update |
| DELETE | /records/:id | delete |
| POST | /records/:id/image | upload photo (multipart, field `image`) |

## Project structure

```
lib/
  models/        FormRecord
  database/      SQLite code
  services/      API, sync, connectivity, images, server address
  providers/     RecordProvider, SyncProvider
  screens/       home, form, server settings
  widgets/       list row, progress bar, offline banner
  utils/         validators, constants
mock_server/     Express server
test/            tests
```

## Tests

```bash
flutter test
```

- `validators_test.dart`: form validation, and a widget test that taps Save on an empty form
- `database_test.dart`: insert, update, delete and status changes (in-memory SQLite)
- `api_service_test.dart`: error handling, using `MockClient`
- `sync_provider_test.dart`: progress, failure in the middle, retry, no duplicates, merge, offline. Uses a fake server.

## Limitations

- No login.
- If the same record is changed on the phone and on the server, the phone's change wins.
- Records deleted directly on the server are not removed from phones.
- Progress counts records, not upload bytes.
- The mock server is only for testing (one JSON file, plain HTTP).

// Mock REST API for the offline form app.
// Start it with: npm start
//
// Settings (environment variables):
//   PORT       port to listen on (default 3000)
//   DELAY_MS   wait this long before answering, so the app's progress bar
//              is visible (default 800)
//   FAIL_RATE  chance from 0 to 1 that a create/update/image request fails
//              with a 500 error, e.g. FAIL_RATE=0.3 fails about 30% (default 0)
//
// Any record whose fullName contains "fail" (any case) always gets a 500,
// so you can test Failed and Retry on purpose.

const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = Number(process.env.PORT) || 3000;
const DELAY_MS = Number(process.env.DELAY_MS ?? 800);
const FAIL_RATE = Number(process.env.FAIL_RATE ?? 0);

const DB_FILE = path.join(__dirname, 'db.json');
const UPLOADS_DIR = path.join(__dirname, 'uploads');

// Fields the app must send when creating a record.
const REQUIRED_FIELDS = [
  'localId',
  'fullName',
  'mobile',
  'email',
  'category',
  'description',
  'visitDate',
];

// Fields the app is allowed to change with PUT.
// id, localId, imageUrl and createdAt are never changed by PUT.
const EDITABLE_FIELDS = [
  'fullName',
  'mobile',
  'email',
  'category',
  'description',
  'visitDate',
];

// ---------- Saving data in db.json ----------

// Read all records from the file. If the file is missing or broken,
// start with an empty list instead of crashing.
function loadRecords() {
  try {
    const data = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
    return Array.isArray(data.records) ? data.records : [];
  } catch (error) {
    return [];
  }
}

function saveRecords(records) {
  fs.writeFileSync(DB_FILE, JSON.stringify({ records }, null, 2) + '\n');
}

// Delete an uploaded image file, ignoring errors if it is already gone.
// imageUrl looks like "/uploads/abc.jpg".
function deleteImageFile(imageUrl) {
  if (!imageUrl) return;
  const filePath = path.join(UPLOADS_DIR, path.basename(imageUrl));
  fs.rm(filePath, { force: true }, () => {});
}

// ---------- Failure simulation ----------

// Returns true if this request should fail on purpose.
function shouldFail(fullName) {
  if (typeof fullName === 'string' && fullName.toLowerCase().includes('fail')) {
    return true;
  }
  return Math.random() < FAIL_RATE;
}

function sendSimulatedFailure(res) {
  res.status(500).json({ error: 'Simulated server failure' });
}

// ---------- App setup ----------

fs.mkdirSync(UPLOADS_DIR, { recursive: true });

const app = express();
app.use(express.json());

// Log every request, so you can watch the app sync in the terminal.
app.use((req, res, next) => {
  console.log(`${new Date().toLocaleTimeString()}  ${req.method} ${req.url}`);
  next();
});

// Slow down every request except /health, so the progress bar is visible.
// /health stays fast because the app uses it to check if it is online.
app.use((req, res, next) => {
  if (req.path === '/health' || DELAY_MS <= 0) return next();
  setTimeout(next, DELAY_MS);
});

// Uploaded images can be opened at http://<server>/uploads/<file name>
app.use('/uploads', express.static(UPLOADS_DIR));

// Image uploads: saved in uploads/, max 10 MB, images only.
const upload = multer({
  storage: multer.diskStorage({
    destination: UPLOADS_DIR,
    filename: (req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
      cb(null, `${req.params.id}_${Date.now()}${ext}`);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    // Some phones send photos as application/octet-stream,
    // so also accept common image file extensions.
    const isImage =
      file.mimetype.startsWith('image/') ||
      /\.(jpe?g|png|gif|webp|heic)$/i.test(file.originalname);
    cb(null, isImage);
  },
});

// ---------- Routes ----------

// Health check: lets the app know the server is reachable.
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Create a record.
// Idempotent: if a record with the same localId already exists, return it
// with 200 instead of creating a duplicate. This is what stops duplicates
// when the app sends the same record twice (e.g. it was killed mid-sync).
app.post('/records', (req, res) => {
  const body = req.body || {};

  const missing = REQUIRED_FIELDS.filter(
    (field) => typeof body[field] !== 'string' || body[field].trim() === '',
  );
  if (missing.length > 0) {
    return res
      .status(400)
      .json({ error: `Missing required fields: ${missing.join(', ')}` });
  }

  if (shouldFail(body.fullName)) return sendSimulatedFailure(res);

  const records = loadRecords();
  const existing = records.find((record) => record.localId === body.localId);
  if (existing) {
    return res.status(200).json(existing);
  }

  const now = new Date().toISOString();
  const record = {
    id: crypto.randomUUID(),
    localId: body.localId,
    fullName: body.fullName,
    mobile: body.mobile,
    email: body.email,
    category: body.category,
    description: body.description,
    visitDate: body.visitDate,
    imageUrl: null,
    createdAt: body.createdAt || now,
    updatedAt: now,
  };
  records.push(record);
  saveRecords(records);
  res.status(201).json(record);
});

// All records.
app.get('/records', (req, res) => {
  res.json(loadRecords());
});

// One record.
app.get('/records/:id', (req, res) => {
  const record = loadRecords().find((r) => r.id === req.params.id);
  if (!record) return res.status(404).json({ error: 'Record not found' });
  res.json(record);
});

// Update a record. Only the editable fields that were sent are changed.
app.put('/records/:id', (req, res) => {
  const body = req.body || {};
  const records = loadRecords();
  const record = records.find((r) => r.id === req.params.id);
  if (!record) return res.status(404).json({ error: 'Record not found' });

  if (shouldFail(body.fullName ?? record.fullName)) {
    return sendSimulatedFailure(res);
  }

  for (const field of EDITABLE_FIELDS) {
    if (body[field] !== undefined) {
      record[field] = body[field];
    }
  }
  record.updatedAt = new Date().toISOString();
  saveRecords(records);
  res.json(record);
});

// Delete a record and its image file.
app.delete('/records/:id', (req, res) => {
  const records = loadRecords();
  const index = records.findIndex((r) => r.id === req.params.id);
  if (index === -1) return res.status(404).json({ error: 'Record not found' });

  const [removed] = records.splice(index, 1);
  saveRecords(records);
  deleteImageFile(removed.imageUrl);
  res.json({ message: 'Record deleted', id: removed.id });
});

// Upload the image for a record. The file must be in a field named "image".
app.post('/records/:id/image', upload.single('image'), (req, res) => {
  const records = loadRecords();
  const record = records.find((r) => r.id === req.params.id);

  // multer already saved the file, so remove it if we can't use it.
  if (!record) {
    if (req.file) fs.rm(req.file.path, { force: true }, () => {});
    return res.status(404).json({ error: 'Record not found' });
  }
  if (!req.file) {
    return res
      .status(400)
      .json({ error: 'No image received (send an image file in a field named "image")' });
  }
  if (shouldFail(record.fullName)) {
    fs.rm(req.file.path, { force: true }, () => {});
    return sendSimulatedFailure(res);
  }

  // Replace the old image if this record already had one.
  deleteImageFile(record.imageUrl);

  // Saved as a path like "/uploads/abc.jpg". The app adds its own base URL,
  // so the same record works from the emulator and from a real phone.
  record.imageUrl = `/uploads/${req.file.filename}`;
  record.updatedAt = new Date().toISOString();
  saveRecords(records);
  res.json(record);
});

// Unknown address.
app.use((req, res) => {
  res.status(404).json({ error: `Not found: ${req.method} ${req.path}` });
});

// Errors: broken JSON, image too big, or anything unexpected.
// Always answer with JSON so the app can read the error.
app.use((err, req, res, next) => {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Body is not valid JSON' });
  }
  if (err instanceof multer.MulterError) {
    const message =
      err.code === 'LIMIT_FILE_SIZE' ? 'Image is larger than 10 MB' : err.message;
    return res.status(400).json({ error: message });
  }
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

// '0.0.0.0' accepts connections from other devices on the Wi-Fi,
// not only from this computer, so a real phone can reach it.
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Mock server running on http://localhost:${PORT}`);
  console.log(`Android emulator: http://10.0.2.2:${PORT}`);
  console.log(`DELAY_MS=${DELAY_MS}  FAIL_RATE=${FAIL_RATE}`);
});

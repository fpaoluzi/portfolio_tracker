// ============================================
// FILE UPLOAD CONFIGURATION
// Multer settings for Excel file uploads
// ============================================

const multer = require('multer');

// Configurazione Multer per upload file Excel
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB max
  fileFilter: (req, file, cb) => {
    if (
      file.mimetype === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
      file.mimetype === 'application/vnd.ms-excel'
    ) {
      cb(null, true);
    } else {
      cb(new Error('Solo file Excel (.xlsx, .xls) sono permessi'));
    }
  },
});

module.exports = upload;

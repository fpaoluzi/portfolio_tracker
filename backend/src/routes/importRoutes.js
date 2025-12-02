// ============================================
// IMPORT ROUTES
// ============================================

const express = require('express');
const upload = require('../config/upload');
const { importExcel } = require('../controllers/importController');

const router = express.Router();

// Import transactions from Excel file
router.post('/excel', upload.single('file'), importExcel);

module.exports = router;


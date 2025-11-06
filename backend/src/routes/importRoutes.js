// ============================================
// IMPORT ROUTES
// ============================================

const express = require('express');
const upload = require('../config/upload');

const router = express.Router();

// Placeholder - importController will be created
router.post('/excel', upload.single('file'), async (req, res) => {
  res.status(501).json({ error: 'Import controller in development' });
});

module.exports = router;

// ============================================
// ROUTES INDEX
// Central route registration
// ============================================

const express = require('express');
const portfolioRoutes = require('./portfolioRoutes');
const assetRoutes = require('./assetRoutes');
const transactionRoutes = require('./transactionRoutes');
const targetAllocationRoutes = require('./targetAllocationRoutes');
const priceUpdateRoutes = require('./priceUpdateRoutes');
const importRoutes = require('./importRoutes');
const performanceRoutes = require('./performanceRoutes');
const etfCompositionRoutes = require('./etfCompositionRoutes');
const compositionAnalysisRoutes = require('./compositionAnalysisRoutes');

const router = express.Router();

// Health check endpoint
router.get('/health', async (req, res) => {
  const pool = require('../config/database');
  try {
    const result = await pool.query('SELECT NOW()');
    res.json({
      status: 'ok',
      database: 'connected',
      timestamp: result.rows[0].now,
    });
  } catch (err) {
    res.status(500).json({
      status: 'error',
      database: 'disconnected',
      error: err.message,
    });
  }
});

// Register all routes
router.use('/portfolios', portfolioRoutes);
router.use('/assets', assetRoutes);
router.use('/transactions', transactionRoutes);
router.use('/target-allocations', targetAllocationRoutes);
router.use('/portfolios', priceUpdateRoutes); // Price updates routes
router.use('/import', importRoutes);
router.use('/portfolios', performanceRoutes); // Performance routes
router.use('/etf-composition', etfCompositionRoutes); // ETF composition routes (scraping, bulk operations)
router.use('/composition', compositionAnalysisRoutes); // Composition analysis routes (modular with look-through)

module.exports = router;

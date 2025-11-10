// ============================================
// ETF COMPOSITION ROUTES
// API endpoints for ETF composition data
// ============================================

const express = require('express');
const router = express.Router();
const {
  getCompositionByAsset,
  fetchAndSaveComposition,
  bulkUpdateCompositions,
  deleteCompositionByAsset,
  saveManualComposition,
} = require('../controllers/etfCompositionController');

// Get composition data for a single asset
router.get('/asset/:assetId', getCompositionByAsset);

// Fetch and save composition data from Yahoo Finance
router.post('/asset/:assetId/fetch', fetchAndSaveComposition);

// Save manually entered composition data
router.post('/asset/:assetId/manual', saveManualComposition);

// Delete composition data for a single asset
router.delete('/asset/:assetId', deleteCompositionByAsset);

// Bulk update compositions for all assets (fire-and-forget)
router.post('/bulk-update', bulkUpdateCompositions);

// ============================================
// DEPRECATED ROUTES (Removed - Use Modular API Instead)
// ============================================
// The following routes have been replaced with modular composition analysis endpoints.
// Instead of getting all composition data at once, use specific endpoints:
//
// For portfolio analysis, use:
//   GET /api/composition/holdings/portfolio/:portfolioId
//   GET /api/composition/sectors/portfolio/:portfolioId
//   GET /api/composition/geographic/portfolio/:portfolioId
//   GET /api/composition/allocation/portfolio/:portfolioId
//   GET /api/composition/bond-ratings/portfolio/:portfolioId (bonds only)
//   GET /api/composition/bond-maturity/portfolio/:portfolioId (bonds only)
//
// For multiple portfolios, use:
//   GET /api/composition/holdings/portfolios/multiple?portfolioIds=1,2,3
//   GET /api/composition/sectors/portfolios/multiple?portfolioIds=1,2,3
//   GET /api/composition/geographic/portfolios/multiple?portfolioIds=1,2,3
//   GET /api/composition/allocation/portfolios/multiple?portfolioIds=1,2,3
//   GET /api/composition/bond-ratings/portfolios/multiple?portfolioIds=1,2,3
//   GET /api/composition/bond-maturity/portfolios/multiple?portfolioIds=1,2,3
//
// For multiple assets, use:
//   GET /api/composition/holdings/assets/multiple?assetIds=1,2,3&portfolioId=1
//   GET /api/composition/sectors/assets/multiple?assetIds=1,2,3
//   GET /api/composition/geographic/assets/multiple?assetIds=1,2,3
//   GET /api/composition/allocation/assets/multiple?assetIds=1,2,3
//   GET /api/composition/bond-ratings/assets/multiple?assetIds=1,2,3
//   GET /api/composition/bond-maturity/assets/multiple?assetIds=1,2,3
//
// See compositionAnalysisRoutes.js for the complete modular API documentation.
// ============================================

module.exports = router;

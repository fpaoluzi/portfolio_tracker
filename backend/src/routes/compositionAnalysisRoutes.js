// ============================================
// COMPOSITION ANALYSIS ROUTES
// API endpoints modulari per analisi di composizione ETF/Fondi
// con calcolo look-through corretto
// ============================================

const express = require('express');
const router = express.Router();

// Import moduli di analisi
const holdingsAnalysis = require('../controllers/composition/holdingsAnalysis');
const sectorAnalysis = require('../controllers/composition/sectorAnalysis');
const geographicAnalysis = require('../controllers/composition/geographicAnalysis');
const allocationAnalysis = require('../controllers/composition/allocationAnalysis');
const bondRatingAnalysis = require('../controllers/composition/bondRatingAnalysis');
const bondMaturityAnalysis = require('../controllers/composition/bondMaturityAnalysis');
const riskStatsAnalysis = require('../controllers/composition/riskStatsAnalysis');

// ============================================
// HOLDINGS ANALYSIS (Top Holdings)
// ============================================

// GET /api/composition/holdings/asset/:assetId
router.get('/holdings/asset/:assetId', holdingsAnalysis.getHoldingsByAsset);

// GET /api/composition/holdings/portfolio/:portfolioId
router.get('/holdings/portfolio/:portfolioId', holdingsAnalysis.getHoldingsByPortfolio);

// GET /api/composition/holdings/portfolios/multiple?portfolioIds=1,2,3
router.get('/holdings/portfolios/multiple', holdingsAnalysis.getHoldingsByMultiplePortfolios);

// GET /api/composition/holdings/assets/multiple?assetIds=1,2,3&portfolioId=1
router.get('/holdings/assets/multiple', holdingsAnalysis.getHoldingsByMultipleAssets);

// POST /api/composition/holdings/asset/:assetId
router.post('/holdings/asset/:assetId', holdingsAnalysis.saveManualHoldings);

// DELETE /api/composition/holdings/asset/:assetId
router.delete('/holdings/asset/:assetId', holdingsAnalysis.deleteHoldingsByAsset);

// GET /api/composition/holdings/detail?portfolioId=1&holdingSymbol=AAPL
router.get('/holdings/detail', holdingsAnalysis.getHoldingDetail);

// ============================================
// SECTOR ANALYSIS (Settori)
// ============================================

// GET /api/composition/sectors/asset/:assetId
router.get('/sectors/asset/:assetId', sectorAnalysis.getSectorsByAsset);

// GET /api/composition/sectors/portfolio/:portfolioId
router.get('/sectors/portfolio/:portfolioId', sectorAnalysis.getSectorsByPortfolio);

// GET /api/composition/sectors/portfolios/multiple?portfolioIds=1,2,3
router.get('/sectors/portfolios/multiple', sectorAnalysis.getSectorsByMultiplePortfolios);

// GET /api/composition/sectors/assets/multiple?assetIds=1,2,3&portfolioId=1
router.get('/sectors/assets/multiple', sectorAnalysis.getSectorsByMultipleAssets);

// POST /api/composition/sectors/asset/:assetId
router.post('/sectors/asset/:assetId', sectorAnalysis.saveManualSectors);

// DELETE /api/composition/sectors/asset/:assetId
router.delete('/sectors/asset/:assetId', sectorAnalysis.deleteSectorsByAsset);

// GET /api/composition/sectors/detail?portfolioId=1&sectorName=Technology
router.get('/sectors/detail', sectorAnalysis.getSectorDetail);

// ============================================
// GEOGRAPHIC ANALYSIS (Aree geografiche)
// ============================================

// GET /api/composition/geographic/asset/:assetId
router.get('/geographic/asset/:assetId', geographicAnalysis.getGeographicByAsset);

// GET /api/composition/geographic/portfolio/:portfolioId
router.get('/geographic/portfolio/:portfolioId', geographicAnalysis.getGeographicByPortfolio);

// GET /api/composition/geographic/portfolios/multiple?portfolioIds=1,2,3
router.get('/geographic/portfolios/multiple', geographicAnalysis.getGeographicByMultiplePortfolios);

// GET /api/composition/geographic/assets/multiple?assetIds=1,2,3&portfolioId=1
router.get('/geographic/assets/multiple', geographicAnalysis.getGeographicByMultipleAssets);

// POST /api/composition/geographic/asset/:assetId
router.post('/geographic/asset/:assetId', geographicAnalysis.saveManualGeographic);

// DELETE /api/composition/geographic/asset/:assetId
router.delete('/geographic/asset/:assetId', geographicAnalysis.deleteGeographicByAsset);

// GET /api/composition/geographic/detail?portfolioId=1&regionName=Stati Uniti
router.get('/geographic/detail', geographicAnalysis.getRegionDetail);

// ============================================
// ALLOCATION ANALYSIS (Stocks/Bonds/Cash)
// ============================================

// GET /api/composition/allocation/asset/:assetId
router.get('/allocation/asset/:assetId', allocationAnalysis.getAllocationByAsset);

// GET /api/composition/allocation/portfolio/:portfolioId
router.get('/allocation/portfolio/:portfolioId', allocationAnalysis.getAllocationByPortfolio);

// GET /api/composition/allocation/portfolios/multiple?portfolioIds=1,2,3
router.get('/allocation/portfolios/multiple', allocationAnalysis.getAllocationByMultiplePortfolios);

// GET /api/composition/allocation/assets/multiple?assetIds=1,2,3&portfolioId=1
router.get('/allocation/assets/multiple', allocationAnalysis.getAllocationByMultipleAssets);

// POST /api/composition/allocation/asset/:assetId
router.post('/allocation/asset/:assetId', allocationAnalysis.saveManualAllocation);

// DELETE /api/composition/allocation/asset/:assetId
router.delete('/allocation/asset/:assetId', allocationAnalysis.deleteAllocationByAsset);

// ============================================
// BOND RATING ANALYSIS (AAA, AA, A, BBB, etc.)
// SOLO PER OBBLIGAZIONI
// ============================================

// GET /api/composition/bond-ratings/asset/:assetId
router.get('/bond-ratings/asset/:assetId', bondRatingAnalysis.getBondRatingsByAsset);

// GET /api/composition/bond-ratings/portfolio/:portfolioId
router.get('/bond-ratings/portfolio/:portfolioId', bondRatingAnalysis.getBondRatingsByPortfolio);

// GET /api/composition/bond-ratings/portfolios/multiple?portfolioIds=1,2,3
router.get('/bond-ratings/portfolios/multiple', bondRatingAnalysis.getBondRatingsByMultiplePortfolios);

// GET /api/composition/bond-ratings/assets/multiple?assetIds=1,2,3&portfolioId=1
router.get('/bond-ratings/assets/multiple', bondRatingAnalysis.getBondRatingsByMultipleAssets);

// POST /api/composition/bond-ratings/asset/:assetId
router.post('/bond-ratings/asset/:assetId', bondRatingAnalysis.saveManualBondRatings);

// DELETE /api/composition/bond-ratings/asset/:assetId
router.delete('/bond-ratings/asset/:assetId', bondRatingAnalysis.deleteBondRatingsByAsset);

// ============================================
// BOND MATURITY ANALYSIS (0-1y, 1-3y, 3-5y, etc.)
// SOLO PER OBBLIGAZIONI
// ============================================

// GET /api/composition/bond-maturity/asset/:assetId
router.get('/bond-maturity/asset/:assetId', bondMaturityAnalysis.getBondMaturityByAsset);

// GET /api/composition/bond-maturity/portfolio/:portfolioId
router.get('/bond-maturity/portfolio/:portfolioId', bondMaturityAnalysis.getBondMaturityByPortfolio);

// GET /api/composition/bond-maturity/portfolios/multiple?portfolioIds=1,2,3
router.get('/bond-maturity/portfolios/multiple', bondMaturityAnalysis.getBondMaturityByMultiplePortfolios);

// GET /api/composition/bond-maturity/assets/multiple?assetIds=1,2,3&portfolioId=1
router.get('/bond-maturity/assets/multiple', bondMaturityAnalysis.getBondMaturityByMultipleAssets);

// POST /api/composition/bond-maturity/asset/:assetId
router.post('/bond-maturity/asset/:assetId', bondMaturityAnalysis.saveManualBondMaturity);

// DELETE /api/composition/bond-maturity/asset/:assetId
router.delete('/bond-maturity/asset/:assetId', bondMaturityAnalysis.deleteBondMaturityByAsset);

// ============================================
// RISK STATS ANALYSIS (ISR, Deviazione Standard, Sharpe Ratio)
// ============================================

// GET /api/composition/risk-stats/portfolio/:portfolioId
router.get('/risk-stats/portfolio/:portfolioId', riskStatsAnalysis.getRiskStatsByPortfolio);

// GET /api/composition/risk-stats/assets/multiple?assetIds=1,2,3&portfolioId=1
router.get('/risk-stats/assets/multiple', riskStatsAnalysis.getRiskStatsByMultipleAssets);

module.exports = router;

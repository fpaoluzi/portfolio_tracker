// ============================================
// PORTFOLIO ROUTES
// ============================================

const express = require('express');
const {
  getAllPortfolios,
  getPortfolioById,
  createPortfolio,
  updatePortfolio,
  deletePortfolio,
  getPortfolioPerformance,
  getPortfolioAllocation,
  getPortfolioSnapshots,
} = require('../controllers/portfolioController');
const { getPortfolioPositions } = require('../controllers/positionController');
const { getPortfolioTransactions } = require('../controllers/transactionController');

const router = express.Router();

router.get('/', getAllPortfolios);
router.get('/:id', getPortfolioById);
router.post('/', createPortfolio);
router.put('/:id', updatePortfolio);
router.delete('/:id', deletePortfolio);

router.get('/:id/performance', getPortfolioPerformance);
router.get('/:id/allocation', getPortfolioAllocation);
router.get('/:id/snapshots', getPortfolioSnapshots);
router.get('/:id/positions', getPortfolioPositions);
router.get('/:id/transactions', getPortfolioTransactions);

module.exports = router;

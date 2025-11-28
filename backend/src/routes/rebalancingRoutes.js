// ============================================
// REBALANCING ROUTES
// Routes for allocation category management and rebalancing simulations
// ============================================

const express = require('express');
const {
    getCategories,
    createCategory,
    updateCategory,
    deleteCategory,
    getDriftAnalysis,
    getSmartDeposit,
    getSimulateTransaction,
} = require('../controllers/rebalancingController');

const router = express.Router();

// Category Management
router.get('/:portfolioId/categories', getCategories);
router.post('/:portfolioId/categories', createCategory);
router.put('/:portfolioId/categories/:categoryId', updateCategory);
router.delete('/:portfolioId/categories/:categoryId', deleteCategory);

// Simulation & Analysis (Read-only)
router.get('/:portfolioId/drift-analysis', getDriftAnalysis);
router.post('/:portfolioId/smart-deposit', getSmartDeposit);
router.post('/:portfolioId/simulate-transaction', getSimulateTransaction);

module.exports = router;

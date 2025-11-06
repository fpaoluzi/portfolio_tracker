// ============================================
// PRICE UPDATE ROUTES
// ============================================

const express = require('express');
const { updatePortfolioPrices } = require('../controllers/priceUpdateController');

const router = express.Router();

router.post('/:id/update-prices', updatePortfolioPrices);

module.exports = router;

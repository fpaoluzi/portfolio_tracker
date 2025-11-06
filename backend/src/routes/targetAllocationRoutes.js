// ============================================
// TARGET ALLOCATION ROUTES
// ============================================

const express = require('express');
const {
  getTargetAllocation,
  createTargetAllocation,
  updateTargetAllocation,
} = require('../controllers/targetAllocationController');

const router = express.Router();

router.get('/:portfolioId', getTargetAllocation);
router.post('/', createTargetAllocation);
router.put('/:id', updateTargetAllocation);

module.exports = router;

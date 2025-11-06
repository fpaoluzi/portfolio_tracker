// ============================================
// PERFORMANCE ROUTES
// ============================================

const express = require('express');
const {
  getMonthlyPerformanceLive,
  getMonthlyPerformance,
  getMonthlyPerformanceAggregate,
  calculateMonthlyPerformance,
} = require('../controllers/performanceController');

const router = express.Router();

router.get('/:id/monthly-performance-live', getMonthlyPerformanceLive);
router.post('/:id/calculate-monthly-performance', calculateMonthlyPerformance);
router.get('/:id/monthly-performance', getMonthlyPerformance);
router.get('/:id/monthly-performance-aggregate', getMonthlyPerformanceAggregate);

module.exports = router;

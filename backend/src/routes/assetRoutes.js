// ============================================
// ASSET ROUTES
// ============================================

const express = require('express');
const {
  getAllAssets,
  getAssetByIsin,
  createAsset,
  updateAsset,
  deleteAsset,
} = require('../controllers/assetController');

const router = express.Router();

router.get('/', getAllAssets);
router.get('/isin/:isin', getAssetByIsin);
router.post('/', createAsset);
router.put('/:id', updateAsset);
router.delete('/:id', deleteAsset);

module.exports = router;

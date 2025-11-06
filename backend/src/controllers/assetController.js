// ============================================
// ASSET CONTROLLER
// Handles all asset-related operations
// ============================================

const pool = require('../config/database');

/**
 * GET /api/assets
 * Recupera lista di tutti gli asset attivi
 */
async function getAllAssets(req, res) {
  try {
    const result = await pool.query('SELECT * FROM assets WHERE is_active = true ORDER BY name');
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero asset' });
  }
}

/**
 * GET /api/assets/isin/:isin
 * Recupera un asset tramite ISIN
 */
async function getAssetByIsin(req, res) {
  try {
    const { isin } = req.params;
    const result = await pool.query('SELECT * FROM assets WHERE isin = $1', [isin]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Asset non trovato' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero asset' });
  }
}

/**
 * POST /api/assets
 * Crea un nuovo asset
 */
async function createAsset(req, res) {
  try {
    const {
      isin,
      ticker,
      name,
      asset_type,
      asset_category,
      currency,
      country,
      region,
      sector,
      industry,
      benchmark_index,
      ter,
      transaction_cost,
      esg_rating,
      is_accumulation,
      description,
      sharpe_ratio,
      annual_fees,
      standard_deviation,
      isr,
    } = req.body;

    const result = await pool.query(
      `INSERT INTO assets (
        isin, ticker, name, asset_type, asset_category, currency,
        country, region, sector, industry, benchmark_index,
        ter, transaction_cost, esg_rating, is_accumulation, description,
        sharpe_ratio, annual_fees, standard_deviation, isr
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20)
      RETURNING *`,
      [
        isin,
        ticker,
        name,
        asset_type,
        asset_category,
        currency || 'EUR',
        country,
        region,
        sector,
        industry,
        benchmark_index,
        ter,
        transaction_cost,
        esg_rating,
        is_accumulation,
        description,
        sharpe_ratio,
        annual_fees,
        standard_deviation,
        isr,
      ]
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nella creazione asset' });
  }
}

/**
 * PUT /api/assets/:id
 * Aggiorna un asset esistente
 */
async function updateAsset(req, res) {
  try {
    const { id } = req.params;
    const {
      isin,
      ticker,
      name,
      asset_type,
      asset_category,
      currency,
      country,
      region,
      sector,
      industry,
      benchmark_index,
      ter,
      transaction_cost,
      esg_rating,
      is_accumulation,
      description,
      sharpe_ratio,
      annual_fees,
      standard_deviation,
      isr,
    } = req.body;

    const result = await pool.query(
      `UPDATE assets SET
        isin = $1, ticker = $2, name = $3, asset_type = $4, asset_category = $5,
        currency = $6, country = $7, region = $8, sector = $9, industry = $10,
        benchmark_index = $11, ter = $12, transaction_cost = $13, esg_rating = $14,
        is_accumulation = $15, description = $16,
        sharpe_ratio = $17, annual_fees = $18, standard_deviation = $19, isr = $20,
        updated_at = CURRENT_TIMESTAMP
       WHERE asset_id = $21
       RETURNING *`,
      [
        isin,
        ticker,
        name,
        asset_type,
        asset_category,
        currency,
        country,
        region,
        sector,
        industry,
        benchmark_index,
        ter,
        transaction_cost,
        esg_rating,
        is_accumulation,
        description,
        sharpe_ratio,
        annual_fees,
        standard_deviation,
        isr,
        id,
      ]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Asset non trovato' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Errore nell'aggiornamento asset" });
  }
}

/**
 * DELETE /api/assets/:id
 * Elimina (soft delete) un asset
 */
async function deleteAsset(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `UPDATE assets SET is_active = false, updated_at = CURRENT_TIMESTAMP
       WHERE asset_id = $1
       RETURNING *`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Asset non trovato' });
    }

    res.json({ message: 'Asset eliminato con successo', asset: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Errore nell'eliminazione asset" });
  }
}

module.exports = {
  getAllAssets,
  getAssetByIsin,
  createAsset,
  updateAsset,
  deleteAsset,
};

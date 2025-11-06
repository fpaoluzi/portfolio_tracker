// ============================================
// TARGET ALLOCATION CONTROLLER
// Handles target allocation operations
// ============================================

const pool = require('../config/database');

/**
 * GET /api/target-allocations/:portfolioId
 * Recupera target allocation attivo per un portafoglio
 */
async function getTargetAllocation(req, res) {
  try {
    const { portfolioId } = req.params;
    const result = await pool.query(
      `SELECT * FROM target_allocations
       WHERE portfolio_id = $1 AND is_active = true
       ORDER BY created_at DESC
       LIMIT 1`,
      [portfolioId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Target allocation non trovato' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero target allocation' });
  }
}

/**
 * POST /api/target-allocations
 * Crea nuovo target allocation
 */
async function createTargetAllocation(req, res) {
  try {
    const {
      portfolio_id,
      allocation_name,
      target_azionario,
      target_obbligazionario,
      target_monetario,
      target_oro,
      target_crypto,
    } = req.body;

    const result = await pool.query(
      `INSERT INTO target_allocations (
        portfolio_id, allocation_name,
        target_azionario, target_obbligazionario, target_monetario,
        target_oro, target_crypto
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *`,
      [
        portfolio_id,
        allocation_name || 'Target Standard',
        target_azionario || 0,
        target_obbligazionario || 0,
        target_monetario || 0,
        target_oro || 0,
        target_crypto || 0,
      ]
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nella creazione target allocation' });
  }
}

/**
 * PUT /api/target-allocations/:id
 * Aggiorna target allocation
 */
async function updateTargetAllocation(req, res) {
  try {
    const { id } = req.params;
    const {
      allocation_name,
      target_azionario,
      target_obbligazionario,
      target_monetario,
      target_oro,
      target_crypto,
    } = req.body;

    const result = await pool.query(
      `UPDATE target_allocations SET
        allocation_name = $1,
        target_azionario = $2,
        target_obbligazionario = $3,
        target_monetario = $4,
        target_oro = $5,
        target_crypto = $6,
        updated_at = CURRENT_TIMESTAMP
       WHERE target_id = $7
       RETURNING *`,
      [
        allocation_name,
        target_azionario,
        target_obbligazionario,
        target_monetario,
        target_oro,
        target_crypto,
        id,
      ]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Target allocation non trovato' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Errore nell'aggiornamento target allocation" });
  }
}

module.exports = {
  getTargetAllocation,
  createTargetAllocation,
  updateTargetAllocation,
};

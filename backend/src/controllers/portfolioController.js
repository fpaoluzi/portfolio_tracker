// ============================================
// PORTFOLIO CONTROLLER
// Handles all portfolio-related operations
// ============================================

const pool = require('../config/database');

/**
 * GET /api/portfolios
 * Recupera lista di tutti i portafogli attivi
 */
async function getAllPortfolios(req, res) {
  try {
    const result = await pool.query(
      'SELECT * FROM portfolios WHERE is_active = true ORDER BY name'
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero portafogli' });
  }
}

/**
 * GET /api/portfolios/:id
 * Recupera un singolo portafoglio per ID
 */
async function getPortfolioById(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('SELECT * FROM portfolios WHERE portfolio_id = $1', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Portafoglio non trovato' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero portafoglio' });
  }
}

/**
 * POST /api/portfolios
 * Crea un nuovo portafoglio
 */
async function createPortfolio(req, res) {
  try {
    const { name, broker, account_number, currency, notes } = req.body;
    const result = await pool.query(
      `INSERT INTO portfolios (name, broker, account_number, currency, notes)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [name, broker, account_number, currency || 'EUR', notes]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nella creazione portafoglio' });
  }
}

/**
 * PUT /api/portfolios/:id
 * Aggiorna un portafoglio esistente
 */
async function updatePortfolio(req, res) {
  try {
    const { id } = req.params;
    const { name, broker, account_number, currency, notes } = req.body;

    const result = await pool.query(
      `UPDATE portfolios SET
        name = $1, broker = $2, account_number = $3, currency = $4, notes = $5,
        updated_at = CURRENT_TIMESTAMP
       WHERE portfolio_id = $6
       RETURNING *`,
      [name, broker, account_number, currency, notes, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Portafoglio non trovato' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Errore nell'aggiornamento portafoglio" });
  }
}

/**
 * DELETE /api/portfolios/:id
 * Elimina (soft delete) un portafoglio
 */
async function deletePortfolio(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `UPDATE portfolios SET is_active = false, updated_at = CURRENT_TIMESTAMP
       WHERE portfolio_id = $1
       RETURNING *`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Portafoglio non trovato' });
    }

    res.json({ message: 'Portafoglio eliminato con successo', portfolio: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Errore nell'eliminazione portafoglio" });
  }
}

/**
 * GET /api/portfolios/:id/performance
 * Recupera performance di un portafoglio
 */
async function getPortfolioPerformance(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('SELECT * FROM v_portfolio_performance WHERE portfolio_id = $1', [
      id,
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Portafoglio non trovato' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel calcolo performance' });
  }
}

/**
 * GET /api/portfolios/:id/allocation
 * Recupera allocazione asset di un portafoglio
 */
async function getPortfolioAllocation(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('SELECT * FROM v_asset_allocation WHERE portfolio_id = $1', [id]);
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel calcolo allocazione' });
  }
}

/**
 * GET /api/portfolios/:id/snapshots
 * Recupera snapshot storici di un portafoglio
 */
async function getPortfolioSnapshots(req, res) {
  try {
    const { id } = req.params;
    const { days = 365 } = req.query;

    const result = await pool.query(
      `SELECT * FROM portfolio_snapshots
       WHERE portfolio_id = $1
       AND snapshot_date >= CURRENT_DATE - $2::integer
       ORDER BY snapshot_date DESC`,
      [id, days]
    );

    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero snapshot' });
  }
}

module.exports = {
  getAllPortfolios,
  getPortfolioById,
  createPortfolio,
  updatePortfolio,
  deletePortfolio,
  getPortfolioPerformance,
  getPortfolioAllocation,
  getPortfolioSnapshots,
};

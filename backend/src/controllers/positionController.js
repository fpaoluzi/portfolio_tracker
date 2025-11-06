// ============================================
// POSITION CONTROLLER
// Handles all position-related operations
// ============================================

const pool = require('../config/database');

/**
 * GET /api/portfolios/:id/positions
 * Recupera tutte le posizioni di un portafoglio
 */
async function getPortfolioPositions(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT * FROM v_current_positions WHERE portfolio_name = (
        SELECT name FROM portfolios WHERE portfolio_id = $1
      )`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Errore nel recupero posizioni' });
  }
}

module.exports = {
  getPortfolioPositions,
};

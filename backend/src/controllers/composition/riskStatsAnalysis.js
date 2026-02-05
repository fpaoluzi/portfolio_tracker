// ============================================
// RISK STATS ANALYSIS CONTROLLER
// Gestisce l'analisi delle statistiche di rischio (ISR, Deviazione Standard, Sharpe Ratio)
// ============================================

const pool = require('../../config/database');

/**
 * GET /api/composition/risk-stats/assets/multiple
 * Recupera statistiche di rischio aggregate per più asset
 * Query params: assetIds, portfolioId
 */
async function getRiskStatsByMultipleAssets(req, res) {
  // Weighted calculation: verified 2026-02-05 — uses v_current_positions for portfolio weights
  try {
    const { assetIds, portfolioId } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');

    let query, params;

    if (portfolioId) {
      // Pesa in base al valore delle posizioni nel portafoglio
      query = `
        WITH asset_values AS (
          SELECT 
            a.asset_id,
            a.isr,
            a.standard_deviation,
            a.sharpe_ratio,
            p.current_value
          FROM assets a
          JOIN v_current_positions p ON a.asset_id = p.asset_id
          WHERE a.asset_id = ANY($1) AND p.portfolio_id = $2
            AND p.current_value > 0
        ),
        total_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total
          FROM asset_values
        )
        SELECT
          COALESCE(SUM(isr * current_value) / NULLIF((SELECT total FROM total_value), 0), 0) AS weighted_isr,
          COALESCE(SUM(standard_deviation * current_value) / NULLIF((SELECT total FROM total_value), 0), 0) AS weighted_standard_deviation,
          COALESCE(SUM(sharpe_ratio * current_value) / NULLIF((SELECT total FROM total_value), 0), 0) AS weighted_sharpe_ratio,
          COUNT(*) AS asset_count,
          (SELECT total FROM total_value) AS total_value
        FROM asset_values
        WHERE isr IS NOT NULL OR standard_deviation IS NOT NULL OR sharpe_ratio IS NOT NULL
      `;
      params = [ids, portfolioId];
    } else {
      // Media semplice (senza ponderazione)
      query = `
        SELECT
          COALESCE(AVG(isr), 0) AS weighted_isr,
          COALESCE(AVG(standard_deviation), 0) AS weighted_standard_deviation,
          COALESCE(AVG(sharpe_ratio), 0) AS weighted_sharpe_ratio,
          COUNT(*) AS asset_count,
          0 AS total_value
        FROM assets
        WHERE asset_id = ANY($1)
          AND (isr IS NOT NULL OR standard_deviation IS NOT NULL OR sharpe_ratio IS NOT NULL)
      `;
      params = [ids];
    }

    const result = await pool.query(query, params);

    if (result.rows.length === 0) {
      return res.json({
        isr: null,
        standard_deviation: null,
        sharpe_ratio: null,
        asset_count: 0,
        total_value: 0,
        details: []
      });
    }

    const stats = result.rows[0];

    // Recupera dettagli per ogni asset
    let detailsQuery, detailsParams;
    if (portfolioId) {
      detailsQuery = `
        SELECT 
          a.asset_id,
          a.ticker,
          a.name AS asset_name,
          a.isr,
          a.standard_deviation,
          a.sharpe_ratio,
          p.current_value,
          (p.current_value / NULLIF((SELECT SUM(current_value) FROM v_current_positions WHERE portfolio_id = $2 AND asset_id = ANY($1)), 0)) * 100 AS weight_percent
        FROM assets a
        JOIN v_current_positions p ON a.asset_id = p.asset_id
        WHERE a.asset_id = ANY($1) AND p.portfolio_id = $2
          AND p.current_value > 0
          AND (a.isr IS NOT NULL OR a.standard_deviation IS NOT NULL OR a.sharpe_ratio IS NOT NULL)
        ORDER BY p.current_value DESC
      `;
      detailsParams = [ids, portfolioId];
    } else {
      detailsQuery = `
        SELECT 
          asset_id,
          ticker,
          name AS asset_name,
          isr,
          standard_deviation,
          sharpe_ratio,
          0 AS current_value,
          (100.0 / COUNT(*) OVER()) AS weight_percent
        FROM assets
        WHERE asset_id = ANY($1)
          AND (isr IS NOT NULL OR standard_deviation IS NOT NULL OR sharpe_ratio IS NOT NULL)
        ORDER BY name
      `;
      detailsParams = [ids];
    }

    const detailsResult = await pool.query(detailsQuery, detailsParams);

    const details = detailsResult.rows.map(row => ({
      asset_id: row.asset_id,
      ticker: row.ticker,
      asset_name: row.asset_name,
      isr: row.isr ? parseFloat(row.isr) : null,
      standard_deviation: row.standard_deviation ? parseFloat(row.standard_deviation) : null,
      sharpe_ratio: row.sharpe_ratio ? parseFloat(row.sharpe_ratio) : null,
      current_value: parseFloat(row.current_value || 0),
      weight_percent: parseFloat(row.weight_percent || 0),
    }));

    res.json({
      isr: stats.weighted_isr ? parseFloat(Number(stats.weighted_isr).toFixed(2)) : null,
      standard_deviation: stats.weighted_standard_deviation ? parseFloat(Number(stats.weighted_standard_deviation).toFixed(2)) : null,
      sharpe_ratio: stats.weighted_sharpe_ratio ? parseFloat(Number(stats.weighted_sharpe_ratio).toFixed(2)) : null,
      asset_count: parseInt(stats.asset_count, 10),
      total_value: parseFloat(stats.total_value || 0),
      details,
    });
  } catch (err) {
    console.error('Error in getRiskStatsByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo statistiche rischio', details: err.message });
  }
}

/**
 * GET /api/composition/risk-stats/portfolio/:portfolioId
 * Recupera statistiche di rischio aggregate per un portafoglio
 */
async function getRiskStatsByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;

    const query = `
      WITH asset_values AS (
        SELECT 
          a.asset_id,
          a.isr,
          a.standard_deviation,
          a.sharpe_ratio,
          p.current_value
        FROM assets a
        JOIN v_current_positions p ON a.asset_id = p.asset_id
        WHERE p.portfolio_id = $1
          AND p.current_value > 0
      ),
      total_value AS (
        SELECT COALESCE(SUM(current_value), 0) AS total
        FROM asset_values
      )
      SELECT
        COALESCE(SUM(isr * current_value) / NULLIF((SELECT total FROM total_value), 0), 0) AS weighted_isr,
        COALESCE(SUM(standard_deviation * current_value) / NULLIF((SELECT total FROM total_value), 0), 0) AS weighted_standard_deviation,
        COALESCE(SUM(sharpe_ratio * current_value) / NULLIF((SELECT total FROM total_value), 0), 0) AS weighted_sharpe_ratio,
        COUNT(*) AS asset_count,
        (SELECT total FROM total_value) AS total_value
      FROM asset_values
      WHERE isr IS NOT NULL OR standard_deviation IS NOT NULL OR sharpe_ratio IS NOT NULL
    `;

    const result = await pool.query(query, [portfolioId]);

    if (result.rows.length === 0 || result.rows[0].asset_count === '0') {
      return res.json({
        isr: null,
        standard_deviation: null,
        sharpe_ratio: null,
        asset_count: 0,
        total_value: 0,
        details: []
      });
    }

    const stats = result.rows[0];

    // Recupera dettagli per ogni asset
    const detailsQuery = `
      SELECT 
        a.asset_id,
        a.ticker,
        a.name AS asset_name,
        a.isr,
        a.standard_deviation,
        a.sharpe_ratio,
        p.current_value,
        (p.current_value / NULLIF((SELECT SUM(current_value) FROM v_current_positions WHERE portfolio_id = $1), 0)) * 100 AS weight_percent
      FROM assets a
      JOIN v_current_positions p ON a.asset_id = p.asset_id
      WHERE p.portfolio_id = $1
        AND p.current_value > 0
        AND (a.isr IS NOT NULL OR a.standard_deviation IS NOT NULL OR a.sharpe_ratio IS NOT NULL)
      ORDER BY p.current_value DESC
    `;

    const detailsResult = await pool.query(detailsQuery, [portfolioId]);

    const details = detailsResult.rows.map(row => ({
      asset_id: row.asset_id,
      ticker: row.ticker,
      asset_name: row.asset_name,
      isr: row.isr ? parseFloat(row.isr) : null,
      standard_deviation: row.standard_deviation ? parseFloat(row.standard_deviation) : null,
      sharpe_ratio: row.sharpe_ratio ? parseFloat(row.sharpe_ratio) : null,
      current_value: parseFloat(row.current_value || 0),
      weight_percent: parseFloat(row.weight_percent || 0),
    }));

    res.json({
      isr: stats.weighted_isr ? parseFloat(Number(stats.weighted_isr).toFixed(2)) : null,
      standard_deviation: stats.weighted_standard_deviation ? parseFloat(Number(stats.weighted_standard_deviation).toFixed(2)) : null,
      sharpe_ratio: stats.weighted_sharpe_ratio ? parseFloat(Number(stats.weighted_sharpe_ratio).toFixed(2)) : null,
      asset_count: parseInt(stats.asset_count, 10),
      total_value: parseFloat(stats.total_value || 0),
      details,
    });
  } catch (err) {
    console.error('Error in getRiskStatsByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo statistiche rischio portafoglio', details: err.message });
  }
}

module.exports = {
  getRiskStatsByMultipleAssets,
  getRiskStatsByPortfolio,
};



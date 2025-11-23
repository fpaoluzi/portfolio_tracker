// ============================================
// HOLDINGS ANALYSIS CONTROLLER
// Gestisce l'analisi dei singoli titoli detenuti (Top Holdings)
// LOGICA CORRETTA: Peso reale = Peso_Asset × Peso_Holding
// ============================================

const pool = require('../../config/database');

/**
 * GET /api/composition/holdings/asset/:assetId
 * Recupera le holdings per un singolo asset
 */
async function getHoldingsByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const { limit = 15 } = req.query;
    const queryLimit = parseInt(limit, 10);

    // Query per top holdings
    const holdingsQuery = `
      SELECT 
        holding_symbol,
        holding_name,
        holding_percent
      FROM etf_holdings
      WHERE asset_id = $1
      ORDER BY holding_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(holdingsQuery, [assetId]);

    // Converti da decimale a percentuale (0.0442 -> 4.42)
    const holdings = result.rows.map(row => ({
      holding_symbol: row.holding_symbol,
      holding_name: row.holding_name,
      weighted_percent: parseFloat((row.holding_percent * 100).toFixed(2))
    }));

    // Calcola "Altri" come differenza tra 100% e la somma di TUTTE le holdings
    const allHoldingsQuery = `
      SELECT COALESCE(SUM(holding_percent), 0) as total
      FROM etf_holdings
      WHERE asset_id = $1
    `;
    const totalResult = await pool.query(allHoldingsQuery, [assetId]);
    const allHoldingsTotal = parseFloat(totalResult.rows[0].total);

    // Somma delle holdings mostrate
    const shownTotal = holdings.reduce((sum, h) => sum + (h.weighted_percent / 100), 0);

    // Altri = totale di tutte le holdings - holdings mostrate
    const othersPercent = Math.max(0, (allHoldingsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      holdings.push({
        holding_symbol: null,
        holding_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      holdings,
      count: holdings.length,
      totalPercent: parseFloat((allHoldingsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getHoldingsByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero holdings' });
  }
}

/**
 * GET /api/composition/holdings/portfolio/:portfolioId
 * Recupera holdings aggregate per un portafoglio (look-through corretto)
 * Formula: Peso_Reale = Peso_Asset_nel_Portafoglio × Peso_Holding_in_Asset
 */
async function getHoldingsByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    // Query con calcolo corretto del peso reale
    const query = `
      WITH asset_weights AS (
        -- Calcola il peso di ogni asset nel portafoglio
        SELECT 
          asset_id,
          current_value,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        h.holding_symbol,
        h.holding_name,
        SUM(aw.asset_weight * h.holding_percent) as real_weight
      FROM etf_holdings h
      JOIN asset_weights aw ON h.asset_id = aw.asset_id
      WHERE h.holding_symbol IS NOT NULL AND h.holding_symbol != ''
      GROUP BY h.holding_symbol, h.holding_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    // Converti da decimale a percentuale
    const holdings = result.rows.map(row => ({
      holding_symbol: row.holding_symbol,
      holding_name: row.holding_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    // Calcola il totale di TUTTE le holdings (non solo quelle mostrate)
    const allHoldingsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * h.holding_percent), 0) as total
      FROM etf_holdings h
      JOIN asset_weights aw ON h.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allHoldingsQuery, [portfolioId]);
    const allHoldingsTotal = parseFloat(totalResult.rows[0].total);

    // Somma delle holdings mostrate
    const shownTotal = holdings.reduce((sum, h) => sum + (h.weighted_percent / 100), 0);

    // Altri = totale - mostrate
    const othersPercent = Math.max(0, (allHoldingsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      holdings.push({
        holding_symbol: null,
        holding_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      holdings,
      count: holdings.length,
      totalPercent: parseFloat((allHoldingsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getHoldingsByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo holdings portafoglio' });
  }
}

/**
 * GET /api/composition/holdings/portfolios/multiple
 * Recupera holdings aggregate per più portafogli
 */
async function getHoldingsByMultiplePortfolios(req, res) {
  try {
    const { portfolioIds, expand = 'false', limit = 15 } = req.query;

    if (!portfolioIds) {
      return res.status(400).json({ error: 'portfolioIds query parameter richiesto' });
    }

    const ids = Array.isArray(portfolioIds) ? portfolioIds : portfolioIds.split(',');
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    const query = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        h.holding_symbol,
        h.holding_name,
        SUM(aw.asset_weight * h.holding_percent) as real_weight
      FROM etf_holdings h
      JOIN asset_weights aw ON h.asset_id = aw.asset_id
      WHERE h.holding_symbol IS NOT NULL AND h.holding_symbol != ''
      GROUP BY h.holding_symbol, h.holding_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [ids]);

    const holdings = result.rows.map(row => ({
      holding_symbol: row.holding_symbol,
      holding_name: row.holding_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allHoldingsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * h.holding_percent), 0) as total
      FROM etf_holdings h
      JOIN asset_weights aw ON h.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allHoldingsQuery, [ids]);
    const allHoldingsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = holdings.reduce((sum, h) => sum + (h.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allHoldingsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      holdings.push({
        holding_symbol: null,
        holding_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      holdings,
      count: holdings.length,
      totalPercent: parseFloat((allHoldingsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getHoldingsByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo holdings multi-portafoglio' });
  }
}

/**
 * GET /api/composition/holdings/assets/multiple
 * Recupera holdings aggregate per più asset
 */
async function getHoldingsByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    let query, params, allHoldingsQuery, allParams;

    if (portfolioId) {
      // Con portfolioId: calcola peso reale considerando il valore degli asset
      query = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          h.holding_symbol,
          h.holding_name,
          SUM(aw.asset_weight * h.holding_percent) as real_weight
        FROM etf_holdings h
        JOIN asset_weights aw ON h.asset_id = aw.asset_id
        WHERE h.holding_symbol IS NOT NULL AND h.holding_symbol != ''
        GROUP BY h.holding_symbol, h.holding_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids, portfolioId];

      allHoldingsQuery = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          COALESCE(SUM(aw.asset_weight * h.holding_percent), 0) as total
        FROM etf_holdings h
        JOIN asset_weights aw ON h.asset_id = aw.asset_id
      `;
      allParams = [ids, portfolioId];
    } else {
      // Senza portfolioId: media semplice (peso uguale per ogni asset)
      query = `
        SELECT
          h.holding_symbol,
          h.holding_name,
          AVG(h.holding_percent) as real_weight
        FROM etf_holdings h
        WHERE h.asset_id = ANY($1)
          AND h.holding_symbol IS NOT NULL AND h.holding_symbol != ''
        GROUP BY h.holding_symbol, h.holding_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids];

      allHoldingsQuery = `
        SELECT
          COALESCE(AVG(total_per_asset), 0) as total
        FROM (
          SELECT asset_id, SUM(holding_percent) as total_per_asset
          FROM etf_holdings
          WHERE asset_id = ANY($1)
          GROUP BY asset_id
        ) t
      `;
      allParams = [ids];
    }

    const result = await pool.query(query, params);

    const holdings = result.rows.map(row => ({
      holding_symbol: row.holding_symbol,
      holding_name: row.holding_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const totalResult = await pool.query(allHoldingsQuery, allParams);
    const allHoldingsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = holdings.reduce((sum, h) => sum + (h.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allHoldingsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      holdings.push({
        holding_symbol: null,
        holding_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      holdings,
      count: holdings.length,
      totalPercent: parseFloat((allHoldingsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getHoldingsByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo holdings multi-asset' });
  }
}

/**
 * POST /api/composition/holdings/asset/:assetId
 * Salva manualmente le holdings per un asset
 */
async function saveManualHoldings(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { holdings } = req.body;

    if (!holdings || !Array.isArray(holdings)) {
      return res.status(400).json({ error: 'holdings array richiesto' });
    }

    await client.query('BEGIN');

    // Cancella holdings esistenti
    await client.query('DELETE FROM etf_holdings WHERE asset_id = $1', [assetId]);

    // Inserisci nuove holdings
    let inserted = 0;
    for (const holding of holdings) {
      await client.query(
        `INSERT INTO etf_holdings (asset_id, holding_symbol, holding_name, holding_percent, rank_position)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          assetId,
          holding.symbol || null,
          holding.name,
          holding.percent / 100, // Converti da percentuale a decimale
          holding.rank || 0
        ]
      );
      inserted++;
    }

    await client.query('COMMIT');

    res.json({
      success: true,
      message: `${inserted} holdings salvate con successo`,
      count: inserted
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error in saveManualHoldings:', err);
    res.status(500).json({ error: 'Errore nel salvataggio holdings', details: err.message });
  } finally {
    client.release();
  }
}

/**
 * DELETE /api/composition/holdings/asset/:assetId
 * Cancella le holdings per un asset
 */
async function deleteHoldingsByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query('DELETE FROM etf_holdings WHERE asset_id = $1', [assetId]);

    res.json({
      success: true,
      message: `${result.rowCount} holdings cancellate`,
      deletedCount: result.rowCount
    });

  } catch (err) {
    console.error('Error in deleteHoldingsByAsset:', err);
    res.status(500).json({ error: 'Errore nella cancellazione holdings' });
  }
}

/**
 * GET /api/composition/holdings/detail
 * Recupera dettagli degli asset che contengono una specifica holding
 */
async function getHoldingDetail(req, res) {
  try {
    const { portfolioId, holdingSymbol, holdingName } = req.query;

    if (!portfolioId || (!holdingSymbol && !holdingName)) {
      return res.status(400).json({ error: 'portfolioId e holdingSymbol o holdingName richiesti' });
    }

    let query, params;

    if (holdingSymbol) {
      query = `
        SELECT
          a.asset_id,
          a.ticker,
          a.name AS asset_name,
          p.current_value,
          SUM(h.holding_percent) AS holding_percent,
          SUM(h.holding_percent * p.current_value) AS holding_value,
          MIN(h.holding_name) AS holding_name
        FROM etf_holdings h
        JOIN v_current_positions p ON h.asset_id = p.asset_id
        JOIN assets a ON h.asset_id = a.asset_id
        WHERE p.portfolio_id = $1
          AND h.holding_symbol = $2
          AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
        GROUP BY a.asset_id, a.ticker, a.name, p.current_value
        ORDER BY holding_value DESC
      `;
      params = [portfolioId, holdingSymbol];
    } else {
      query = `
        SELECT
          a.asset_id,
          a.ticker,
          a.name AS asset_name,
          p.current_value,
          h.holding_percent,
          (h.holding_percent * p.current_value) AS holding_value,
          h.holding_name
        FROM etf_holdings h
        JOIN v_current_positions p ON h.asset_id = p.asset_id
        JOIN assets a ON h.asset_id = a.asset_id
        WHERE p.portfolio_id = $1
          AND h.holding_name = $2
        ORDER BY holding_value DESC
      `;
      params = [portfolioId, holdingName];
    }

    const result = await pool.query(query, params);

    const details = result.rows.map(row => ({
      asset_id: row.asset_id,
      ticker: row.ticker,
      asset_name: row.asset_name,
      current_value: parseFloat(row.current_value),
      holding_percent: parseFloat((row.holding_percent * 100).toFixed(2)),
      holding_value: parseFloat(row.holding_value),
      contribution_percent: 0,
    }));

    const total = details.reduce((sum, d) => sum + d.holding_value, 0);

    const detailsWithContribution = details.map(d => ({
      ...d,
      contribution_percent: total > 0 ? parseFloat(((d.holding_value / total) * 100).toFixed(2)) : 0,
    }));

    const firstHoldingName = result.rows.length > 0 ? result.rows[0].holding_name : holdingName;

    res.json({
      holding_symbol: holdingSymbol,
      holding_name: holdingSymbol ? firstHoldingName : holdingName,
      details: detailsWithContribution,
      total_value: parseFloat(total.toFixed(2)),
      count: detailsWithContribution.length,
    });

  } catch (err) {
    console.error('Error in getHoldingDetail:', err);
    res.status(500).json({ error: 'Errore nel recupero dettagli holding' });
  }
}

module.exports = {
  getHoldingsByAsset,
  getHoldingsByPortfolio,
  getHoldingsByMultiplePortfolios,
  getHoldingsByMultipleAssets,
  saveManualHoldings,
  deleteHoldingsByAsset,
  getHoldingDetail,
};

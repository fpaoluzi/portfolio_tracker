// ============================================
// HOLDINGS ANALYSIS CONTROLLER
// Gestisce l'analisi dei singoli titoli detenuti (Top Holdings)
// ============================================

const pool = require('../../config/database');
const { calculateLookThrough, calculateMultiPortfolioLookThrough, calculateMultiAssetLookThrough, calculateStats } = require('../../services/compositionCalculator');

/**
 * GET /api/composition/holdings/asset/:assetId
 * Recupera le holdings per un singolo asset
 */
async function getHoldingsByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query(
      'SELECT * FROM etf_holdings WHERE asset_id = $1 ORDER BY rank_position',
      [assetId]
    );

    res.json({
      holdings: result.rows,
      count: result.rows.length,
    });
  } catch (err) {
    console.error('Error in getHoldingsByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero holdings' });
  }
}

/**
 * GET /api/composition/holdings/portfolio/:portfolioId
 * Recupera holdings aggregate per un portafoglio (look-through corretto)
 */
async function getHoldingsByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    // Query per holdings (con limit opzionale)
    // Calcolo corretto:
    // 1. Calcola il controvalore assoluto di ogni holding: holding_percent * current_value
    // 2. Somma i controvalori assoluti per holding
    // 3. Dividi per il TOTALE degli asset che hanno holdings (somma DISTINCT dei current_value)
    const query = `
      WITH assets_with_holdings AS (
        SELECT DISTINCT p.asset_id, p.current_value
        FROM etf_holdings h
        JOIN v_current_positions p ON h.asset_id = p.asset_id
        WHERE p.portfolio_id = $1
          AND h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
          AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
      ),
      total_holdings_value AS (
        SELECT COALESCE(SUM(current_value), 0) AS total_value
        FROM assets_with_holdings
      ),
      all_holdings_total AS (
        SELECT COALESCE(SUM(h.holding_percent * p.current_value), 0) AS total_holdings_sum
        FROM etf_holdings h
        JOIN v_current_positions p ON h.asset_id = p.asset_id
        CROSS JOIN total_holdings_value
        WHERE p.portfolio_id = $1
      )
      SELECT
        h.holding_symbol,
        MIN(h.holding_name) AS holding_name,
        SUM(h.holding_percent * p.current_value) / NULLIF((SELECT total_value FROM total_holdings_value), 0) AS weighted_percent,
        (SELECT total_holdings_sum FROM all_holdings_total) / NULLIF((SELECT total_value FROM total_holdings_value), 0) AS total_percent
      FROM etf_holdings h
      JOIN v_current_positions p ON h.asset_id = p.asset_id
      CROSS JOIN total_holdings_value
      WHERE p.portfolio_id = $1
        AND h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
        AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
      GROUP BY h.holding_symbol
      ORDER BY weighted_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    // weighted_percent è già in formato decimale (0-1) dalla query SQL
    // Il frontend si aspetta formato decimale e moltiplica per 100 per la visualizzazione
    const holdings = result.rows
      .filter(row => row.weighted_percent != null && !isNaN(row.weighted_percent))
      .map(row => ({
        holding_symbol: row.holding_symbol,
        holding_name: row.holding_name,
        weighted_percent: parseFloat(Number(row.weighted_percent).toFixed(4))
      }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = holdings.reduce((sum, h) => sum + h.weighted_percent, 0);
    
    // Il totale dovrebbe essere sempre 1.0 (100%) perché dividiamo per il totale degli asset
    // "Altri" è la differenza tra 100% e la somma delle holdings mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      holdings.push({
        holding_symbol: null,
        holding_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(4))
      });
    }

    const stats = calculateStats(holdings);

    res.json({
      holdings,
      stats,
      count: holdings.length,
      totalPercent: 1.0, // Sempre 100% quando includiamo "Altri"
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

    // Calcolo corretto: divide per il totale degli asset che hanno holdings (somma DISTINCT)
    const query = `
      WITH assets_with_holdings AS (
        SELECT DISTINCT p.asset_id, p.current_value
        FROM etf_holdings h
        JOIN v_current_positions p ON h.asset_id = p.asset_id
        WHERE p.portfolio_id = ANY($1)
          AND h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
          AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
      ),
      total_holdings_value AS (
        SELECT COALESCE(SUM(current_value), 0) AS total_value
        FROM assets_with_holdings
      ),
      all_holdings_total AS (
        SELECT COALESCE(SUM(h.holding_percent * p.current_value), 0) AS total_holdings_sum
        FROM etf_holdings h
        JOIN v_current_positions p ON h.asset_id = p.asset_id
        CROSS JOIN total_holdings_value
        WHERE p.portfolio_id = ANY($1)
      )
      SELECT
        h.holding_symbol,
        MIN(h.holding_name) AS holding_name,
        SUM(h.holding_percent * p.current_value) / NULLIF((SELECT total_value FROM total_holdings_value), 0) AS weighted_percent,
        (SELECT total_holdings_sum FROM all_holdings_total) / NULLIF((SELECT total_value FROM total_holdings_value), 0) AS total_percent
      FROM etf_holdings h
      JOIN v_current_positions p ON h.asset_id = p.asset_id
      CROSS JOIN total_holdings_value
      WHERE p.portfolio_id = ANY($1)
        AND h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
        AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
      GROUP BY h.holding_symbol
      ORDER BY weighted_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [ids]);

    // weighted_percent è già in formato decimale (0-1) dalla query SQL
    // Il frontend si aspetta formato decimale e moltiplica per 100 per la visualizzazione
    const holdings = result.rows
      .filter(row => row.weighted_percent != null && !isNaN(row.weighted_percent))
      .map(row => ({
        holding_symbol: row.holding_symbol,
        holding_name: row.holding_name,
        weighted_percent: parseFloat(Number(row.weighted_percent).toFixed(4))
      }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = holdings.reduce((sum, h) => sum + h.weighted_percent, 0);
    
    // Il totale dovrebbe essere sempre 1.0 (100%) perché dividiamo per il totale degli asset
    // "Altri" è la differenza tra 100% e la somma delle holdings mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      holdings.push({
        holding_symbol: null,
        holding_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(4))
      });
    }

    const stats = calculateStats(holdings);

    res.json({
      holdings,
      stats,
      count: holdings.length,
      totalPercent: 1.0, // Sempre 100% quando includiamo "Altri"
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

    let query, params;

    if (portfolioId) {
      // Pesa in base al valore delle posizioni nel portafoglio
      // Calcolo corretto: divide per il totale degli asset selezionati che hanno holdings (somma DISTINCT)
      query = `
        WITH assets_with_holdings AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_holdings h
          JOIN v_current_positions p ON h.asset_id = p.asset_id
          WHERE h.asset_id = ANY($1) AND p.portfolio_id = $2
            AND h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
            AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
        ),
        total_holdings_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_holdings
        ),
        all_holdings_total AS (
          SELECT COALESCE(SUM(h.holding_percent * p.current_value), 0) AS total_holdings_sum
          FROM etf_holdings h
          JOIN v_current_positions p ON h.asset_id = p.asset_id
          CROSS JOIN total_holdings_value
          WHERE h.asset_id = ANY($1) AND p.portfolio_id = $2
        )
        SELECT
          h.holding_symbol,
          MIN(h.holding_name) AS holding_name,
          SUM(h.holding_percent * p.current_value) / NULLIF((SELECT total_value FROM total_holdings_value), 0) AS weighted_percent,
          (SELECT total_holdings_sum FROM all_holdings_total) / NULLIF((SELECT total_value FROM total_holdings_value), 0) AS total_percent
        FROM etf_holdings h
        JOIN v_current_positions p ON h.asset_id = p.asset_id
        CROSS JOIN total_holdings_value
        WHERE h.asset_id = ANY($1) AND p.portfolio_id = $2
          AND h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
          AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
        GROUP BY h.holding_symbol
        ORDER BY weighted_percent DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids, portfolioId];
    } else {
      // Peso uguale per tutti gli asset (media semplice)
      // Nota: senza portfolioId non possiamo calcolare "Altri" accuratamente
      query = `
        SELECT
          h.holding_symbol,
          MIN(h.holding_name) AS holding_name,
          AVG(h.holding_percent) AS weighted_percent
        FROM etf_holdings h
        WHERE h.asset_id = ANY($1)
          AND h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
          AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '')
        GROUP BY h.holding_symbol
        ORDER BY weighted_percent DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids];
    }

    const result = await pool.query(query, params);

    // weighted_percent è già in formato decimale (0-1) dalla query SQL
    // Quando portfolioId è presente, la query usa SUM con current_value (formato decimale)
    // Quando portfolioId non è presente, la query usa AVG (formato decimale)
    // Il frontend si aspetta formato decimale e moltiplica per 100 per la visualizzazione
    const holdings = result.rows
      .filter(row => row.weighted_percent != null && !isNaN(row.weighted_percent))
      .map(row => ({
        holding_symbol: row.holding_symbol,
        holding_name: row.holding_name,
        weighted_percent: parseFloat(Number(row.weighted_percent).toFixed(4))
      }));

    // Calcola "Altri" solo se portfolioId è presente
    if (portfolioId && result.rows.length > 0) {
      const totalShown = holdings.reduce((sum, h) => sum + h.weighted_percent, 0);
      // Il totale dovrebbe essere sempre 1.0 (100%) perché dividiamo per il totale degli asset
      // "Altri" è la differenza tra 100% e la somma delle holdings mostrate
      const othersPercent = Math.max(0, 1.0 - totalShown);
      
      if (othersPercent > 0.0001) {
        holdings.push({
          holding_symbol: null,
          holding_name: 'Altri',
          weighted_percent: parseFloat(othersPercent.toFixed(4))
        });
      }
    }

    const stats = calculateStats(holdings);

    res.json({
      holdings,
      stats,
      count: holdings.length,
      totalPercent: portfolioId && result.rows.length > 0 
        ? parseFloat(Number(result.rows[0].total_percent || 0).toFixed(4))
        : undefined,
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
 * Query params: portfolioId, holdingSymbol, holdingName
 * Se holdingSymbol è fornito, filtra solo per symbol (ignora holdingName nel filtro)
 * Aggrega per asset_id sommando le percentuali delle holdings con lo stesso symbol
 */
async function getHoldingDetail(req, res) {
  try {
    const { portfolioId, holdingSymbol, holdingName } = req.query;

    if (!portfolioId || (!holdingSymbol && !holdingName)) {
      return res.status(400).json({ error: 'portfolioId e holdingSymbol o holdingName richiesti' });
    }

    // Se holdingSymbol è fornito, usa solo quello per filtrare (ignora holdingName nel WHERE)
    // Aggrega per asset_id sommando le percentuali delle holdings con lo stesso symbol
    let query;
    let params;

    if (holdingSymbol) {
      // Filtra solo per symbol e aggrega per asset
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
      // Se solo holdingName è fornito, filtra per nome (comportamento legacy)
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
      contribution_percent: 0, // Calcolato dopo
    }));

    const total = details.reduce((sum, d) => sum + d.holding_value, 0);

    // Calcola il contributo percentuale per ogni asset
    const detailsWithContribution = details.map(d => ({
      ...d,
      contribution_percent: total > 0 ? parseFloat(((d.holding_value / total) * 100).toFixed(2)) : 0,
    }));

    // Prendi il nome dalla prima riga se disponibile (per holdingSymbol)
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

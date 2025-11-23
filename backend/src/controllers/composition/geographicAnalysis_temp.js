// ============================================
// region ANALYSIS CONTROLLER
// Gestisce l'analisi Regioniale (Technology, Healthcare, Financials, etc.)
// LOGICA CORRETTA: Peso reale = Peso_Asset × Peso_regione
// ============================================

const pool = require('../../config/database');

/**
 * GET /api/composition/regions/asset/:assetId
 * Recupera la composizione Regioniale per un singolo asset
 */
async function getregionsByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const { limit = 15 } = req.query;
    const queryLimit = parseInt(limit, 10);

    const regionsQuery = `
      SELECT 
        region_name,
        weight_percent
      FROM etf_region_weights
      WHERE asset_id = $1
      ORDER BY weight_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(regionsQuery, [assetId]);

    const regions = result.rows.map(row => ({
      region_name: row.region_name,
      weighted_percent: parseFloat((row.weight_percent * 100).toFixed(2))
    }));

    const allregionsQuery = `
      SELECT COALESCE(SUM(weight_percent), 0) as total
      FROM etf_region_weights
      WHERE asset_id = $1
    `;
    const totalResult = await pool.query(allregionsQuery, [assetId]);
    const allregionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allregionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allregionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getregionsByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero Regioni' });
  }
}

/**
 * GET /api/composition/regions/portfolio/:portfolioId
 * Recupera composizione Regioniale aggregata per un portafoglio
 */
async function getregionsByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    const query = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        s.region_name,
        SUM(aw.asset_weight * s.weight_percent) as real_weight
      FROM etf_region_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
      WHERE s.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
      GROUP BY s.region_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    const regions = result.rows.map(row => ({
      region_name: row.region_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allregionsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * s.weight_percent), 0) as total
      FROM etf_region_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allregionsQuery, [portfolioId]);
    const allregionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allregionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allregionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getregionsByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo Regioni portafoglio' });
  }
}

/**
 * GET /api/composition/regions/portfolios/multiple
 * Recupera composizione Regioniale aggregata per più portafogli
 */
async function getregionsByMultiplePortfolios(req, res) {
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
        s.region_name,
        SUM(aw.asset_weight * s.weight_percent) as real_weight
      FROM etf_region_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
      WHERE s.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
      GROUP BY s.region_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [ids]);

    const regions = result.rows.map(row => ({
      region_name: row.region_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allregionsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * s.weight_percent), 0) as total
      FROM etf_region_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allregionsQuery, [ids]);
    const allregionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allregionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allregionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getregionsByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo Regioni multi-portafoglio' });
  }
}

/**
 * GET /api/composition/regions/assets/multiple
 * Recupera composizione Regioniale aggregata per più asset
 */
async function getregionsByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    let query, params, allregionsQuery, allParams;

    if (portfolioId) {
      query = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          s.region_name,
          SUM(aw.asset_weight * s.weight_percent) as real_weight
        FROM etf_region_weights s
        JOIN asset_weights aw ON s.asset_id = aw.asset_id
        WHERE s.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
        GROUP BY s.region_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids, portfolioId];

      allregionsQuery = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          COALESCE(SUM(aw.asset_weight * s.weight_percent), 0) as total
        FROM etf_region_weights s
        JOIN asset_weights aw ON s.asset_id = aw.asset_id
      `;
      allParams = [ids, portfolioId];
    } else {
      query = `
        SELECT
          s.region_name,
          AVG(s.weight_percent) as real_weight
        FROM etf_region_weights s
        WHERE s.asset_id = ANY($1)
          AND s.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
        GROUP BY s.region_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids];

      allregionsQuery = `
        SELECT
          COALESCE(AVG(total_per_asset), 0) as total
        FROM (
          SELECT asset_id, SUM(weight_percent) as total_per_asset
          FROM etf_region_weights
          WHERE asset_id = ANY($1)
          GROUP BY asset_id
        ) t
      `;
      allParams = [ids];
    }

    const result = await pool.query(query, params);

    const regions = result.rows.map(row => ({
      region_name: row.region_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const totalResult = await pool.query(allregionsQuery, allParams);
    const allregionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allregionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allregionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getregionsByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo Regioni multi-asset' });
  }
}

/**
 * POST /api/composition/regions/asset/:assetId
 * Salva manualmente la composizione Regioniale per un asset
 */
async function saveManualregions(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { regions } = req.body;

    if (!regions || !Array.isArray(regions)) {
      return res.status(400).json({ error: 'regions array richiesto' });
    }

    await client.query('BEGIN');
    await client.query('DELETE FROM etf_region_weights WHERE asset_id = $1', [assetId]);

    let inserted = 0;
    for (const region of regions) {
      await client.query(
        `INSERT INTO etf_region_weights (asset_id, region_name, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, region.name, region.percent / 100]
      );
      inserted++;
    }

    await client.query('COMMIT');

    res.json({
      success: true,
      message: `${inserted} Regioni salvati con successo`,
      count: inserted
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error in saveManualregions:', err);
    res.status(500).json({ error: 'Errore nel salvataggio Regioni', details: err.message });
  } finally {
    client.release();
  }
}

/**
 * DELETE /api/composition/regions/asset/:assetId
 * Cancella i Regioni per un asset
 */
async function deleteregionsByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const result = await pool.query('DELETE FROM etf_region_weights WHERE asset_id = $1', [assetId]);

    res.json({
      success: true,
      message: `${result.rowCount} Regioni cancellati`,
      deletedCount: result.rowCount
    });

  } catch (err) {
    console.error('Error in deleteregionsByAsset:', err);
    res.status(500).json({ error: 'Errore nella cancellazione Regioni' });
  }
}

/**
 * GET /api/composition/regions/detail
 * Recupera dettagli degli asset che contengono un specifico regione
 */
async function getregionDetail(req, res) {
  try {
    const { portfolioId, regionName } = req.query;

    if (!portfolioId || !regionName) {
      return res.status(400).json({ error: 'portfolioId e regionName richiesti' });
    }

    const query = `
      SELECT
        a.asset_id,
        a.ticker,
        a.name AS asset_name,
        p.current_value,
        s.weight_percent,
        (s.weight_percent * p.current_value) AS region_value,
        (s.weight_percent * p.current_value) / NULLIF(SUM(s.weight_percent * p.current_value) OVER(), 0) AS contribution_percent
      FROM etf_region_weights s
      JOIN v_current_positions p ON s.asset_id = p.asset_id
      JOIN assets a ON s.asset_id = a.asset_id
      WHERE p.portfolio_id = $1
        AND s.region_name = $2
      ORDER BY region_value DESC
    `;

    const result = await pool.query(query, [portfolioId, regionName]);

    const details = result.rows.map(row => ({
      asset_id: row.asset_id,
      ticker: row.ticker,
      asset_name: row.asset_name,
      current_value: parseFloat(row.current_value),
      region_percent: parseFloat((row.weight_percent * 100).toFixed(2)),
      region_value: parseFloat(row.region_value),
      contribution_percent: parseFloat((row.contribution_percent * 100).toFixed(2)),
    }));

    const total = details.reduce((sum, d) => sum + d.region_value, 0);

    res.json({
      region_name: regionName,
      details,
      total_value: parseFloat(total.toFixed(2)),
      count: details.length,
    });

  } catch (err) {
    console.error('Error in getregionDetail:', err);
    res.status(500).json({ error: 'Errore nel recupero dettagli regione' });
  }
}

module.exports = {
  getregionsByAsset,
  getregionsByPortfolio,
  getregionsByMultiplePortfolios,
  getregionsByMultipleAssets,
  saveManualregions,
  deleteregionsByAsset,
  getregionDetail,
};

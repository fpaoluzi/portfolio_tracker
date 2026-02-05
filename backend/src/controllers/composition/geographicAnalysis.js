// ============================================
// GEOGRAPHIC ANALYSIS CONTROLLER
// Gestisce l'analisi geografica (USA, Europa, Asia, etc.)
// LOGICA CORRETTA: Peso reale = Peso_Asset × Peso_Regione
// ============================================

const pool = require('../../config/database');

// Mapping per normalizzare nomi geografici in italiano
const REGION_MAPPING = {
  'United States': 'Stati Uniti', 'USA': 'Stati Uniti', 'US': 'Stati Uniti',
  'United Kingdom': 'Regno Unito', 'UK': 'Regno Unito', 'Great Britain': 'Regno Unito',
  'Japan': 'Giappone', 'France': 'Francia', 'Germany': 'Germania',
  'Netherlands': 'Paesi Bassi', 'Olanda': 'Paesi Bassi', 'Paesi bassi': 'Paesi Bassi',
  'Spain': 'Spagna', 'Italy': 'Italia', 'Switzerland': 'Svizzera',
  'Belgium': 'Belgio', 'Austria': 'Austria', 'Sweden': 'Svezia',
  'Denmark': 'Danimarca', 'Finland': 'Finlandia', 'Norway': 'Norvegia',
  'Portugal': 'Portogallo', 'Ireland': 'Irlanda', 'Poland': 'Polonia',
  'South Korea': 'Corea del Sud', 'Korea': 'Corea del Sud',
  'China': 'Cina', 'Canada': 'Canada', 'Australia': 'Australia',
  'Brazil': 'Brasile', 'India': 'India', 'Mexico': 'Messico',
  'Russia': 'Russia', 'Hong Kong': 'Hong Kong', 'Singapore': 'Singapore',
  'Taiwan': 'Taiwan'
};

function normalizeRegionName(name) {
  return REGION_MAPPING[name] || name;
}

async function getGeographicByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const { limit = 15 } = req.query;
    const queryLimit = parseInt(limit, 10);

    const regionsQuery = `
      SELECT 
        region_name,
        weight_percent
      FROM etf_geographic_weights
      WHERE asset_id = $1
      ORDER BY weight_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(regionsQuery, [assetId]);

    const regions = result.rows.map(row => ({
      region_name: normalizeRegionName(row.region_name),
      weighted_percent: parseFloat((row.weight_percent * 100).toFixed(2))
    }));

    const allRegionsQuery = `
      SELECT COALESCE(SUM(weight_percent), 0) as total
      FROM etf_geographic_weights
      WHERE asset_id = $1
    `;
    const totalResult = await pool.query(allRegionsQuery, [assetId]);
    const allRegionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, r) => sum + (r.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allRegionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allRegionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getGeographicByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero composizione geografica' });
  }
}

async function getGeographicByPortfolio(req, res) {
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
        g.region_name,
        SUM(aw.asset_weight * g.weight_percent) as real_weight
      FROM etf_geographic_weights g
      JOIN asset_weights aw ON g.asset_id = aw.asset_id
      WHERE g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
      GROUP BY g.region_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    const regions = result.rows.map(row => ({
      region_name: normalizeRegionName(row.region_name),
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allRegionsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * g.weight_percent), 0) as total
      FROM etf_geographic_weights g
      JOIN asset_weights aw ON g.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allRegionsQuery, [portfolioId]);
    const allRegionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, r) => sum + (r.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allRegionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allRegionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getGeographicByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo composizione geografica portafoglio' });
  }
}

async function getGeographicByMultiplePortfolios(req, res) {
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
        g.region_name,
        SUM(aw.asset_weight * g.weight_percent) as real_weight
      FROM etf_geographic_weights g
      JOIN asset_weights aw ON g.asset_id = aw.asset_id
      WHERE g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
      GROUP BY g.region_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [ids]);

    const regions = result.rows.map(row => ({
      region_name: normalizeRegionName(row.region_name),
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allRegionsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * g.weight_percent), 0) as total
      FROM etf_geographic_weights g
      JOIN asset_weights aw ON g.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allRegionsQuery, [ids]);
    const allRegionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, r) => sum + (r.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allRegionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allRegionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getGeographicByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo composizione geografica multi-portafoglio' });
  }
}

async function getGeographicByMultipleAssets(req, res) {
  // Weighted calculation: verified 2026-02-05 — uses v_current_positions for portfolio weights
  try {
    const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    let query, params, allRegionsQuery, allParams;

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
          g.region_name,
          SUM(aw.asset_weight * g.weight_percent) as real_weight
        FROM etf_geographic_weights g
        JOIN asset_weights aw ON g.asset_id = aw.asset_id
        WHERE g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
        GROUP BY g.region_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids, portfolioId];

      allRegionsQuery = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          COALESCE(SUM(aw.asset_weight * g.weight_percent), 0) as total
        FROM etf_geographic_weights g
        JOIN asset_weights aw ON g.asset_id = aw.asset_id
      `;
      allParams = [ids, portfolioId];
    } else {
      query = `
        SELECT
          g.region_name,
          AVG(g.weight_percent) as real_weight
        FROM etf_geographic_weights g
        WHERE g.asset_id = ANY($1)
          AND g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
        GROUP BY g.region_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids];

      allRegionsQuery = `
        SELECT
          COALESCE(AVG(total_per_asset), 0) as total
        FROM (
          SELECT asset_id, SUM(weight_percent) as total_per_asset
          FROM etf_geographic_weights
          WHERE asset_id = ANY($1)
          GROUP BY asset_id
        ) t
      `;
      allParams = [ids];
    }

    const result = await pool.query(query, params);

    const regions = result.rows.map(row => ({
      region_name: normalizeRegionName(row.region_name),
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const totalResult = await pool.query(allRegionsQuery, allParams);
    const allRegionsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = regions.reduce((sum, r) => sum + (r.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allRegionsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      regions,
      count: regions.length,
      totalPercent: parseFloat((allRegionsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getGeographicByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo composizione geografica multi-asset' });
  }
}

async function saveManualGeographic(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { regions } = req.body;

    if (!regions || !Array.isArray(regions)) {
      return res.status(400).json({ error: 'regions array richiesto' });
    }

    await client.query('BEGIN');
    await client.query('DELETE FROM etf_geographic_weights WHERE asset_id = $1', [assetId]);

    let inserted = 0;
    for (const region of regions) {
      await client.query(
        `INSERT INTO etf_geographic_weights (asset_id, region_name, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, region.name, region.percent / 100]
      );
      inserted++;
    }

    await client.query('COMMIT');

    res.json({
      success: true,
      message: `${inserted} regioni salvate con successo`,
      count: inserted
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error in saveManualGeographic:', err);
    res.status(500).json({ error: 'Errore nel salvataggio composizione geografica', details: err.message });
  } finally {
    client.release();
  }
}

async function deleteGeographicByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const result = await pool.query('DELETE FROM etf_geographic_weights WHERE asset_id = $1', [assetId]);

    res.json({
      success: true,
      message: `${result.rowCount} regioni cancellate`,
      deletedCount: result.rowCount
    });

  } catch (err) {
    console.error('Error in deleteGeographicByAsset:', err);
    res.status(500).json({ error: 'Errore nella cancellazione composizione geografica' });
  }
}

async function getRegionDetail(req, res) {
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
        g.weight_percent,
        (g.weight_percent * p.current_value) AS region_value,
        (g.weight_percent * p.current_value) / NULLIF(SUM(g.weight_percent * p.current_value) OVER(), 0) AS contribution_percent
      FROM etf_geographic_weights g
      JOIN v_current_positions p ON g.asset_id = p.asset_id
      JOIN assets a ON g.asset_id = a.asset_id
      WHERE p.portfolio_id = $1
        AND g.region_name = $2
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
    console.error('Error in getRegionDetail:', err);
    res.status(500).json({ error: 'Errore nel recupero dettagli regione' });
  }
}

module.exports = {
  getGeographicByAsset,
  getGeographicByPortfolio,
  getGeographicByMultiplePortfolios,
  getGeographicByMultipleAssets,
  saveManualGeographic,
  deleteGeographicByAsset,
  getRegionDetail,
};

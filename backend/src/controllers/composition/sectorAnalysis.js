// ============================================
// SECTOR ANALYSIS CONTROLLER
// Gestisce l'analisi settoriale (Technology, Healthcare, Financials, etc.)
// LOGICA CORRETTA: Peso reale = Peso_Asset × Peso_Settore
// ============================================

const pool = require('../../config/database');

/**
 * GET /api/composition/sectors/asset/:assetId
 * Recupera la composizione settoriale per un singolo asset
 */
async function getSectorsByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const { limit = 15 } = req.query;
    const queryLimit = parseInt(limit, 10);

    const sectorsQuery = `
      SELECT 
        sector_name,
        weight_percent
      FROM etf_sector_weights
      WHERE asset_id = $1
      ORDER BY weight_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(sectorsQuery, [assetId]);

    const sectors = result.rows.map(row => ({
      sector_name: row.sector_name,
      weighted_percent: parseFloat((row.weight_percent * 100).toFixed(2))
    }));

    const allSectorsQuery = `
      SELECT COALESCE(SUM(weight_percent), 0) as total
      FROM etf_sector_weights
      WHERE asset_id = $1
    `;
    const totalResult = await pool.query(allSectorsQuery, [assetId]);
    const allSectorsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = sectors.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allSectorsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      sectors.push({
        sector_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      sectors,
      count: sectors.length,
      totalPercent: parseFloat((allSectorsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getSectorsByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero settori' });
  }
}

/**
 * GET /api/composition/sectors/portfolio/:portfolioId
 * Recupera composizione settoriale aggregata per un portafoglio
 */
async function getSectorsByPortfolio(req, res) {
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
        s.sector_name,
        SUM(aw.asset_weight * s.weight_percent) as real_weight
      FROM etf_sector_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
      WHERE s.sector_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
      GROUP BY s.sector_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    const sectors = result.rows.map(row => ({
      sector_name: row.sector_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allSectorsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * s.weight_percent), 0) as total
      FROM etf_sector_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allSectorsQuery, [portfolioId]);
    const allSectorsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = sectors.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allSectorsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      sectors.push({
        sector_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      sectors,
      count: sectors.length,
      totalPercent: parseFloat((allSectorsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getSectorsByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo settori portafoglio' });
  }
}

/**
 * GET /api/composition/sectors/portfolios/multiple
 * Recupera composizione settoriale aggregata per più portafogli
 */
async function getSectorsByMultiplePortfolios(req, res) {
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
        s.sector_name,
        SUM(aw.asset_weight * s.weight_percent) as real_weight
      FROM etf_sector_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
      WHERE s.sector_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
      GROUP BY s.sector_name
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [ids]);

    const sectors = result.rows.map(row => ({
      sector_name: row.sector_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allSectorsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * s.weight_percent), 0) as total
      FROM etf_sector_weights s
      JOIN asset_weights aw ON s.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allSectorsQuery, [ids]);
    const allSectorsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = sectors.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allSectorsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      sectors.push({
        sector_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      sectors,
      count: sectors.length,
      totalPercent: parseFloat((allSectorsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getSectorsByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo settori multi-portafoglio' });
  }
}

/**
 * GET /api/composition/sectors/assets/multiple
 * Recupera composizione settoriale aggregata per più asset
 */
async function getSectorsByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    let query, params, allSectorsQuery, allParams;

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
          s.sector_name,
          SUM(aw.asset_weight * s.weight_percent) as real_weight
        FROM etf_sector_weights s
        JOIN asset_weights aw ON s.asset_id = aw.asset_id
        WHERE s.sector_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
        GROUP BY s.sector_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids, portfolioId];

      allSectorsQuery = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          COALESCE(SUM(aw.asset_weight * s.weight_percent), 0) as total
        FROM etf_sector_weights s
        JOIN asset_weights aw ON s.asset_id = aw.asset_id
      `;
      allParams = [ids, portfolioId];
    } else {
      query = `
        SELECT
          s.sector_name,
          AVG(s.weight_percent) as real_weight
        FROM etf_sector_weights s
        WHERE s.asset_id = ANY($1)
          AND s.sector_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
        GROUP BY s.sector_name
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids];

      allSectorsQuery = `
        SELECT
          COALESCE(AVG(total_per_asset), 0) as total
        FROM (
          SELECT asset_id, SUM(weight_percent) as total_per_asset
          FROM etf_sector_weights
          WHERE asset_id = ANY($1)
          GROUP BY asset_id
        ) t
      `;
      allParams = [ids];
    }

    const result = await pool.query(query, params);

    const sectors = result.rows.map(row => ({
      sector_name: row.sector_name,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const totalResult = await pool.query(allSectorsQuery, allParams);
    const allSectorsTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = sectors.reduce((sum, s) => sum + (s.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allSectorsTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      sectors.push({
        sector_name: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      sectors,
      count: sectors.length,
      totalPercent: parseFloat((allSectorsTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getSectorsByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo settori multi-asset' });
  }
}

/**
 * POST /api/composition/sectors/asset/:assetId
 * Salva manualmente la composizione settoriale per un asset
 */
async function saveManualSectors(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { sectors } = req.body;

    if (!sectors || !Array.isArray(sectors)) {
      return res.status(400).json({ error: 'sectors array richiesto' });
    }

    await client.query('BEGIN');
    await client.query('DELETE FROM etf_sector_weights WHERE asset_id = $1', [assetId]);

    let inserted = 0;
    for (const sector of sectors) {
      await client.query(
        `INSERT INTO etf_sector_weights (asset_id, sector_name, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, sector.name, sector.percent / 100]
      );
      inserted++;
    }

    await client.query('COMMIT');

    res.json({
      success: true,
      message: `${inserted} settori salvati con successo`,
      count: inserted
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error in saveManualSectors:', err);
    res.status(500).json({ error: 'Errore nel salvataggio settori', details: err.message });
  } finally {
    client.release();
  }
}

/**
 * DELETE /api/composition/sectors/asset/:assetId
 * Cancella i settori per un asset
 */
async function deleteSectorsByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const result = await pool.query('DELETE FROM etf_sector_weights WHERE asset_id = $1', [assetId]);

    res.json({
      success: true,
      message: `${result.rowCount} settori cancellati`,
      deletedCount: result.rowCount
    });

  } catch (err) {
    console.error('Error in deleteSectorsByAsset:', err);
    res.status(500).json({ error: 'Errore nella cancellazione settori' });
  }
}

/**
 * GET /api/composition/sectors/detail
 * Recupera dettagli degli asset che contengono un specifico settore
 */
async function getSectorDetail(req, res) {
  try {
    const { portfolioId, sectorName } = req.query;

    if (!portfolioId || !sectorName) {
      return res.status(400).json({ error: 'portfolioId e sectorName richiesti' });
    }

    const query = `
      SELECT
        a.asset_id,
        a.ticker,
        a.name AS asset_name,
        p.current_value,
        s.weight_percent,
        (s.weight_percent * p.current_value) AS sector_value,
        (s.weight_percent * p.current_value) / NULLIF(SUM(s.weight_percent * p.current_value) OVER(), 0) AS contribution_percent
      FROM etf_sector_weights s
      JOIN v_current_positions p ON s.asset_id = p.asset_id
      JOIN assets a ON s.asset_id = a.asset_id
      WHERE p.portfolio_id = $1
        AND s.sector_name = $2
      ORDER BY sector_value DESC
    `;

    const result = await pool.query(query, [portfolioId, sectorName]);

    const details = result.rows.map(row => ({
      asset_id: row.asset_id,
      ticker: row.ticker,
      asset_name: row.asset_name,
      current_value: parseFloat(row.current_value),
      sector_percent: parseFloat((row.weight_percent * 100).toFixed(2)),
      sector_value: parseFloat(row.sector_value),
      contribution_percent: parseFloat((row.contribution_percent * 100).toFixed(2)),
    }));

    const total = details.reduce((sum, d) => sum + d.sector_value, 0);

    res.json({
      sector_name: sectorName,
      details,
      total_value: parseFloat(total.toFixed(2)),
      count: details.length,
    });

  } catch (err) {
    console.error('Error in getSectorDetail:', err);
    res.status(500).json({ error: 'Errore nel recupero dettagli settore' });
  }
}

module.exports = {
  getSectorsByAsset,
  getSectorsByPortfolio,
  getSectorsByMultiplePortfolios,
  getSectorsByMultipleAssets,
  saveManualSectors,
  deleteSectorsByAsset,
  getSectorDetail,
};

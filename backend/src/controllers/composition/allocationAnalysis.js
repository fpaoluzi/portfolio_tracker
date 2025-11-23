// ============================================
// ALLOCATION ANALYSIS CONTROLLER
// Gestisce l'analisi di asset allocation (Stocks, Bonds, Cash, Commodities, etc.)
// LOGICA CORRETTA: Peso reale = Peso_Asset × Peso_Allocation
// ============================================

const pool = require('../../config/database');

async function getAllocationByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const { limit = 15 } = req.query;
    const queryLimit = parseInt(limit, 10);

    const allocationQuery = `
      SELECT 
        allocation_type,
        weight_percent
      FROM etf_asset_allocation
      WHERE asset_id = $1
      ORDER BY weight_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(allocationQuery, [assetId]);

    const allocation = result.rows.map(row => ({
      allocation_type: row.allocation_type,
      weighted_percent: parseFloat((row.weight_percent * 100).toFixed(2))
    }));

    const allAllocationQuery = `
      SELECT COALESCE(SUM(weight_percent), 0) as total
      FROM etf_asset_allocation
      WHERE asset_id = $1
    `;
    const totalResult = await pool.query(allAllocationQuery, [assetId]);
    const allAllocationTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = allocation.reduce((sum, a) => sum + (a.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allAllocationTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      allocation.push({
        allocation_type: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      allocation,
      count: allocation.length,
      totalPercent: parseFloat((allAllocationTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getAllocationByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero asset allocation' });
  }
}

async function getAllocationByPortfolio(req, res) {
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
        a.allocation_type,
        SUM(aw.asset_weight * a.weight_percent) as real_weight
      FROM etf_asset_allocation a
      JOIN asset_weights aw ON a.asset_id = aw.asset_id
      WHERE a.allocation_type NOT IN ('Altri', 'Other', 'Others', 'Altro', 'N/A')
      GROUP BY a.allocation_type
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    const allocation = result.rows.map(row => ({
      allocation_type: row.allocation_type,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allAllocationQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * a.weight_percent), 0) as total
      FROM etf_asset_allocation a
      JOIN asset_weights aw ON a.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allAllocationQuery, [portfolioId]);
    const allAllocationTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = allocation.reduce((sum, a) => sum + (a.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allAllocationTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      allocation.push({
        allocation_type: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      allocation,
      count: allocation.length,
      totalPercent: parseFloat((allAllocationTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getAllocationByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo asset allocation portafoglio' });
  }
}

async function getAllocationByMultiplePortfolios(req, res) {
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
        a.allocation_type,
        SUM(aw.asset_weight * a.weight_percent) as real_weight
      FROM etf_asset_allocation a
      JOIN asset_weights aw ON a.asset_id = aw.asset_id
      WHERE a.allocation_type NOT IN ('Altri', 'Other', 'Others', 'Altro', 'N/A')
      GROUP BY a.allocation_type
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [ids]);

    const allocation = result.rows.map(row => ({
      allocation_type: row.allocation_type,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const allAllocationQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * a.weight_percent), 0) as total
      FROM etf_asset_allocation a
      JOIN asset_weights aw ON a.asset_id = aw.asset_id
    `;
    const totalResult = await pool.query(allAllocationQuery, [ids]);
    const allAllocationTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = allocation.reduce((sum, a) => sum + (a.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allAllocationTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      allocation.push({
        allocation_type: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      allocation,
      count: allocation.length,
      totalPercent: parseFloat((allAllocationTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getAllocationByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo asset allocation multi-portafoglio' });
  }
}

async function getAllocationByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    let query, params, allAllocationQuery, allParams;

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
          a.allocation_type,
          SUM(aw.asset_weight * a.weight_percent) as real_weight
        FROM etf_asset_allocation a
        JOIN asset_weights aw ON a.asset_id = aw.asset_id
        WHERE a.allocation_type NOT IN ('Altri', 'Other', 'Others', 'Altro', 'N/A')
        GROUP BY a.allocation_type
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids, portfolioId];

      allAllocationQuery = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          COALESCE(SUM(aw.asset_weight * a.weight_percent), 0) as total
        FROM etf_asset_allocation a
        JOIN asset_weights aw ON a.asset_id = aw.asset_id
      `;
      allParams = [ids, portfolioId];
    } else {
      query = `
        SELECT
          a.allocation_type,
          AVG(a.weight_percent) as real_weight
        FROM etf_asset_allocation a
        WHERE a.asset_id = ANY($1)
          AND a.allocation_type NOT IN ('Altri', 'Other', 'Others', 'Altro', 'N/A')
        GROUP BY a.allocation_type
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
      params = [ids];

      allAllocationQuery = `
        SELECT
          COALESCE(AVG(total_per_asset), 0) as total
        FROM (
          SELECT asset_id, SUM(weight_percent) as total_per_asset
          FROM etf_asset_allocation
          WHERE asset_id = ANY($1)
          GROUP BY asset_id
        ) t
      `;
      allParams = [ids];
    }

    const result = await pool.query(query, params);

    const allocation = result.rows.map(row => ({
      allocation_type: row.allocation_type,
      weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
    }));

    const totalResult = await pool.query(allAllocationQuery, allParams);
    const allAllocationTotal = parseFloat(totalResult.rows[0].total);

    const shownTotal = allocation.reduce((sum, a) => sum + (a.weighted_percent / 100), 0);
    const othersPercent = Math.max(0, (allAllocationTotal - shownTotal) * 100);

    if (othersPercent > 0.01) {
      allocation.push({
        allocation_type: 'Altri',
        weighted_percent: parseFloat(othersPercent.toFixed(2))
      });
    }

    res.json({
      allocation,
      count: allocation.length,
      totalPercent: parseFloat((allAllocationTotal * 100).toFixed(2))
    });
  } catch (err) {
    console.error('Error in getAllocationByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo asset allocation multi-asset' });
  }
}

async function saveManualAllocation(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { allocation } = req.body;

    if (!allocation || !Array.isArray(allocation)) {
      return res.status(400).json({ error: 'allocation array richiesto' });
    }

    await client.query('BEGIN');
    await client.query('DELETE FROM etf_asset_allocation WHERE asset_id = $1', [assetId]);

    let inserted = 0;
    for (const alloc of allocation) {
      await client.query(
        `INSERT INTO etf_asset_allocation (asset_id, allocation_type, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, alloc.type, alloc.percent / 100]
      );
      inserted++;
    }

    await client.query('COMMIT');

    res.json({
      success: true,
      message: `${inserted} asset allocation salvate con successo`,
      count: inserted
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error in saveManualAllocation:', err);
    res.status(500).json({ error: 'Errore nel salvataggio asset allocation', details: err.message });
  } finally {
    client.release();
  }
}

async function deleteAllocationByAsset(req, res) {
  try {
    const { assetId } = req.params;
    const result = await pool.query('DELETE FROM etf_asset_allocation WHERE asset_id = $1', [assetId]);

    res.json({
      success: true,
      message: `${result.rowCount} asset allocation cancellate`,
      deletedCount: result.rowCount
    });

  } catch (err) {
    console.error('Error in deleteAllocationByAsset:', err);
    res.status(500).json({ error: 'Errore nella cancellazione asset allocation' });
  }
}

module.exports = {
  getAllocationByAsset,
  getAllocationByPortfolio,
  getAllocationByMultiplePortfolios,
  getAllocationByMultipleAssets,
  saveManualAllocation,
  deleteAllocationByAsset,
};

// ============================================
// ALLOCATION ANALYSIS CONTROLLER
// Gestisce l'analisi di asset allocation (Stocks, Bonds, Cash, Commodities, etc.)
// ============================================

const pool = require('../../config/database');
const { calculateLookThrough, calculateMultiPortfolioLookThrough, calculateMultiAssetLookThrough, calculateStats } = require('../../services/compositionCalculator');

/**
 * GET /api/composition/allocation/asset/:assetId
 * Recupera l'asset allocation per un singolo asset
 */
async function getAllocationByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query(
      'SELECT * FROM etf_asset_allocation WHERE asset_id = $1 ORDER BY weight_percent DESC',
      [assetId]
    );

    const stats = calculateStats(result.rows);

    res.json({
      allocation: result.rows,
      stats,
      count: result.rows.length,
    });
  } catch (err) {
    console.error('Error in getAllocationByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero asset allocation' });
  }
}

/**
 * GET /api/composition/allocation/portfolio/:portfolioId
 * Recupera asset allocation aggregata per un portafoglio (look-through corretto)
 */
async function getAllocationByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    const allocation = await calculateLookThrough(
      portfolioId,
      'etf_asset_allocation',
      'allocation_type',
      {
        exclude: ['Altri', 'Other', 'Others', 'Altro', 'N/A'],
        asPercentage: true,
        limit: queryLimit,
      }
    );

    // Converti da percentuale a decimale per calcolare "Altri"
    const allocationDecimal = allocation.map(a => ({
      ...a,
      weighted_percent: a.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = allocationDecimal.reduce((sum, a) => sum + a.weighted_percent, 0);
    
    // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      allocation.push({
        allocation_type: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    const stats = calculateStats(allocation);

    res.json({
      allocation,
      stats,
      count: allocation.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getAllocationByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo asset allocation portafoglio' });
  }
}

/**
 * GET /api/composition/allocation/portfolios/multiple
 * Recupera asset allocation aggregata per più portafogli
 */
async function getAllocationByMultiplePortfolios(req, res) {
  try {
    const { portfolioIds } = req.query;

    if (!portfolioIds) {
      return res.status(400).json({ error: 'portfolioIds query parameter richiesto' });
    }

    const ids = Array.isArray(portfolioIds) ? portfolioIds : portfolioIds.split(',');

    const allocation = await calculateMultiPortfolioLookThrough(
      ids,
      'etf_asset_allocation',
      'allocation_type',
      {
        exclude: ['Altri', 'Other', 'Others', 'Altro', 'N/A'],
        asPercentage: true,
      }
    );

    // Converti da percentuale a decimale per calcolare "Altri"
    const allocationDecimal = allocation.map(a => ({
      ...a,
      weighted_percent: a.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = allocationDecimal.reduce((sum, a) => sum + a.weighted_percent, 0);
    
    // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      allocation.push({
        allocation_type: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    const stats = calculateStats(allocation);

    res.json({
      allocation,
      stats,
      count: allocation.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getAllocationByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo asset allocation multi-portafoglio' });
  }
}

/**
 * GET /api/composition/allocation/assets/multiple
 * Recupera asset allocation aggregata per più asset
 */
async function getAllocationByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');

    let allocation;

    // Calcola "Altri" solo se portfolioId è presente (abbiamo calcolo ponderato)
    if (portfolioId) {
      // Calcolo corretto: divide per il totale di TUTTI gli asset selezionati che hanno dati di allocation
      const allocationQuery = `
        WITH assets_with_allocation AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_asset_allocation a
          JOIN v_current_positions p ON a.asset_id = p.asset_id
          WHERE a.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_allocation
        )
        SELECT
          a.allocation_type,
          SUM(a.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS weighted_percent
        FROM etf_asset_allocation a
        JOIN v_current_positions p ON a.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE a.asset_id = ANY($1) AND p.portfolio_id = $2
          AND a.allocation_type NOT IN ('Altri', 'Other', 'Others', 'Altro', 'N/A')
        GROUP BY a.allocation_type
        ORDER BY weighted_percent DESC
      `;

      const allocationResult = await pool.query(allocationQuery, [ids, portfolioId]);
      
      // Converti da decimale a percentuale
      allocation = allocationResult.rows.map(row => ({
        allocation_type: row.allocation_type,
        weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
      }));

      // Calcola il totale reale includendo TUTTI i tipi di allocation (anche quelli esclusi)
      const allAllocationQuery = `
        WITH assets_with_allocation AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_asset_allocation a
          JOIN v_current_positions p ON a.asset_id = p.asset_id
          WHERE a.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_allocation
        )
        SELECT
          SUM(a.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS total_percent
        FROM etf_asset_allocation a
        JOIN v_current_positions p ON a.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE a.asset_id = ANY($1) AND p.portfolio_id = $2
      `;
      const allAllocationResult = await pool.query(allAllocationQuery, [ids, portfolioId]);
      const totalReal = parseFloat(allAllocationResult.rows[0].total_percent || 0);

      // Log per diagnosticare problemi (se totale > 1.0)
      if (totalReal > 1.01) {
        console.warn(`⚠️  Allocation somma a ${(totalReal * 100).toFixed(2)}% per asset ${ids.join(',')} nel portafoglio ${portfolioId}. Normalizzazione applicata.`);
      }

      // Converti da percentuale a decimale per calcolare "Altri"
      const allocationDecimal = allocation.map(a => ({
        ...a,
        weighted_percent: a.weighted_percent / 100
      }));

      // Calcola la somma delle percentuali mostrate
      const totalShown = allocationDecimal.reduce((sum, a) => sum + a.weighted_percent, 0);
      
      // "Altri" è la differenza tra il totale reale e la somma delle categorie mostrate
      const othersPercent = Math.max(0, totalReal - totalShown);
      
      // Aggiungi "Altri" se > 0
      if (othersPercent > 0.0001) {
        allocation.push({
          allocation_type: 'Altri',
          weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
        });
      }

      // Normalizza tutte le percentuali al 100% se il totale reale è diverso da 1.0
      if (Math.abs(totalReal - 1.0) > 0.01 && totalReal > 0) {
        const normalizationFactor = 1.0 / totalReal;
        allocation.forEach(a => {
          a.weighted_percent = parseFloat((a.weighted_percent * normalizationFactor).toFixed(2));
        });
      }
    } else {
      allocation = await calculateMultiAssetLookThrough(
        ids,
        null,
        'etf_asset_allocation',
        'allocation_type',
        {
          exclude: ['Altri', 'Other', 'Others', 'Altro', 'N/A'],
          asPercentage: true,
        }
      );
    }

    const stats = calculateStats(allocation);

    res.json({
      allocation,
      stats,
      count: allocation.length,
      totalPercent: portfolioId ? 100.0 : undefined, // Solo se portfolioId presente
    });
  } catch (err) {
    console.error('Error in getAllocationByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo asset allocation multi-asset' });
  }
}

/**
 * POST /api/composition/allocation/asset/:assetId
 * Salva manualmente l'asset allocation per un asset
 */
async function saveManualAllocation(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { allocation } = req.body;

    if (!allocation || !Array.isArray(allocation)) {
      return res.status(400).json({ error: 'allocation array richiesto' });
    }

    await client.query('BEGIN');

    // Cancella allocation esistente
    await client.query('DELETE FROM etf_asset_allocation WHERE asset_id = $1', [assetId]);

    // Inserisci nuova allocation
    let inserted = 0;
    for (const alloc of allocation) {
      await client.query(
        `INSERT INTO etf_asset_allocation (asset_id, allocation_type, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, alloc.type, alloc.percent / 100] // Converti da percentuale a decimale
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

/**
 * DELETE /api/composition/allocation/asset/:assetId
 * Cancella l'asset allocation per un asset
 */
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

// ============================================
// BOND MATURITY ANALYSIS CONTROLLER
// Gestisce l'analisi della scadenza obbligazionaria (0-1y, 1-3y, 3-5y, 5-7y, 7-10y, 10y+)
// Include anche calcolo duration media ponderata
// SOLO PER OBBLIGAZIONI
// ============================================

const pool = require('../../config/database');
const { calculateLookThrough, calculateMultiPortfolioLookThrough, calculateMultiAssetLookThrough, calculateStats } = require('../../services/compositionCalculator');

/**
 * GET /api/composition/bond-maturity/asset/:assetId
 * Recupera la maturity obbligazionaria per un singolo asset
 */
async function getBondMaturityByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query(
      'SELECT * FROM etf_bond_maturity WHERE asset_id = $1 ORDER BY weight_percent DESC',
      [assetId]
    );

    // Calcola duration media ponderata
    const avgDuration = result.rows.reduce((sum, row) => {
      const weight = parseFloat(row.weight_percent || 0);
      const duration = parseFloat(row.avg_duration_years || 0);
      return sum + (weight * duration / 100);
    }, 0);

    const stats = {
      ...calculateStats(result.rows),
      avgDuration: parseFloat(avgDuration.toFixed(2))
    };

    res.json({
      bondMaturity: result.rows,
      stats,
      count: result.rows.length,
    });
  } catch (err) {
    console.error('Error in getBondMaturityByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero maturity obbligazionaria' });
  }
}

/**
 * GET /api/composition/bond-maturity/portfolio/:portfolioId
 * Recupera maturity obbligazionaria aggregata per un portafoglio (look-through corretto)
 */
async function getBondMaturityByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    // Query con calcolo duration media
    // Nota: weight_percent nel DB è già decimale (0-1)
    const query = `
      SELECT
        bm.maturity_range,
        SUM(bm.weight_percent * p.current_value) / NULLIF(SUM(p.current_value), 0) AS weighted_percent,
        AVG(bm.avg_duration_years) AS avg_duration_years
      FROM etf_bond_maturity bm
      JOIN v_current_positions p ON bm.asset_id = p.asset_id
      WHERE p.portfolio_id = $1
        AND bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
      GROUP BY bm.maturity_range
      ORDER BY weighted_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    // Converti da decimale a percentuale
    const bondMaturity = result.rows.map(row => ({
      maturity_range: row.maturity_range,
      weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2)),
      avg_duration_years: row.avg_duration_years ? parseFloat(row.avg_duration_years.toFixed(2)) : null
    }));

    // Converti da percentuale a decimale per calcolare "Altri"
    const bondMaturityDecimal = bondMaturity.map(bm => ({
      ...bm,
      weighted_percent: bm.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = bondMaturityDecimal.reduce((sum, bm) => sum + bm.weighted_percent, 0);
    
    // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      bondMaturity.push({
        maturity_range: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2)),
        avg_duration_years: null
      });
    }

    // Calcola duration media ponderata totale
    const avgDuration = bondMaturity.reduce((sum, row) => {
      const weight = parseFloat(row.weighted_percent || 0);
      const duration = parseFloat(row.avg_duration_years || 0);
      return sum + (weight * duration / 100);
    }, 0);

    const stats = {
      ...calculateStats(bondMaturity),
      avgDuration: parseFloat(avgDuration.toFixed(2))
    };

    res.json({
      bondMaturity,
      stats,
      count: bondMaturity.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getBondMaturityByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo maturity obbligazionaria portafoglio' });
  }
}

/**
 * GET /api/composition/bond-maturity/portfolios/multiple
 * Recupera maturity obbligazionaria aggregata per più portafogli
 */
async function getBondMaturityByMultiplePortfolios(req, res) {
  try {
    const { portfolioIds } = req.query;

    if (!portfolioIds) {
      return res.status(400).json({ error: 'portfolioIds query parameter richiesto' });
    }

    const ids = Array.isArray(portfolioIds) ? portfolioIds : portfolioIds.split(',');

    const query = `
      SELECT
        bm.maturity_range,
        SUM(bm.weight_percent * p.current_value) / NULLIF(SUM(p.current_value), 0) AS weighted_percent,
        AVG(bm.avg_duration_years) AS avg_duration_years
      FROM etf_bond_maturity bm
      JOIN v_current_positions p ON bm.asset_id = p.asset_id
      WHERE p.portfolio_id = ANY($1)
        AND bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
      GROUP BY bm.maturity_range
      ORDER BY weighted_percent DESC
    `;

    const result = await pool.query(query, [ids]);

    const bondMaturity = result.rows.map(row => ({
      maturity_range: row.maturity_range,
      weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2)),
      avg_duration_years: row.avg_duration_years ? parseFloat(row.avg_duration_years.toFixed(2)) : null
    }));

    // Converti da percentuale a decimale per calcolare "Altri"
    const bondMaturityDecimal = bondMaturity.map(bm => ({
      ...bm,
      weighted_percent: bm.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = bondMaturityDecimal.reduce((sum, bm) => sum + bm.weighted_percent, 0);
    
    // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      bondMaturity.push({
        maturity_range: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2)),
        avg_duration_years: null
      });
    }

    const avgDuration = bondMaturity.reduce((sum, row) => {
      const weight = parseFloat(row.weighted_percent || 0);
      const duration = parseFloat(row.avg_duration_years || 0);
      return sum + (weight * duration / 100);
    }, 0);

    const stats = {
      ...calculateStats(bondMaturity),
      avgDuration: parseFloat(avgDuration.toFixed(2))
    };

    res.json({
      bondMaturity,
      stats,
      count: bondMaturity.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getBondMaturityByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo maturity obbligazionaria multi-portafoglio' });
  }
}

/**
 * GET /api/composition/bond-maturity/assets/multiple
 * Recupera maturity obbligazionaria aggregata per più asset
 */
async function getBondMaturityByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');

    let query, params;

    if (portfolioId) {
      // Calcolo corretto: divide per il totale di TUTTI gli asset selezionati che hanno dati di maturity
      query = `
        WITH assets_with_maturity AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_bond_maturity bm
          JOIN v_current_positions p ON bm.asset_id = p.asset_id
          WHERE bm.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_maturity
        )
        SELECT
          bm.maturity_range,
          SUM(bm.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS weighted_percent,
          AVG(bm.avg_duration_years) AS avg_duration_years
        FROM etf_bond_maturity bm
        JOIN v_current_positions p ON bm.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE bm.asset_id = ANY($1) AND p.portfolio_id = $2
          AND bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
        GROUP BY bm.maturity_range
        ORDER BY weighted_percent DESC
      `;
      params = [ids, portfolioId];
    } else {
      // Peso uguale per tutti gli asset (media semplice)
      query = `
        SELECT
          bm.maturity_range,
          AVG(bm.weight_percent) AS weighted_percent,
          AVG(bm.avg_duration_years) AS avg_duration_years
        FROM etf_bond_maturity bm
        WHERE bm.asset_id = ANY($1)
          AND bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
        GROUP BY bm.maturity_range
        ORDER BY weighted_percent DESC
      `;
      params = [ids];
    }

    const result = await pool.query(query, params);

    const bondMaturity = result.rows.map(row => ({
      maturity_range: row.maturity_range,
      weighted_percent: portfolioId
        ? parseFloat((row.weighted_percent * 100).toFixed(2))
        : parseFloat(row.weighted_percent.toFixed(2)),
      avg_duration_years: row.avg_duration_years ? parseFloat(row.avg_duration_years.toFixed(2)) : null
    }));

    // Calcola "Altri" solo se portfolioId è presente (abbiamo calcolo ponderato)
    if (portfolioId) {
      // Calcola il totale reale includendo TUTTE le maturity (anche quelle esclusi)
      const allMaturityQuery = `
        WITH assets_with_maturity AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_bond_maturity bm
          JOIN v_current_positions p ON bm.asset_id = p.asset_id
          WHERE bm.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_maturity
        )
        SELECT
          SUM(bm.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS total_percent
        FROM etf_bond_maturity bm
        JOIN v_current_positions p ON bm.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE bm.asset_id = ANY($1) AND p.portfolio_id = $2
      `;
      const allMaturityResult = await pool.query(allMaturityQuery, [ids, portfolioId]);
      const totalReal = parseFloat(allMaturityResult.rows[0].total_percent || 0);

      // Log per diagnosticare problemi (se totale > 1.0)
      if (totalReal > 1.01) {
        console.warn(`⚠️  Bond maturity somma a ${(totalReal * 100).toFixed(2)}% per asset ${ids.join(',')} nel portafoglio ${portfolioId}. Normalizzazione applicata.`);
      }

      // Converti da percentuale a decimale per calcolare "Altri"
      const bondMaturityDecimal = bondMaturity.map(bm => ({
        ...bm,
        weighted_percent: bm.weighted_percent / 100
      }));

      // Calcola la somma delle percentuali mostrate
      const totalShown = bondMaturityDecimal.reduce((sum, bm) => sum + bm.weighted_percent, 0);
      
      // "Altri" è la differenza tra il totale reale e la somma delle categorie mostrate
      const othersPercent = Math.max(0, totalReal - totalShown);
      
      // Aggiungi "Altri" se > 0
      if (othersPercent > 0.0001) {
        bondMaturity.push({
          maturity_range: 'Altri',
          weighted_percent: parseFloat((othersPercent * 100).toFixed(2)),
          avg_duration_years: null
        });
      }

      // Normalizza tutte le percentuali al 100% se il totale reale è diverso da 1.0
      if (Math.abs(totalReal - 1.0) > 0.01 && totalReal > 0) {
        const normalizationFactor = 1.0 / totalReal;
        bondMaturity.forEach(bm => {
          bm.weighted_percent = parseFloat((bm.weighted_percent * normalizationFactor).toFixed(2));
        });
      }
    }

    const avgDuration = bondMaturity.reduce((sum, row) => {
      const weight = parseFloat(row.weighted_percent || 0);
      const duration = parseFloat(row.avg_duration_years || 0);
      return sum + (weight * duration / 100);
    }, 0);

    const stats = {
      ...calculateStats(bondMaturity),
      avgDuration: parseFloat(avgDuration.toFixed(2))
    };

    res.json({
      bondMaturity,
      stats,
      count: bondMaturity.length,
      totalPercent: portfolioId ? 100.0 : undefined, // Solo se portfolioId presente
    });
  } catch (err) {
    console.error('Error in getBondMaturityByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo maturity obbligazionaria multi-asset' });
  }
}

/**
 * POST /api/composition/bond-maturity/asset/:assetId
 * Salva manualmente la maturity obbligazionaria per un asset
 */
async function saveManualBondMaturity(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { bondMaturity } = req.body;

    if (!bondMaturity || !Array.isArray(bondMaturity)) {
      return res.status(400).json({ error: 'bondMaturity array richiesto' });
    }

    await client.query('BEGIN');

    // Cancella maturity esistente
    await client.query('DELETE FROM etf_bond_maturity WHERE asset_id = $1', [assetId]);

    // Inserisci nuova maturity
    let inserted = 0;
    for (const maturity of bondMaturity) {
      await client.query(
        `INSERT INTO etf_bond_maturity (asset_id, maturity_range, weight_percent, avg_duration_years)
         VALUES ($1, $2, $3, $4)`,
        [
          assetId,
          maturity.range,
          maturity.percent / 100, // Converti da percentuale a decimale
          maturity.duration || null
        ]
      );
      inserted++;
    }

    await client.query('COMMIT');

    res.json({
      success: true,
      message: `${inserted} maturity obbligazionarie salvate con successo`,
      count: inserted
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error in saveManualBondMaturity:', err);
    res.status(500).json({ error: 'Errore nel salvataggio maturity obbligazionaria', details: err.message });
  } finally {
    client.release();
  }
}

/**
 * DELETE /api/composition/bond-maturity/asset/:assetId
 * Cancella la maturity obbligazionaria per un asset
 */
async function deleteBondMaturityByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query('DELETE FROM etf_bond_maturity WHERE asset_id = $1', [assetId]);

    res.json({
      success: true,
      message: `${result.rowCount} maturity obbligazionarie cancellate`,
      deletedCount: result.rowCount
    });

  } catch (err) {
    console.error('Error in deleteBondMaturityByAsset:', err);
    res.status(500).json({ error: 'Errore nella cancellazione maturity obbligazionaria' });
  }
}

module.exports = {
  getBondMaturityByAsset,
  getBondMaturityByPortfolio,
  getBondMaturityByMultiplePortfolios,
  getBondMaturityByMultipleAssets,
  saveManualBondMaturity,
  deleteBondMaturityByAsset,
};

// ============================================
// SECTOR ANALYSIS CONTROLLER
// Gestisce l'analisi settoriale (Technology, Healthcare, Financials, etc.)
// ============================================

const pool = require('../../config/database');
const { calculateLookThrough, calculateMultiPortfolioLookThrough, calculateMultiAssetLookThrough, calculateStats } = require('../../services/compositionCalculator');

/**
 * GET /api/composition/sectors/asset/:assetId
 * Recupera la composizione settoriale per un singolo asset
 */
async function getSectorsByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query(
      'SELECT * FROM etf_sector_weights WHERE asset_id = $1 ORDER BY weight_percent DESC',
      [assetId]
    );

    const stats = calculateStats(result.rows);

    res.json({
      sectors: result.rows,
      stats,
      count: result.rows.length,
    });
  } catch (err) {
    console.error('Error in getSectorsByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero settori' });
  }
}

/**
 * GET /api/composition/sectors/portfolio/:portfolioId
 * Recupera composizione settoriale aggregata per un portafoglio (look-through corretto)
 */
async function getSectorsByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    // Prima calcola il totale reale di TUTTE le categorie (incluso quelle escluse)
    const allSectors = await calculateLookThrough(
      portfolioId,
      'etf_sector_weights',
      'sector_name',
      {
        exclude: [], // Non escludere nulla per calcolare il totale reale
        asPercentage: false, // Restituisci in formato decimale per calcoli
      }
    );

    // Calcola il totale reale (somma di tutte le categorie)
    const totalReal = allSectors.reduce((sum, s) => sum + s.weighted_percent, 0);

    // Log per diagnosticare problemi (se totale > 1.0)
    if (totalReal > 1.01) {
      console.warn(`⚠️  Settori sommano a ${(totalReal * 100).toFixed(2)}% per portafoglio ${portfolioId}. Possibili cause: duplicati o dati errati nel database.`);
    }

    // Ora calcola solo le categorie mostrate (escludendo quelle da filtrare)
    const sectors = await calculateLookThrough(
      portfolioId,
      'etf_sector_weights',
      'sector_name',
      {
        exclude: ['Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A'],
        asPercentage: true, // Restituisci in formato percentuale (25.5 invece di 0.255)
        limit: queryLimit,
      }
    );

    // Converti da percentuale a decimale per calcolare "Altri"
    const sectorsDecimal = sectors.map(s => ({
      ...s,
      weighted_percent: s.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = sectorsDecimal.reduce((sum, s) => sum + s.weighted_percent, 0);
    
    // "Altri" è la differenza tra il totale reale e la somma delle categorie mostrate
    // Se il totale reale è > 1.0, significa che alcuni asset hanno settori che sommano a più del 100%
    const othersPercent = Math.max(0, totalReal - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      sectors.push({
        sector_name: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    // Normalizza tutte le percentuali al 100% se il totale reale è diverso da 1.0
    // Questo gestisce il caso in cui alcuni asset hanno settori che sommano a più del 100%
    if (Math.abs(totalReal - 1.0) > 0.01 && totalReal > 0) {
      const normalizationFactor = 1.0 / totalReal;
      sectors.forEach(s => {
        s.weighted_percent = parseFloat((s.weighted_percent * normalizationFactor).toFixed(2));
      });
    }

    const stats = calculateStats(sectors);

    res.json({
      sectors,
      stats,
      count: sectors.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
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

    // Prima calcola il totale reale di TUTTE le categorie (incluso quelle escluse)
    const allSectors = await calculateMultiPortfolioLookThrough(
      ids,
      'etf_sector_weights',
      'sector_name',
      {
        exclude: [], // Non escludere nulla per calcolare il totale reale
        asPercentage: false, // Restituisci in formato decimale per calcoli
      }
    );

    // Calcola il totale reale (somma di tutte le categorie)
    const totalReal = allSectors.reduce((sum, s) => sum + s.weighted_percent, 0);

    // Log per diagnosticare problemi (se totale > 1.0)
    if (totalReal > 1.01) {
      console.warn(`⚠️  Settori sommano a ${(totalReal * 100).toFixed(2)}% per portafogli ${ids.join(',')}. Possibili cause: duplicati o dati errati nel database.`);
    }

    // Ora calcola solo le categorie mostrate (escludendo quelle da filtrare)
    const sectors = await calculateMultiPortfolioLookThrough(
      ids,
      'etf_sector_weights',
      'sector_name',
      {
        exclude: ['Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A'],
        asPercentage: true,
        limit: queryLimit,
      }
    );

    // Converti da percentuale a decimale per calcolare "Altri"
    const sectorsDecimal = sectors.map(s => ({
      ...s,
      weighted_percent: s.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = sectorsDecimal.reduce((sum, s) => sum + s.weighted_percent, 0);
    
    // "Altri" è la differenza tra il totale reale e la somma delle categorie mostrate
    const othersPercent = Math.max(0, totalReal - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      sectors.push({
        sector_name: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    // Normalizza tutte le percentuali al 100% se il totale reale è diverso da 1.0
    if (Math.abs(totalReal - 1.0) > 0.01 && totalReal > 0) {
      const normalizationFactor = 1.0 / totalReal;
      sectors.forEach(s => {
        s.weighted_percent = parseFloat((s.weighted_percent * normalizationFactor).toFixed(2));
      });
    }

    const stats = calculateStats(sectors);

    res.json({
      sectors,
      stats,
      count: sectors.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
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

    let sectors;

    // Calcola "Altri" solo se portfolioId è presente (abbiamo calcolo ponderato)
    if (portfolioId) {
      // Calcolo corretto: divide per il totale di TUTTI gli asset selezionati che hanno dati settoriali
      // Prima calcola il totale di tutti gli asset con dati settoriali
      const totalAssetsQuery = `
        WITH assets_with_sectors AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_sector_weights s
          JOIN v_current_positions p ON s.asset_id = p.asset_id
          WHERE s.asset_id = ANY($1) AND p.portfolio_id = $2
        )
        SELECT COALESCE(SUM(current_value), 0) AS total_value
        FROM assets_with_sectors
      `;
      const totalAssetsResult = await pool.query(totalAssetsQuery, [ids, portfolioId]);
      const totalAssetsValue = parseFloat(totalAssetsResult.rows[0].total_value);

      // Query per calcolare i settori dividendo per il totale corretto
      const sectorsQuery = `
        WITH assets_with_sectors AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_sector_weights s
          JOIN v_current_positions p ON s.asset_id = p.asset_id
          WHERE s.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_sectors
        )
        SELECT
          s.sector_name,
          SUM(s.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS weighted_percent
        FROM etf_sector_weights s
        JOIN v_current_positions p ON s.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE s.asset_id = ANY($1) AND p.portfolio_id = $2
          AND s.sector_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A')
        GROUP BY s.sector_name
        ORDER BY weighted_percent DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;

      const sectorsResult = await pool.query(sectorsQuery, [ids, portfolioId]);
      
      // Converti da decimale a percentuale
      sectors = sectorsResult.rows.map(row => ({
        sector_name: row.sector_name,
        weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
      }));

      // Calcola il totale reale includendo TUTTI i settori (anche quelli esclusi)
      const allSectorsQuery = `
        WITH assets_with_sectors AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_sector_weights s
          JOIN v_current_positions p ON s.asset_id = p.asset_id
          WHERE s.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_sectors
        )
        SELECT
          SUM(s.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS total_percent
        FROM etf_sector_weights s
        JOIN v_current_positions p ON s.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE s.asset_id = ANY($1) AND p.portfolio_id = $2
      `;
      const allSectorsResult = await pool.query(allSectorsQuery, [ids, portfolioId]);
      const totalReal = parseFloat(allSectorsResult.rows[0].total_percent || 0);

      // Log per diagnosticare problemi (se totale > 1.0)
      if (totalReal > 1.01) {
        console.warn(`⚠️  Settori sommano a ${(totalReal * 100).toFixed(2)}% per asset ${ids.join(',')} nel portafoglio ${portfolioId}. Normalizzazione applicata.`);
      }

      // Converti da percentuale a decimale per calcolare "Altri"
      const sectorsDecimal = sectors.map(s => ({
        ...s,
        weighted_percent: s.weighted_percent / 100
      }));

      // Calcola la somma delle percentuali mostrate
      const totalShown = sectorsDecimal.reduce((sum, s) => sum + s.weighted_percent, 0);
      
      // "Altri" è la differenza tra il totale reale e la somma delle categorie mostrate
      const othersPercent = Math.max(0, totalReal - totalShown);
      
      // Aggiungi "Altri" se > 0
      if (othersPercent > 0.0001) {
        sectors.push({
          sector_name: 'Altri',
          weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
        });
      }

      // Normalizza tutte le percentuali al 100% se il totale reale è diverso da 1.0
      // Questo gestisce il caso in cui alcuni asset hanno settori che sommano a più del 100%
      if (Math.abs(totalReal - 1.0) > 0.01 && totalReal > 0) {
        const normalizationFactor = 1.0 / totalReal;
        sectors.forEach(s => {
          s.weighted_percent = parseFloat((s.weighted_percent * normalizationFactor).toFixed(2));
        });
      }
    } else {
      sectors = await calculateMultiAssetLookThrough(
        ids,
        null,
        'etf_sector_weights',
        'sector_name',
        {
          exclude: ['Altri', 'Other', 'Others', 'Altro', 'Miscellaneous', 'N/A'],
          asPercentage: true,
          limit: queryLimit,
        }
      );
    }

    const stats = calculateStats(sectors);

    res.json({
      sectors,
      stats,
      count: sectors.length,
      totalPercent: portfolioId ? 100.0 : undefined, // Solo se portfolioId presente
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

    // Cancella settori esistenti
    await client.query('DELETE FROM etf_sector_weights WHERE asset_id = $1', [assetId]);

    // Inserisci nuovi settori
    let inserted = 0;
    for (const sector of sectors) {
      await client.query(
        `INSERT INTO etf_sector_weights (asset_id, sector_name, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, sector.name, sector.percent / 100] // Converti da percentuale a decimale
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
 * Query params: portfolioId, sectorName
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

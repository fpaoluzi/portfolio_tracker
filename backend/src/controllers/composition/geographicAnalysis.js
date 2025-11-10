// ============================================
// GEOGRAPHIC ANALYSIS CONTROLLER
// Gestisce l'analisi geografica (USA, Europa, Asia, etc.)
// Include normalizzazione nomi paesi
// ============================================

const pool = require('../../config/database');
const { calculateLookThrough, calculateMultiPortfolioLookThrough, calculateMultiAssetLookThrough, calculateStats } = require('../../services/compositionCalculator');

/**
 * Mapping per normalizzare nomi geografici in italiano
 */
const REGION_NAME_TRANSFORM = `
  CASE
    WHEN g.region_name IN ('United States', 'USA', 'US') THEN 'Stati Uniti'
    WHEN g.region_name IN ('United Kingdom', 'UK', 'Great Britain') THEN 'Regno Unito'
    WHEN g.region_name IN ('Japan') THEN 'Giappone'
    WHEN g.region_name IN ('France') THEN 'Francia'
    WHEN g.region_name IN ('Germany') THEN 'Germania'
    WHEN g.region_name IN ('Netherlands', 'Olanda', 'Paesi bassi') THEN 'Paesi Bassi'
    WHEN g.region_name IN ('Spain') THEN 'Spagna'
    WHEN g.region_name IN ('Italy') THEN 'Italia'
    WHEN g.region_name IN ('Switzerland') THEN 'Svizzera'
    WHEN g.region_name IN ('Belgium') THEN 'Belgio'
    WHEN g.region_name IN ('Austria') THEN 'Austria'
    WHEN g.region_name IN ('Sweden') THEN 'Svezia'
    WHEN g.region_name IN ('Denmark') THEN 'Danimarca'
    WHEN g.region_name IN ('Finland') THEN 'Finlandia'
    WHEN g.region_name IN ('Norway') THEN 'Norvegia'
    WHEN g.region_name IN ('Portugal') THEN 'Portogallo'
    WHEN g.region_name IN ('Ireland') THEN 'Irlanda'
    WHEN g.region_name IN ('Poland') THEN 'Polonia'
    WHEN g.region_name IN ('South Korea', 'Korea') THEN 'Corea del Sud'
    WHEN g.region_name IN ('China') THEN 'Cina'
    WHEN g.region_name IN ('Canada') THEN 'Canada'
    WHEN g.region_name IN ('Australia') THEN 'Australia'
    WHEN g.region_name IN ('Brazil') THEN 'Brasile'
    WHEN g.region_name IN ('India') THEN 'India'
    WHEN g.region_name IN ('Mexico') THEN 'Messico'
    WHEN g.region_name IN ('Russia') THEN 'Russia'
    WHEN g.region_name IN ('Hong Kong') THEN 'Hong Kong'
    WHEN g.region_name IN ('Singapore') THEN 'Singapore'
    WHEN g.region_name IN ('Taiwan') THEN 'Taiwan'
    ELSE g.region_name
  END
`;

/**
 * GET /api/composition/geographic/asset/:assetId
 * Recupera la composizione geografica per un singolo asset
 */
async function getGeographicByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query(
      'SELECT * FROM etf_geographic_weights WHERE asset_id = $1 ORDER BY weight_percent DESC',
      [assetId]
    );

    const stats = calculateStats(result.rows);

    res.json({
      regions: result.rows,
      stats,
      count: result.rows.length,
    });
  } catch (err) {
    console.error('Error in getGeographicByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero composizione geografica' });
  }
}

/**
 * GET /api/composition/geographic/portfolio/:portfolioId
 * Recupera composizione geografica aggregata per un portafoglio (look-through corretto)
 */
async function getGeographicByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    // Prima calcola il totale reale di TUTTE le categorie (incluso quelle escluse)
    const allRegionsQuery = `
      SELECT
        ${REGION_NAME_TRANSFORM} as region_name,
        SUM(g.weight_percent * p.current_value) / NULLIF(SUM(p.current_value), 0) AS weighted_percent
      FROM etf_geographic_weights g
      JOIN v_current_positions p ON g.asset_id = p.asset_id
      WHERE p.portfolio_id = $1
      GROUP BY ${REGION_NAME_TRANSFORM}
    `;

    const allRegionsResult = await pool.query(allRegionsQuery, [portfolioId]);
    const totalReal = allRegionsResult.rows.reduce((sum, r) => sum + parseFloat(r.weighted_percent || 0), 0);

    // Log per diagnosticare problemi (se totale > 1.0)
    if (totalReal > 1.01) {
      console.warn(`⚠️  Regioni sommano a ${(totalReal * 100).toFixed(2)}% per portafoglio ${portfolioId}. Possibili cause: duplicati o dati errati nel database.`);
    }

    // Query con normalizzazione nomi
    // Nota: weight_percent nel DB è già decimale (0-1), es. 0.65 = 65%
    const query = `
      SELECT
        ${REGION_NAME_TRANSFORM} as region_name,
        SUM(g.weight_percent * p.current_value) / NULLIF(SUM(p.current_value), 0) AS weighted_percent
      FROM etf_geographic_weights g
      JOIN v_current_positions p ON g.asset_id = p.asset_id
      WHERE p.portfolio_id = $1
        AND g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
      GROUP BY ${REGION_NAME_TRANSFORM}
      ORDER BY weighted_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

    const result = await pool.query(query, [portfolioId]);

    // Converti da decimale a percentuale
    const regions = result.rows.map(row => ({
      region_name: row.region_name,
      weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
    }));

    // Converti da percentuale a decimale per calcolare "Altri"
    const regionsDecimal = regions.map(r => ({
      ...r,
      weighted_percent: r.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = regionsDecimal.reduce((sum, r) => sum + r.weighted_percent, 0);
    
    // "Altri" è la differenza tra il totale reale e la somma delle categorie mostrate
    const othersPercent = Math.max(0, totalReal - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    // Normalizza tutte le percentuali al 100% se il totale reale è diverso da 1.0
    if (Math.abs(totalReal - 1.0) > 0.01 && totalReal > 0) {
      const normalizationFactor = 1.0 / totalReal;
      regions.forEach(r => {
        r.weighted_percent = parseFloat((r.weighted_percent * normalizationFactor).toFixed(2));
      });
    }

    const stats = calculateStats(regions);

    res.json({
      regions,
      stats,
      count: regions.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getGeographicByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo composizione geografica portafoglio' });
  }
}

/**
 * GET /api/composition/geographic/portfolios/multiple
 * Recupera composizione geografica aggregata per più portafogli
 */
async function getGeographicByMultiplePortfolios(req, res) {
  try {
    const { portfolioIds } = req.query;

    if (!portfolioIds) {
      return res.status(400).json({ error: 'portfolioIds query parameter richiesto' });
    }

    const ids = Array.isArray(portfolioIds) ? portfolioIds : portfolioIds.split(',');

    const query = `
      SELECT
        ${REGION_NAME_TRANSFORM} as region_name,
        SUM(g.weight_percent * p.current_value) / NULLIF(SUM(p.current_value), 0) AS weighted_percent
      FROM etf_geographic_weights g
      JOIN v_current_positions p ON g.asset_id = p.asset_id
      WHERE p.portfolio_id = ANY($1)
        AND g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
      GROUP BY ${REGION_NAME_TRANSFORM}
      ORDER BY weighted_percent DESC
    `;

    const result = await pool.query(query, [ids]);

    const regions = result.rows.map(row => ({
      region_name: row.region_name,
      weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
    }));

    // Converti da percentuale a decimale per calcolare "Altri"
    const regionsDecimal = regions.map(r => ({
      ...r,
      weighted_percent: r.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = regionsDecimal.reduce((sum, r) => sum + r.weighted_percent, 0);
    
    // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      regions.push({
        region_name: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    const stats = calculateStats(regions);

    res.json({
      regions,
      stats,
      count: regions.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getGeographicByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo composizione geografica multi-portafoglio' });
  }
}

/**
 * GET /api/composition/geographic/assets/multiple
 * Recupera composizione geografica aggregata per più asset
 */
async function getGeographicByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');

    let query, params;

    if (portfolioId) {
      // Pesa in base al valore delle posizioni nel portafoglio
      // Calcolo corretto: divide per il totale di TUTTI gli asset selezionati che hanno dati geografici
      query = `
        WITH assets_with_geographic AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_geographic_weights g
          JOIN v_current_positions p ON g.asset_id = p.asset_id
          WHERE g.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_geographic_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_geographic
        )
        SELECT
          ${REGION_NAME_TRANSFORM} as region_name,
          SUM(g.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_geographic_value), 0) AS weighted_percent
        FROM etf_geographic_weights g
        JOIN v_current_positions p ON g.asset_id = p.asset_id
        CROSS JOIN total_geographic_value
        WHERE g.asset_id = ANY($1) AND p.portfolio_id = $2
          AND g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
        GROUP BY ${REGION_NAME_TRANSFORM}
        ORDER BY weighted_percent DESC
      `;
      params = [ids, portfolioId];
    } else {
      // Peso uguale per tutti gli asset (media semplice)
      query = `
        SELECT
          ${REGION_NAME_TRANSFORM} as region_name,
          AVG(g.weight_percent) AS weighted_percent
        FROM etf_geographic_weights g
        WHERE g.asset_id = ANY($1)
          AND g.region_name NOT IN ('Altri', 'Other', 'Others', 'Altro', 'Rest of World', 'N/A')
        GROUP BY ${REGION_NAME_TRANSFORM}
        ORDER BY weighted_percent DESC
      `;
      params = [ids];
    }

    const result = await pool.query(query, params);

    const regions = result.rows.map(row => ({
      region_name: row.region_name,
      weighted_percent: portfolioId
        ? parseFloat((row.weighted_percent * 100).toFixed(2))
        : parseFloat(row.weighted_percent.toFixed(2))
    }));

    // Calcola "Altri" solo se portfolioId è presente (abbiamo calcolo ponderato)
    if (portfolioId) {
      // Converti da percentuale a decimale per calcolare "Altri"
      const regionsDecimal = regions.map(r => ({
        ...r,
        weighted_percent: r.weighted_percent / 100
      }));

      // Calcola la somma delle percentuali mostrate
      const totalShown = regionsDecimal.reduce((sum, r) => sum + r.weighted_percent, 0);
      
      // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
      const othersPercent = Math.max(0, 1.0 - totalShown);
      
      // Aggiungi "Altri" se > 0
      if (othersPercent > 0.0001) {
        regions.push({
          region_name: 'Altri',
          weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
        });
      }
    }

    const stats = calculateStats(regions);

    res.json({
      regions,
      stats,
      count: regions.length,
      totalPercent: portfolioId ? 100.0 : undefined, // Solo se portfolioId presente
    });
  } catch (err) {
    console.error('Error in getGeographicByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo composizione geografica multi-asset' });
  }
}

/**
 * POST /api/composition/geographic/asset/:assetId
 * Salva manualmente la composizione geografica per un asset
 */
async function saveManualGeographic(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { regions } = req.body;

    if (!regions || !Array.isArray(regions)) {
      return res.status(400).json({ error: 'regions array richiesto' });
    }

    await client.query('BEGIN');

    // Cancella regioni esistenti
    await client.query('DELETE FROM etf_geographic_weights WHERE asset_id = $1', [assetId]);

    // Inserisci nuove regioni
    let inserted = 0;
    for (const region of regions) {
      await client.query(
        `INSERT INTO etf_geographic_weights (asset_id, region_name, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, region.name, region.percent / 100] // Converti da percentuale a decimale
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

/**
 * DELETE /api/composition/geographic/asset/:assetId
 * Cancella la composizione geografica per un asset
 */
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

/**
 * GET /api/composition/geographic/detail
 * Recupera dettagli degli asset che contengono una specifica regione
 * Query params: portfolioId, regionName
 */
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
        AND ${REGION_NAME_TRANSFORM} = $2
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

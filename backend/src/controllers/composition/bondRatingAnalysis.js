// ============================================
// BOND RATING ANALYSIS CONTROLLER
// Gestisce l'analisi dei rating obbligazionari (AAA, AA, A, BBB, BB, etc.)
// SOLO PER OBBLIGAZIONI
// ============================================

const pool = require('../../config/database');
const { calculateLookThrough, calculateMultiPortfolioLookThrough, calculateMultiAssetLookThrough, calculateStats } = require('../../services/compositionCalculator');

/**
 * GET /api/composition/bond-ratings/asset/:assetId
 * Recupera i rating obbligazionari per un singolo asset
 */
async function getBondRatingsByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query(
      'SELECT * FROM etf_bond_ratings WHERE asset_id = $1 ORDER BY weight_percent DESC',
      [assetId]
    );

    const stats = calculateStats(result.rows);

    res.json({
      bondRatings: result.rows,
      stats,
      count: result.rows.length,
    });
  } catch (err) {
    console.error('Error in getBondRatingsByAsset:', err);
    res.status(500).json({ error: 'Errore nel recupero rating obbligazionari' });
  }
}

/**
 * GET /api/composition/bond-ratings/portfolio/:portfolioId
 * Recupera rating obbligazionari aggregati per un portafoglio (look-through corretto)
 */
async function getBondRatingsByPortfolio(req, res) {
  try {
    const { portfolioId } = req.params;
    const { expand = 'false', limit = 15 } = req.query;
    const shouldExpand = expand === 'true' || expand === true;
    const queryLimit = shouldExpand ? null : parseInt(limit, 10);

    const bondRatings = await calculateLookThrough(
      portfolioId,
      'etf_bond_ratings',
      'rating_category',
      {
        exclude: ['N/A', 'Not Rated', 'NR'],
        asPercentage: true,
        limit: queryLimit,
      }
    );

    // Converti da percentuale a decimale per calcolare "Altri"
    const bondRatingsDecimal = bondRatings.map(br => ({
      ...br,
      weighted_percent: br.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = bondRatingsDecimal.reduce((sum, br) => sum + br.weighted_percent, 0);
    
    // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      bondRatings.push({
        rating_category: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    const stats = calculateStats(bondRatings);

    res.json({
      bondRatings,
      stats,
      count: bondRatings.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getBondRatingsByPortfolio:', err);
    res.status(500).json({ error: 'Errore nel calcolo rating obbligazionari portafoglio' });
  }
}

/**
 * GET /api/composition/bond-ratings/portfolios/multiple
 * Recupera rating obbligazionari aggregati per più portafogli
 */
async function getBondRatingsByMultiplePortfolios(req, res) {
  try {
    const { portfolioIds } = req.query;

    if (!portfolioIds) {
      return res.status(400).json({ error: 'portfolioIds query parameter richiesto' });
    }

    const ids = Array.isArray(portfolioIds) ? portfolioIds : portfolioIds.split(',');

    const bondRatings = await calculateMultiPortfolioLookThrough(
      ids,
      'etf_bond_ratings',
      'rating_category',
      {
        exclude: ['N/A', 'Not Rated', 'NR'],
        asPercentage: true,
      }
    );

    // Converti da percentuale a decimale per calcolare "Altri"
    const bondRatingsDecimal = bondRatings.map(br => ({
      ...br,
      weighted_percent: br.weighted_percent / 100
    }));

    // Calcola la somma delle percentuali mostrate
    const totalShown = bondRatingsDecimal.reduce((sum, br) => sum + br.weighted_percent, 0);
    
    // "Altri" è la differenza tra 100% e la somma delle categorie mostrate
    const othersPercent = Math.max(0, 1.0 - totalShown);
    
    // Aggiungi "Altri" se > 0
    if (othersPercent > 0.0001) {
      bondRatings.push({
        rating_category: 'Altri',
        weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
      });
    }

    const stats = calculateStats(bondRatings);

    res.json({
      bondRatings,
      stats,
      count: bondRatings.length,
      totalPercent: 100.0, // Sempre 100% quando includiamo "Altri"
    });
  } catch (err) {
    console.error('Error in getBondRatingsByMultiplePortfolios:', err);
    res.status(500).json({ error: 'Errore nel calcolo rating obbligazionari multi-portafoglio' });
  }
}

/**
 * GET /api/composition/bond-ratings/assets/multiple
 * Recupera rating obbligazionari aggregati per più asset
 */
async function getBondRatingsByMultipleAssets(req, res) {
  try {
    const { assetIds, portfolioId } = req.query;

    if (!assetIds) {
      return res.status(400).json({ error: 'assetIds query parameter richiesto' });
    }

    const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');

    let bondRatings;

    // Calcola "Altri" solo se portfolioId è presente (abbiamo calcolo ponderato)
    if (portfolioId) {
      // Calcolo corretto: divide per il totale di TUTTI gli asset selezionati che hanno dati di rating
      const ratingsQuery = `
        WITH assets_with_ratings AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_bond_ratings br
          JOIN v_current_positions p ON br.asset_id = p.asset_id
          WHERE br.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_ratings
        )
        SELECT
          br.rating_category,
          SUM(br.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS weighted_percent
        FROM etf_bond_ratings br
        JOIN v_current_positions p ON br.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE br.asset_id = ANY($1) AND p.portfolio_id = $2
          AND br.rating_category NOT IN ('N/A', 'Not Rated', 'NR')
        GROUP BY br.rating_category
        ORDER BY weighted_percent DESC
      `;

      const ratingsResult = await pool.query(ratingsQuery, [ids, portfolioId]);
      
      // Converti da decimale a percentuale
      bondRatings = ratingsResult.rows.map(row => ({
        rating_category: row.rating_category,
        weighted_percent: parseFloat((row.weighted_percent * 100).toFixed(2))
      }));

      // Calcola il totale reale includendo TUTTI i rating (anche quelli esclusi)
      const allRatingsQuery = `
        WITH assets_with_ratings AS (
          SELECT DISTINCT p.asset_id, p.current_value
          FROM etf_bond_ratings br
          JOIN v_current_positions p ON br.asset_id = p.asset_id
          WHERE br.asset_id = ANY($1) AND p.portfolio_id = $2
        ),
        total_assets_value AS (
          SELECT COALESCE(SUM(current_value), 0) AS total_value
          FROM assets_with_ratings
        )
        SELECT
          SUM(br.weight_percent * p.current_value) / NULLIF((SELECT total_value FROM total_assets_value), 0) AS total_percent
        FROM etf_bond_ratings br
        JOIN v_current_positions p ON br.asset_id = p.asset_id
        CROSS JOIN total_assets_value
        WHERE br.asset_id = ANY($1) AND p.portfolio_id = $2
      `;
      const allRatingsResult = await pool.query(allRatingsQuery, [ids, portfolioId]);
      const totalReal = parseFloat(allRatingsResult.rows[0].total_percent || 0);

      // Log per diagnosticare problemi (se totale > 1.0)
      if (totalReal > 1.01) {
        console.warn(`⚠️  Bond ratings sommano a ${(totalReal * 100).toFixed(2)}% per asset ${ids.join(',')} nel portafoglio ${portfolioId}. Normalizzazione applicata.`);
      }

      // Converti da percentuale a decimale per calcolare "Altri"
      const bondRatingsDecimal = bondRatings.map(br => ({
        ...br,
        weighted_percent: br.weighted_percent / 100
      }));

      // Calcola la somma delle percentuali mostrate
      const totalShown = bondRatingsDecimal.reduce((sum, br) => sum + br.weighted_percent, 0);
      
      // "Altri" è la differenza tra il totale reale e la somma delle categorie mostrate
      const othersPercent = Math.max(0, totalReal - totalShown);
      
      // Aggiungi "Altri" se > 0
      if (othersPercent > 0.0001) {
        bondRatings.push({
          rating_category: 'Altri',
          weighted_percent: parseFloat((othersPercent * 100).toFixed(2))
        });
      }

      // Normalizza tutte le percentuali al 100% se il totale reale è diverso da 1.0
      if (Math.abs(totalReal - 1.0) > 0.01 && totalReal > 0) {
        const normalizationFactor = 1.0 / totalReal;
        bondRatings.forEach(br => {
          br.weighted_percent = parseFloat((br.weighted_percent * normalizationFactor).toFixed(2));
        });
      }
    } else {
      bondRatings = await calculateMultiAssetLookThrough(
        ids,
        null,
        'etf_bond_ratings',
        'rating_category',
        {
          exclude: ['N/A', 'Not Rated', 'NR'],
          asPercentage: true,
        }
      );
    }

    const stats = calculateStats(bondRatings);

    res.json({
      bondRatings,
      stats,
      count: bondRatings.length,
      totalPercent: portfolioId ? 100.0 : undefined, // Solo se portfolioId presente
    });
  } catch (err) {
    console.error('Error in getBondRatingsByMultipleAssets:', err);
    res.status(500).json({ error: 'Errore nel calcolo rating obbligazionari multi-asset' });
  }
}

/**
 * POST /api/composition/bond-ratings/asset/:assetId
 * Salva manualmente i rating obbligazionari per un asset
 */
async function saveManualBondRatings(req, res) {
  const client = await pool.connect();

  try {
    const { assetId } = req.params;
    const { bondRatings } = req.body;

    if (!bondRatings || !Array.isArray(bondRatings)) {
      return res.status(400).json({ error: 'bondRatings array richiesto' });
    }

    await client.query('BEGIN');

    // Cancella ratings esistenti
    await client.query('DELETE FROM etf_bond_ratings WHERE asset_id = $1', [assetId]);

    // Inserisci nuovi ratings
    let inserted = 0;
    for (const rating of bondRatings) {
      await client.query(
        `INSERT INTO etf_bond_ratings (asset_id, rating_category, weight_percent)
         VALUES ($1, $2, $3)`,
        [assetId, rating.category, rating.percent / 100] // Converti da percentuale a decimale
      );
      inserted++;
    }

    await client.query('COMMIT');

    res.json({
      success: true,
      message: `${inserted} rating obbligazionari salvati con successo`,
      count: inserted
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error in saveManualBondRatings:', err);
    res.status(500).json({ error: 'Errore nel salvataggio rating obbligazionari', details: err.message });
  } finally {
    client.release();
  }
}

/**
 * DELETE /api/composition/bond-ratings/asset/:assetId
 * Cancella i rating obbligazionari per un asset
 */
async function deleteBondRatingsByAsset(req, res) {
  try {
    const { assetId } = req.params;

    const result = await pool.query('DELETE FROM etf_bond_ratings WHERE asset_id = $1', [assetId]);

    res.json({
      success: true,
      message: `${result.rowCount} rating obbligazionari cancellati`,
      deletedCount: result.rowCount
    });

  } catch (err) {
    console.error('Error in deleteBondRatingsByAsset:', err);
    res.status(500).json({ error: 'Errore nella cancellazione rating obbligazionari' });
  }
}

module.exports = {
  getBondRatingsByAsset,
  getBondRatingsByPortfolio,
  getBondRatingsByMultiplePortfolios,
  getBondRatingsByMultipleAssets,
  saveManualBondRatings,
  deleteBondRatingsByAsset,
};

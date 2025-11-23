// ============================================
// BOND RATING ANALYSIS CONTROLLER
// Gestisce l'analisi dei rating obbligazionari (AAA, AA, A, BBB, etc.)
// LOGICA CORRETTA: Peso reale = Peso_Asset × Peso_Rating
// SOLO PER OBBLIGAZIONI
// ============================================

const pool = require('../../config/database');

async function getBondRatingsByAsset(req, res) {
    try {
        const { assetId } = req.params;
        const { limit = 15 } = req.query;
        const queryLimit = parseInt(limit, 10);

        const ratingsQuery = `
      SELECT 
        rating_category,
        weight_percent
      FROM etf_bond_ratings
      WHERE asset_id = $1
      ORDER BY weight_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

        const result = await pool.query(ratingsQuery, [assetId]);

        const bondRatings = result.rows.map(row => ({
            rating_category: row.rating_category,
            weighted_percent: parseFloat((row.weight_percent * 100).toFixed(2))
        }));

        const allRatingsQuery = `
      SELECT COALESCE(SUM(weight_percent), 0) as total
      FROM etf_bond_ratings
      WHERE asset_id = $1
    `;
        const totalResult = await pool.query(allRatingsQuery, [assetId]);
        const allRatingsTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondRatings.reduce((sum, br) => sum + (br.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allRatingsTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondRatings.push({
                rating_category: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2))
            });
        }

        res.json({
            bondRatings,
            count: bondRatings.length,
            totalPercent: parseFloat((allRatingsTotal * 100).toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondRatingsByAsset:', err);
        res.status(500).json({ error: 'Errore nel recupero rating obbligazionari' });
    }
}

async function getBondRatingsByPortfolio(req, res) {
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
        br.rating_category,
        SUM(aw.asset_weight * br.weight_percent) as real_weight
      FROM etf_bond_ratings br
      JOIN asset_weights aw ON br.asset_id = aw.asset_id
      WHERE br.rating_category NOT IN ('N/A', 'Not Rated', 'NR')
      GROUP BY br.rating_category
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

        const result = await pool.query(query, [portfolioId]);

        const bondRatings = result.rows.map(row => ({
            rating_category: row.rating_category,
            weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
        }));

        const allRatingsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * br.weight_percent), 0) as total
      FROM etf_bond_ratings br
      JOIN asset_weights aw ON br.asset_id = aw.asset_id
    `;
        const totalResult = await pool.query(allRatingsQuery, [portfolioId]);
        const allRatingsTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondRatings.reduce((sum, br) => sum + (br.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allRatingsTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondRatings.push({
                rating_category: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2))
            });
        }

        res.json({
            bondRatings,
            count: bondRatings.length,
            totalPercent: parseFloat((allRatingsTotal * 100).toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondRatingsByPortfolio:', err);
        res.status(500).json({ error: 'Errore nel calcolo rating obbligazionari portafoglio' });
    }
}

async function getBondRatingsByMultiplePortfolios(req, res) {
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
        br.rating_category,
        SUM(aw.asset_weight * br.weight_percent) as real_weight
      FROM etf_bond_ratings br
      JOIN asset_weights aw ON br.asset_id = aw.asset_id
      WHERE br.rating_category NOT IN ('N/A', 'Not Rated', 'NR')
      GROUP BY br.rating_category
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

        const result = await pool.query(query, [ids]);

        const bondRatings = result.rows.map(row => ({
            rating_category: row.rating_category,
            weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
        }));

        const allRatingsQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * br.weight_percent), 0) as total
      FROM etf_bond_ratings br
      JOIN asset_weights aw ON br.asset_id = aw.asset_id
    `;
        const totalResult = await pool.query(allRatingsQuery, [ids]);
        const allRatingsTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondRatings.reduce((sum, br) => sum + (br.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allRatingsTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondRatings.push({
                rating_category: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2))
            });
        }

        res.json({
            bondRatings,
            count: bondRatings.length,
            totalPercent: parseFloat((allRatingsTotal * 100).toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondRatingsByMultiplePortfolios:', err);
        res.status(500).json({ error: 'Errore nel calcolo rating obbligazionari multi-portafoglio' });
    }
}

async function getBondRatingsByMultipleAssets(req, res) {
    try {
        const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

        if (!assetIds) {
            return res.status(400).json({ error: 'assetIds query parameter richiesto' });
        }

        const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');
        const shouldExpand = expand === 'true' || expand === true;
        const queryLimit = shouldExpand ? null : parseInt(limit, 10);

        let query, params, allRatingsQuery, allParams;

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
          br.rating_category,
          SUM(aw.asset_weight * br.weight_percent) as real_weight
        FROM etf_bond_ratings br
        JOIN asset_weights aw ON br.asset_id = aw.asset_id
        WHERE br.rating_category NOT IN ('N/A', 'Not Rated', 'NR')
        GROUP BY br.rating_category
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
            params = [ids, portfolioId];

            allRatingsQuery = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          COALESCE(SUM(aw.asset_weight * br.weight_percent), 0) as total
        FROM etf_bond_ratings br
        JOIN asset_weights aw ON br.asset_id = aw.asset_id
      `;
            allParams = [ids, portfolioId];
        } else {
            query = `
        SELECT
          br.rating_category,
          AVG(br.weight_percent) as real_weight
        FROM etf_bond_ratings br
        WHERE br.asset_id = ANY($1)
          AND br.rating_category NOT IN ('N/A', 'Not Rated', 'NR')
        GROUP BY br.rating_category
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
            params = [ids];

            allRatingsQuery = `
        SELECT
          COALESCE(AVG(total_per_asset), 0) as total
        FROM (
          SELECT asset_id, SUM(weight_percent) as total_per_asset
          FROM etf_bond_ratings
          WHERE asset_id = ANY($1)
          GROUP BY asset_id
        ) t
      `;
            allParams = [ids];
        }

        const result = await pool.query(query, params);

        const bondRatings = result.rows.map(row => ({
            rating_category: row.rating_category,
            weighted_percent: parseFloat((row.real_weight * 100).toFixed(2))
        }));

        const totalResult = await pool.query(allRatingsQuery, allParams);
        const allRatingsTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondRatings.reduce((sum, br) => sum + (br.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allRatingsTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondRatings.push({
                rating_category: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2))
            });
        }

        res.json({
            bondRatings,
            count: bondRatings.length,
            totalPercent: parseFloat((allRatingsTotal * 100).toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondRatingsByMultipleAssets:', err);
        res.status(500).json({ error: 'Errore nel calcolo rating obbligazionari multi-asset' });
    }
}

async function saveManualBondRatings(req, res) {
    const client = await pool.connect();

    try {
        const { assetId } = req.params;
        const { bondRatings } = req.body;

        if (!bondRatings || !Array.isArray(bondRatings)) {
            return res.status(400).json({ error: 'bondRatings array richiesto' });
        }

        await client.query('BEGIN');
        await client.query('DELETE FROM etf_bond_ratings WHERE asset_id = $1', [assetId]);

        let inserted = 0;
        for (const rating of bondRatings) {
            await client.query(
                `INSERT INTO etf_bond_ratings (asset_id, rating_category, weight_percent)
         VALUES ($1, $2, $3)`,
                [assetId, rating.category, rating.percent / 100]
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

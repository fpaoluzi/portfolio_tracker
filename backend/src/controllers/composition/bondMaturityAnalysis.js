// ============================================
// BOND MATURITY ANALYSIS CONTROLLER
// Gestisce l'analisi della scadenza obbligazionaria (0-1y, 1-3y, 3-5y, etc.)
// LOGICA CORRETTA: Peso reale = Peso_Asset × Peso_Maturity
// SOLO PER OBBLIGAZIONI
// ============================================

const pool = require('../../config/database');

async function getBondMaturityByAsset(req, res) {
    try {
        const { assetId } = req.params;
        const { limit = 15 } = req.query;
        const queryLimit = parseInt(limit, 10);

        const maturityQuery = `
      SELECT 
        maturity_range,
        weight_percent,
        avg_duration_years
      FROM etf_bond_maturity
      WHERE asset_id = $1
      ORDER BY weight_percent DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

        const result = await pool.query(maturityQuery, [assetId]);

        const bondMaturity = result.rows.map(row => ({
            maturity_range: row.maturity_range,
            weighted_percent: parseFloat((row.weight_percent * 100).toFixed(2)),
            avg_duration_years: row.avg_duration_years ? parseFloat(row.avg_duration_years.toFixed(2)) : null
        }));

        const allMaturityQuery = `
      SELECT COALESCE(SUM(weight_percent), 0) as total
      FROM etf_bond_maturity
      WHERE asset_id = $1
    `;
        const totalResult = await pool.query(allMaturityQuery, [assetId]);
        const allMaturityTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondMaturity.reduce((sum, bm) => sum + (bm.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allMaturityTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondMaturity.push({
                maturity_range: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2)),
                avg_duration_years: null
            });
        }

        const avgDuration = bondMaturity.reduce((sum, row) => {
            const weight = parseFloat(row.weighted_percent || 0);
            const duration = parseFloat(row.avg_duration_years || 0);
            return sum + (weight * duration / 100);
        }, 0);

        res.json({
            bondMaturity,
            count: bondMaturity.length,
            totalPercent: parseFloat((allMaturityTotal * 100).toFixed(2)),
            avgDuration: parseFloat(avgDuration.toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondMaturityByAsset:', err);
        res.status(500).json({ error: 'Errore nel recupero maturity obbligazionaria' });
    }
}

async function getBondMaturityByPortfolio(req, res) {
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
        bm.maturity_range,
        SUM(aw.asset_weight * bm.weight_percent) as real_weight,
        AVG(bm.avg_duration_years) as avg_duration_years
      FROM etf_bond_maturity bm
      JOIN asset_weights aw ON bm.asset_id = aw.asset_id
      WHERE bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
      GROUP BY bm.maturity_range
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

        const result = await pool.query(query, [portfolioId]);

        const bondMaturity = result.rows.map(row => ({
            maturity_range: row.maturity_range,
            weighted_percent: parseFloat((row.real_weight * 100).toFixed(2)),
            avg_duration_years: row.avg_duration_years ? parseFloat(row.avg_duration_years.toFixed(2)) : null
        }));

        const allMaturityQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = $1
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * bm.weight_percent), 0) as total
      FROM etf_bond_maturity bm
      JOIN asset_weights aw ON bm.asset_id = aw.asset_id
    `;
        const totalResult = await pool.query(allMaturityQuery, [portfolioId]);
        const allMaturityTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondMaturity.reduce((sum, bm) => sum + (bm.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allMaturityTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondMaturity.push({
                maturity_range: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2)),
                avg_duration_years: null
            });
        }

        const avgDuration = bondMaturity.reduce((sum, row) => {
            const weight = parseFloat(row.weighted_percent || 0);
            const duration = parseFloat(row.avg_duration_years || 0);
            return sum + (weight * duration / 100);
        }, 0);

        res.json({
            bondMaturity,
            count: bondMaturity.length,
            totalPercent: parseFloat((allMaturityTotal * 100).toFixed(2)),
            avgDuration: parseFloat(avgDuration.toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondMaturityByPortfolio:', err);
        res.status(500).json({ error: 'Errore nel calcolo maturity obbligazionaria portafoglio' });
    }
}

async function getBondMaturityByMultiplePortfolios(req, res) {
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
        bm.maturity_range,
        SUM(aw.asset_weight * bm.weight_percent) as real_weight,
        AVG(bm.avg_duration_years) as avg_duration_years
      FROM etf_bond_maturity bm
      JOIN asset_weights aw ON bm.asset_id = aw.asset_id
      WHERE bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
      GROUP BY bm.maturity_range
      ORDER BY real_weight DESC
      ${queryLimit ? `LIMIT ${queryLimit}` : ''}
    `;

        const result = await pool.query(query, [ids]);

        const bondMaturity = result.rows.map(row => ({
            maturity_range: row.maturity_range,
            weighted_percent: parseFloat((row.real_weight * 100).toFixed(2)),
            avg_duration_years: row.avg_duration_years ? parseFloat(row.avg_duration_years.toFixed(2)) : null
        }));

        const allMaturityQuery = `
      WITH asset_weights AS (
        SELECT 
          asset_id,
          current_value / SUM(current_value) OVER() as asset_weight
        FROM v_current_positions
        WHERE portfolio_id = ANY($1)
      )
      SELECT
        COALESCE(SUM(aw.asset_weight * bm.weight_percent), 0) as total
      FROM etf_bond_maturity bm
      JOIN asset_weights aw ON bm.asset_id = aw.asset_id
    `;
        const totalResult = await pool.query(allMaturityQuery, [ids]);
        const allMaturityTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondMaturity.reduce((sum, bm) => sum + (bm.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allMaturityTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondMaturity.push({
                maturity_range: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2)),
                avg_duration_years: null
            });
        }

        const avgDuration = bondMaturity.reduce((sum, row) => {
            const weight = parseFloat(row.weighted_percent || 0);
            const duration = parseFloat(row.avg_duration_years || 0);
            return sum + (weight * duration / 100);
        }, 0);

        res.json({
            bondMaturity,
            count: bondMaturity.length,
            totalPercent: parseFloat((allMaturityTotal * 100).toFixed(2)),
            avgDuration: parseFloat(avgDuration.toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondMaturityByMultiplePortfolios:', err);
        res.status(500).json({ error: 'Errore nel calcolo maturity obbligazionaria multi-portafoglio' });
    }
}

async function getBondMaturityByMultipleAssets(req, res) {
    try {
        const { assetIds, portfolioId, expand = 'false', limit = 15 } = req.query;

        if (!assetIds) {
            return res.status(400).json({ error: 'assetIds query parameter richiesto' });
        }

        const ids = Array.isArray(assetIds) ? assetIds : assetIds.split(',');
        const shouldExpand = expand === 'true' || expand === true;
        const queryLimit = shouldExpand ? null : parseInt(limit, 10);

        let query, params, allMaturityQuery, allParams;

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
          bm.maturity_range,
          SUM(aw.asset_weight * bm.weight_percent) as real_weight,
          AVG(bm.avg_duration_years) as avg_duration_years
        FROM etf_bond_maturity bm
        JOIN asset_weights aw ON bm.asset_id = aw.asset_id
        WHERE bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
        GROUP BY bm.maturity_range
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
            params = [ids, portfolioId];

            allMaturityQuery = `
        WITH asset_weights AS (
          SELECT 
            asset_id,
            current_value / SUM(current_value) OVER() as asset_weight
          FROM v_current_positions
          WHERE portfolio_id = $2 AND asset_id = ANY($1)
        )
        SELECT
          COALESCE(SUM(aw.asset_weight * bm.weight_percent), 0) as total
        FROM etf_bond_maturity bm
        JOIN asset_weights aw ON bm.asset_id = aw.asset_id
      `;
            allParams = [ids, portfolioId];
        } else {
            query = `
        SELECT
          bm.maturity_range,
          AVG(bm.weight_percent) as real_weight,
          AVG(bm.avg_duration_years) as avg_duration_years
        FROM etf_bond_maturity bm
        WHERE bm.asset_id = ANY($1)
          AND bm.maturity_range NOT IN ('N/A', 'Unknown', 'Not Applicable')
        GROUP BY bm.maturity_range
        ORDER BY real_weight DESC
        ${queryLimit ? `LIMIT ${queryLimit}` : ''}
      `;
            params = [ids];

            allMaturityQuery = `
        SELECT
          COALESCE(AVG(total_per_asset), 0) as total
        FROM (
          SELECT asset_id, SUM(weight_percent) as total_per_asset
          FROM etf_bond_maturity
          WHERE asset_id = ANY($1)
          GROUP BY asset_id
        ) t
      `;
            allParams = [ids];
        }

        const result = await pool.query(query, params);

        const bondMaturity = result.rows.map(row => ({
            maturity_range: row.maturity_range,
            weighted_percent: parseFloat((row.real_weight * 100).toFixed(2)),
            avg_duration_years: row.avg_duration_years ? parseFloat(row.avg_duration_years.toFixed(2)) : null
        }));

        const totalResult = await pool.query(allMaturityQuery, allParams);
        const allMaturityTotal = parseFloat(totalResult.rows[0].total);

        const shownTotal = bondMaturity.reduce((sum, bm) => sum + (bm.weighted_percent / 100), 0);
        const othersPercent = Math.max(0, (allMaturityTotal - shownTotal) * 100);

        if (othersPercent > 0.01) {
            bondMaturity.push({
                maturity_range: 'Altri',
                weighted_percent: parseFloat(othersPercent.toFixed(2)),
                avg_duration_years: null
            });
        }

        const avgDuration = bondMaturity.reduce((sum, row) => {
            const weight = parseFloat(row.weighted_percent || 0);
            const duration = parseFloat(row.avg_duration_years || 0);
            return sum + (weight * duration / 100);
        }, 0);

        res.json({
            bondMaturity,
            count: bondMaturity.length,
            totalPercent: parseFloat((allMaturityTotal * 100).toFixed(2)),
            avgDuration: parseFloat(avgDuration.toFixed(2))
        });
    } catch (err) {
        console.error('Error in getBondMaturityByMultipleAssets:', err);
        res.status(500).json({ error: 'Errore nel calcolo maturity obbligazionaria multi-asset' });
    }
}

async function saveManualBondMaturity(req, res) {
    const client = await pool.connect();

    try {
        const { assetId } = req.params;
        const { bondMaturity } = req.body;

        if (!bondMaturity || !Array.isArray(bondMaturity)) {
            return res.status(400).json({ error: 'bondMaturity array richiesto' });
        }

        await client.query('BEGIN');
        await client.query('DELETE FROM etf_bond_maturity WHERE asset_id = $1', [assetId]);

        let inserted = 0;
        for (const maturity of bondMaturity) {
            await client.query(
                `INSERT INTO etf_bond_maturity (asset_id, maturity_range, weight_percent, avg_duration_years)
         VALUES ($1, $2, $3, $4)`,
                [assetId, maturity.range, maturity.percent / 100, maturity.duration || null]
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

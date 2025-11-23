const pool = require('../src/config/database');

const REGION_NAME_TRANSFORM = `
  CASE
    WHEN g.region_name IN ('United States', 'USA', 'US') THEN 'Stati Uniti'
    WHEN g.region_name IN ('United Kingdom', 'UK', 'Great Britain') THEN 'Regno Unito'
    WHEN g.region_name IN ('Japan') THEN 'Giappone'
    WHEN g.region_name IN ('China') THEN 'Cina'
    ELSE g.region_name
  END
`;

async function run() {
    try {
        const portfolioId = 'a5938c95-ba8e-46f6-98f2-4e670ba3b2a4';

        const query = `
      SELECT
        ${REGION_NAME_TRANSFORM} as region_name,
        SUM(g.normalized_percent * p.current_value) / NULLIF(SUM(p.current_value), 0) AS weighted_percent
      FROM v_etf_geographic_weights_normalized g
      JOIN v_current_positions p ON g.asset_id = p.asset_id
      WHERE p.portfolio_id = $1
      GROUP BY ${REGION_NAME_TRANSFORM}
      ORDER BY weighted_percent DESC
      LIMIT 5
    `;

        const result = await pool.query(query, [portfolioId]);
        console.log('Raw query results:');
        console.log(JSON.stringify(result.rows, null, 2));

        console.log('\nAfter *100:');
        result.rows.forEach(row => {
            console.log(`${row.region_name}: ${row.weighted_percent} -> ${(row.weighted_percent * 100).toFixed(2)}%`);
        });

    } catch (err) {
        console.error(err);
    } finally {
        pool.end();
    }
}

run();

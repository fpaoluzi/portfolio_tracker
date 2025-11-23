const pool = require('../src/config/database');

const createViewQuery = `
CREATE OR REPLACE VIEW public.v_portfolio_holdings_aggregated AS
SELECT
    ph.portfolio_id,
    ph.holding_symbol,
    MIN(ph.holding_name) AS holding_name,
    SUM(ph.holding_value_in_portfolio) AS total_holding_value,
    MAX(ph.total_portfolio_value) AS total_portfolio_value,
    (SUM(ph.holding_value_in_portfolio) / NULLIF(MAX(ph.total_portfolio_value), 0)) AS weighted_percent
FROM v_portfolio_holdings ph
GROUP BY ph.portfolio_id, ph.holding_symbol;
`;

async function run() {
    try {
        await pool.query(createViewQuery);
        console.log('View v_portfolio_holdings_aggregated created successfully.');
    } catch (err) {
        console.error('Error creating view:', err);
    } finally {
        pool.end();
    }
}

run();

const pool = require('../src/config/database');

const createViewsQuery = `
-- Portfolio-wide sector view
CREATE OR REPLACE VIEW public.v_portfolio_sectors AS
WITH portfolio_totals AS (
    SELECT
        portfolio_id,
        SUM(current_value) AS total_portfolio_value
    FROM v_current_positions
    GROUP BY portfolio_id
)
SELECT
    p.portfolio_id,
    p.asset_id,
    p.ticker AS etf_ticker,
    p.asset_name AS etf_name,
    p.current_value AS etf_value,
    s.sector_name,
    s.normalized_percent AS sector_weight_in_etf,
    (s.normalized_percent * p.current_value) AS sector_value_in_portfolio,
    pt.total_portfolio_value
FROM v_current_positions p
JOIN v_etf_sector_weights_normalized s ON p.asset_id = s.asset_id
JOIN portfolio_totals pt ON p.portfolio_id = pt.portfolio_id;

-- Portfolio-wide geographic view
CREATE OR REPLACE VIEW public.v_portfolio_geographic AS
WITH portfolio_totals AS (
    SELECT
        portfolio_id,
        SUM(current_value) AS total_portfolio_value
    FROM v_current_positions
    GROUP BY portfolio_id
)
SELECT
    p.portfolio_id,
    p.asset_id,
    p.ticker AS etf_ticker,
    p.asset_name AS etf_name,
    p.current_value AS etf_value,
    g.region_name,
    g.normalized_percent AS region_weight_in_etf,
    (g.normalized_percent * p.current_value) AS region_value_in_portfolio,
    pt.total_portfolio_value
FROM v_current_positions p
JOIN v_etf_geographic_weights_normalized g ON p.asset_id = g.asset_id
JOIN portfolio_totals pt ON p.portfolio_id = pt.portfolio_id;

-- Portfolio-wide allocation view
CREATE OR REPLACE VIEW public.v_portfolio_allocation AS
WITH portfolio_totals AS (
    SELECT
        portfolio_id,
        SUM(current_value) AS total_portfolio_value
    FROM v_current_positions
    GROUP BY portfolio_id
)
SELECT
    p.portfolio_id,
    p.asset_id,
    p.ticker AS etf_ticker,
    p.asset_name AS etf_name,
    p.current_value AS etf_value,
    a.allocation_type,
    a.normalized_percent AS allocation_weight_in_etf,
    (a.normalized_percent * p.current_value) AS allocation_value_in_portfolio,
    pt.total_portfolio_value
FROM v_current_positions p
JOIN v_etf_asset_allocation_normalized a ON p.asset_id = a.asset_id
JOIN portfolio_totals pt ON p.portfolio_id = pt.portfolio_id;
`;

async function run() {
    try {
        await pool.query(createViewsQuery);
        console.log('Portfolio-wide views created successfully.');
    } catch (err) {
        console.error('Error creating views:', err);
    } finally {
        pool.end();
    }
}

run();

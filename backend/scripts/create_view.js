const pool = require('../src/config/database');

const createViewQuery = `
CREATE OR REPLACE VIEW public.v_portfolio_holdings AS
WITH normalized_holdings AS (
    SELECT
        h.holding_id,
        h.asset_id,
        h.holding_symbol,
        h.holding_name,
        -- Normalize holding_percent: if > 1.5, assume percentage (0-100) and divide by 100. Else assume decimal (0-1).
        -- Result is always DECIMAL (0-1).
        CASE
            WHEN h.holding_percent > 1.5 THEN h.holding_percent / 100.0
            ELSE h.holding_percent
        END AS normalized_percent
    FROM etf_holdings h
),
portfolio_totals AS (
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
    h.holding_symbol,
    h.holding_name,
    h.normalized_percent AS holding_weight_in_etf,
    (h.normalized_percent * p.current_value) AS holding_value_in_portfolio,
    pt.total_portfolio_value
FROM v_current_positions p
JOIN normalized_holdings h ON p.asset_id = h.asset_id
JOIN portfolio_totals pt ON p.portfolio_id = pt.portfolio_id
WHERE h.holding_name NOT IN ('Altri', 'Other', 'Others', 'Altro')
  AND (h.holding_symbol IS NOT NULL AND h.holding_symbol != '');
`;

async function run() {
    try {
        await pool.query(createViewQuery);
        console.log('View v_portfolio_holdings created successfully.');
    } catch (err) {
        console.error('Error creating view:', err);
    } finally {
        pool.end();
    }
}

run();

const pool = require('../src/config/database');

const createViewQuery = `
CREATE OR REPLACE VIEW public.v_etf_holdings_normalized AS
SELECT
    h.holding_id,
    h.asset_id,
    h.holding_symbol,
    h.holding_name,
    h.rank_position,
    h.updated_at,
    -- Normalize holding_percent: if > 1.5, assume percentage (0-100) and divide by 100. Else assume decimal (0-1).
    -- Result is always DECIMAL (0-1).
    CASE
        WHEN h.holding_percent > 1.5 THEN h.holding_percent / 100.0
        ELSE h.holding_percent
    END AS normalized_percent
FROM etf_holdings h;
`;

async function run() {
    try {
        await pool.query(createViewQuery);
        console.log('View v_etf_holdings_normalized created successfully.');
    } catch (err) {
        console.error('Error creating view:', err);
    } finally {
        pool.end();
    }
}

run();

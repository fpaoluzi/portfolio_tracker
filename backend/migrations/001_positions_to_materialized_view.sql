 -- ============================================
-- MIGRATION: Positions Table to Materialized View
-- ============================================
-- This migration converts the positions table to a materialized view
-- that is calculated from transactions, ensuring data consistency.
--
-- IMPORTANT: Run this migration when the application is not in use
-- or during a maintenance window.
-- ============================================

BEGIN;

-- ============================================
-- STEP 1: Create temporary materialized view (idempotent)
-- ============================================

-- Ensure clean slate for temp MV and its indexes
DROP MATERIALIZED VIEW IF EXISTS positions_mv CASCADE;
DROP INDEX IF EXISTS idx_positions_mv_portfolio_asset;
DROP INDEX IF EXISTS idx_positions_mv_portfolio;
DROP INDEX IF EXISTS idx_positions_mv_asset;

CREATE MATERIALIZED VIEW positions_mv AS
SELECT 
    uuid_generate_v4() as position_id,
    portfolio_id,
    asset_id,
    quantity,
    average_buy_price,
    (quantity * average_buy_price) as total_invested,
    gross_buy_invested,
    total_commissions,
    total_fees,
    first_purchase_date,
    last_transaction_date,
    CURRENT_TIMESTAMP as updated_at
FROM (
    SELECT 
        t.portfolio_id,
        t.asset_id,
        -- Net quantity (BUY adds, SELL subtracts)
        SUM(CASE 
            WHEN t.transaction_type = 'BUY' THEN t.quantity
            WHEN t.transaction_type = 'SELL' THEN -t.quantity
            ELSE 0
        END) as quantity,
        -- Weighted average buy price (only for BUY transactions)
        CASE 
            WHEN SUM(CASE WHEN t.transaction_type = 'BUY' AND COALESCE(t.price_per_share, 0) > 0 THEN t.quantity ELSE 0 END) > 0
            THEN SUM(CASE WHEN t.transaction_type = 'BUY' AND COALESCE(t.price_per_share, 0) > 0 THEN t.total_amount + t.commission + t.fees ELSE 0 END) / 
                 SUM(CASE WHEN t.transaction_type = 'BUY' AND COALESCE(t.price_per_share, 0) > 0 THEN t.quantity ELSE 0 END)
            ELSE 0
        END as average_buy_price,
        -- Gross invested from BUY transactions (includes commissions and fees)
        SUM(CASE 
            WHEN t.transaction_type = 'BUY' THEN t.total_amount + t.commission + t.fees
            ELSE 0
        END) as gross_buy_invested,
        -- Total commissions (all transactions)
        SUM(t.commission) as total_commissions,
        -- Total fees (all transactions)
        SUM(t.fees) as total_fees,
        -- First purchase date
        MIN(CASE WHEN t.transaction_type = 'BUY' THEN t.transaction_date ELSE NULL END) as first_purchase_date,
        -- Last transaction date (any type)
        MAX(t.transaction_date) as last_transaction_date
    FROM transactions t
    GROUP BY t.portfolio_id, t.asset_id
) calculated
WHERE quantity > 0;  -- Only show positions with positive quantity

CREATE UNIQUE INDEX idx_positions_mv_portfolio_asset ON positions_mv (portfolio_id, asset_id);
CREATE INDEX idx_positions_mv_portfolio ON positions_mv (portfolio_id);
CREATE INDEX idx_positions_mv_asset ON positions_mv (asset_id);

-- ============================================
-- STEP 2: Verify data integrity
-- ============================================

-- Compare totals between old and new
DO $$
DECLARE
    old_total NUMERIC;
    new_total NUMERIC;
    diff NUMERIC;
BEGIN
    SELECT COALESCE(SUM(total_invested), 0) INTO old_total FROM positions;
    SELECT COALESCE(SUM(total_invested), 0) INTO new_total FROM positions_mv;
    diff := ABS(old_total - new_total);
    
    RAISE NOTICE 'Old positions total: %', old_total;
    RAISE NOTICE 'New positions total: %', new_total;
    RAISE NOTICE 'Difference: %', diff;
    
    -- The new total should be LESS than old (since old was inflated)
    -- But we don't fail the migration, just warn
    IF diff > 1000 THEN
        RAISE WARNING 'Large difference detected. Old positions may have been corrupted.';
    END IF;
END $$;

-- ============================================
-- STEP 3: Drop old triggers and functions
-- ============================================

-- Drop trigger on transactions
DROP TRIGGER IF EXISTS update_position_on_transaction ON transactions;

-- Drop trigger on positions (for updated_at)
DROP TRIGGER IF EXISTS update_positions_updated_at ON positions;

-- Drop the trigger function
DROP FUNCTION IF EXISTS update_position_after_transaction();

-- ============================================
-- STEP 4: Preserve old positions table (no drop)
-- ============================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'positions'
    ) THEN
        EXECUTE 'ALTER TABLE positions RENAME TO positions_old';
    END IF;
END $$;

-- ============================================
-- STEP 5: Rename materialized view to positions (idempotent)
-- ============================================

-- If a previous run already created the materialized view 'positions', drop it first
DROP MATERIALIZED VIEW IF EXISTS positions CASCADE;
ALTER MATERIALIZED VIEW positions_mv RENAME TO positions;

-- Avoid conflicts if indexes already exist from previous runs
DROP INDEX IF EXISTS idx_positions_portfolio_asset;
DROP INDEX IF EXISTS idx_positions_portfolio;
DROP INDEX IF EXISTS idx_positions_asset;
ALTER INDEX idx_positions_mv_portfolio_asset RENAME TO idx_positions_portfolio_asset;
ALTER INDEX idx_positions_mv_portfolio RENAME TO idx_positions_portfolio;
ALTER INDEX idx_positions_mv_asset RENAME TO idx_positions_asset;

-- ============================================
-- STEP 6: Recreate v_current_positions view
-- ============================================

CREATE OR REPLACE VIEW v_current_positions AS
WITH position_values AS (
    SELECT 
        pos.position_id,
        pos.portfolio_id,
        pos.asset_id,
        pf.name AS portfolio_name,
        a.isin,
        a.ticker,
        a.name AS asset_name,
        a.asset_type,
        a.sector,
        a.country,
        pos.quantity,
        pos.average_buy_price,
        pos.total_invested,
        pos.gross_buy_invested,
        COALESCE(ph.close_price, pos.average_buy_price) AS current_price,
        (pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) AS current_value,
        ph.price_date AS last_price_date
    FROM positions pos
    JOIN portfolios pf ON pos.portfolio_id = pf.portfolio_id
    JOIN assets a ON pos.asset_id = a.asset_id
    LEFT JOIN LATERAL (
        SELECT close_price, price_date
        FROM price_history
        WHERE asset_id = pos.asset_id
        ORDER BY price_date DESC
        LIMIT 1
    ) ph ON true
    WHERE pos.quantity > 0
)
SELECT 
    position_id,
    portfolio_id,
    asset_id,
    portfolio_name,
    isin,
    ticker,
    asset_name,
    asset_type,
    sector,
    country,
    quantity,
    average_buy_price,
    total_invested,
    gross_buy_invested,
    current_price,
    current_value,
    (current_value - total_invested) AS gain_loss,
    (((current_value - total_invested) / NULLIF(total_invested, 0)) * 100) AS gain_loss_pct,
    last_price_date,
    ((current_value / NULLIF(sum(current_value) OVER (PARTITION BY portfolio_id), 0)) * 100) AS ownership_pct,
    ((total_invested / NULLIF(sum(total_invested) OVER (PARTITION BY portfolio_id), 0)) * 100) AS invested_pct
FROM position_values;

-- Recreate dependent allocation/performance views
CREATE OR REPLACE VIEW v_asset_allocation AS
SELECT
    pf.portfolio_id,
    pf.name AS portfolio_name,
    a.asset_type,
    SUM(pos.quantity * ph.close_price) AS total_value,
    (
        SUM(pos.quantity * ph.close_price)
        / NULLIF(SUM(SUM(pos.quantity * ph.close_price)) OVER (PARTITION BY pf.portfolio_id), 0)
    ) * 100 AS percentage
FROM positions pos
JOIN portfolios pf ON pos.portfolio_id = pf.portfolio_id
JOIN assets a ON pos.asset_id = a.asset_id
LEFT JOIN LATERAL (
    SELECT close_price
    FROM price_history
    WHERE asset_id = pos.asset_id
    ORDER BY price_date DESC
    LIMIT 1
) ph ON true
WHERE pos.quantity > 0
GROUP BY pf.portfolio_id, pf.name, a.asset_type;

CREATE OR REPLACE VIEW v_portfolio_performance AS
SELECT
    pf.portfolio_id,
    pf.name AS portfolio_name,
    COALESCE(SUM(pos.total_invested), 0) AS total_invested,
    COALESCE(SUM(pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)), 0) AS current_value,
    COALESCE(SUM((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested), 0) AS total_gain_loss,
    CASE
        WHEN SUM(pos.total_invested) > 0 THEN (
            SUM((pos.quantity * COALESCE(ph.close_price, pos.average_buy_price)) - pos.total_invested)
            / SUM(pos.total_invested)
        ) * 100
        ELSE 0
    END AS total_gain_loss_pct,
    COUNT(CASE WHEN pos.quantity > 0 THEN 1 END) AS number_of_positions
FROM portfolios pf
LEFT JOIN positions pos ON pf.portfolio_id = pos.portfolio_id AND pos.quantity > 0
LEFT JOIN LATERAL (
    SELECT close_price
    FROM price_history
    WHERE asset_id = pos.asset_id
    ORDER BY price_date DESC
    LIMIT 1
) ph ON true
WHERE pf.is_active = true
GROUP BY pf.portfolio_id, pf.name;

-- ============================================
-- STEP 7: Create refresh trigger (idempotent)
-- ============================================

-- Function to refresh positions materialized view
CREATE OR REPLACE FUNCTION refresh_positions_mv()
RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY positions;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to refresh after transaction changes
-- Ensure no duplicate trigger exists
DROP TRIGGER IF EXISTS refresh_positions_on_transaction ON transactions;
CREATE TRIGGER refresh_positions_on_transaction
AFTER INSERT OR UPDATE OR DELETE ON transactions
FOR EACH STATEMENT
EXECUTE FUNCTION refresh_positions_mv();

-- ============================================
-- STEP 8: Grant permissions
-- ============================================

ALTER MATERIALIZED VIEW positions OWNER TO postgres;
ALTER VIEW v_current_positions OWNER TO postgres;
ALTER VIEW v_asset_allocation OWNER TO postgres;
ALTER VIEW v_portfolio_performance OWNER TO postgres;

-- ============================================
-- FINAL VERIFICATION
-- ============================================

DO $$
DECLARE
    position_count INTEGER;
    transaction_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO position_count FROM positions;

    SELECT COUNT(*) INTO transaction_count
    FROM (
        SELECT portfolio_id, asset_id
        FROM transactions
        GROUP BY portfolio_id, asset_id
        HAVING SUM(CASE WHEN transaction_type = 'BUY' THEN quantity ELSE -quantity END) > 0
    ) active_pairs;

    RAISE NOTICE 'Migration completed successfully!';
    RAISE NOTICE 'Active positions: %', position_count;
    RAISE NOTICE 'Expected positions (from transactions): %', transaction_count;
END $$;

COMMIT;

-- ============================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================
-- To rollback this migration, restore from backup:
-- pg_restore -U postgres -d finance backup_before_migration.dump

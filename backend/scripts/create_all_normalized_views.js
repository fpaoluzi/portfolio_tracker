const pool = require('../src/config/database');

const createViewsQuery = `
-- Sectors
CREATE OR REPLACE VIEW public.v_etf_sector_weights_normalized AS
SELECT
    s.sector_weight_id,
    s.asset_id,
    s.sector_name,
    s.updated_at,
    CASE
        WHEN s.weight_percent > 1.5 THEN s.weight_percent / 100.0
        ELSE s.weight_percent
    END AS normalized_percent
FROM etf_sector_weights s;

-- Geography
CREATE OR REPLACE VIEW public.v_etf_geographic_weights_normalized AS
SELECT
    g.geographic_weight_id,
    g.asset_id,
    g.region_name,
    g.updated_at,
    CASE
        WHEN g.weight_percent > 1.5 THEN g.weight_percent / 100.0
        ELSE g.weight_percent
    END AS normalized_percent
FROM etf_geographic_weights g;

-- Allocation
CREATE OR REPLACE VIEW public.v_etf_asset_allocation_normalized AS
SELECT
    a.asset_allocation_id,
    a.asset_id,
    a.allocation_type,
    a.updated_at,
    CASE
        WHEN a.weight_percent > 1.5 THEN a.weight_percent / 100.0
        ELSE a.weight_percent
    END AS normalized_percent
FROM etf_asset_allocation a;

-- Bond Ratings
CREATE OR REPLACE VIEW public.v_etf_bond_ratings_normalized AS
SELECT
    b.bond_rating_id,
    b.asset_id,
    b.rating_category,
    b.updated_at,
    CASE
        WHEN b.weight_percent > 1.5 THEN b.weight_percent / 100.0
        ELSE b.weight_percent
    END AS normalized_percent
FROM etf_bond_ratings b;

-- Bond Maturity
CREATE OR REPLACE VIEW public.v_etf_bond_maturity_normalized AS
SELECT
    m.bond_maturity_id,
    m.asset_id,
    m.maturity_range,
    m.avg_duration_years,
    m.updated_at,
    CASE
        WHEN m.weight_percent > 1.5 THEN m.weight_percent / 100.0
        ELSE m.weight_percent
    END AS normalized_percent
FROM etf_bond_maturity m;
`;

async function run() {
    try {
        await pool.query(createViewsQuery);
        console.log('All normalized views created successfully.');
    } catch (err) {
        console.error('Error creating views:', err);
    } finally {
        pool.end();
    }
}

run();

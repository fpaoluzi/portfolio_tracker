/**
 * Fix weight_percent values that are 100x too small.
 *
 * Root cause: The Ollama extraction returns fractions (0.245 = 24.5%),
 * but the etfCompositionController divides by 100 again on insert,
 * resulting in values like 0.00245 instead of 0.245.
 *
 * This script multiplies weight_percent by 100 for assets where
 * the total sum is too small (< 0.05), indicating double-division.
 */

const pool = require('../src/config/database');

const TABLES = [
  { table: 'etf_sector_weights', col: 'weight_percent', idCol: 'sector_weight_id' },
  { table: 'etf_geographic_weights', col: 'weight_percent', idCol: 'geographic_weight_id' },
  { table: 'etf_asset_allocation', col: 'weight_percent', idCol: 'asset_allocation_id' },
  { table: 'etf_bond_ratings', col: 'weight_percent', idCol: 'bond_rating_id' },
  { table: 'etf_bond_maturity', col: 'weight_percent', idCol: 'bond_maturity_id' },
];

const HOLDINGS_TABLE = {
  table: 'etf_holdings', col: 'holding_percent', idCol: 'holding_id'
};

async function fixTable({ table, col, idCol }) {
  // Find assets where total weight is too small (< 0.05 = 5%)
  const assetQuery = `
    SELECT asset_id, SUM(${col}) as total
    FROM ${table}
    GROUP BY asset_id
    HAVING SUM(${col}) > 0 AND SUM(${col}) < 0.05
  `;

  const assets = await pool.query(assetQuery);

  if (assets.rows.length === 0) {
    console.log(`  ${table}: No assets need fixing`);
    return 0;
  }

  const assetIds = assets.rows.map(r => r.asset_id);
  console.log(`  ${table}: Fixing ${assetIds.length} assets (total sums: ${assets.rows.map(r => parseFloat(r.total).toFixed(4)).join(', ')})`);

  // Multiply by 100, capping at 1.0 to respect CHECK constraint
  const updateQuery = `
    UPDATE ${table}
    SET ${col} = LEAST(${col} * 100, 1.0)
    WHERE asset_id = ANY($1)
  `;

  const result = await pool.query(updateQuery, [assetIds]);
  console.log(`  ${table}: Updated ${result.rowCount} rows`);
  return result.rowCount;
}

async function main() {
  console.log('=== Fix weight_percent double-division bug ===\n');

  let totalFixed = 0;

  // Fix weight_percent tables
  for (const tableInfo of TABLES) {
    totalFixed += await fixTable(tableInfo);
  }

  // Fix holdings (holding_percent)
  totalFixed += await fixTable(HOLDINGS_TABLE);

  console.log(`\n=== Done. Total rows updated: ${totalFixed} ===`);

  // Verify by checking a known ETF (SWDA)
  const verify = await pool.query(`
    SELECT sector_name, weight_percent
    FROM etf_sector_weights
    WHERE asset_id = (SELECT asset_id FROM assets WHERE ticker = 'SWDA.MI' LIMIT 1)
    ORDER BY weight_percent DESC
    LIMIT 5
  `);

  if (verify.rows.length > 0) {
    console.log('\nVerification (SWDA sectors):');
    for (const row of verify.rows) {
      console.log(`  ${row.sector_name}: ${(row.weight_percent * 100).toFixed(1)}%`);
    }
  }

  await pool.end();
}

main().catch(err => {
  console.error('Error:', err);
  pool.end();
  process.exit(1);
});

const pool = require('../src/config/database');

async function main() {
  console.log("=== Fixing accent normalization ===\n");

  const fixes = [
    ['etf_sector_weights', 'sector_name', 'Beni di prima necessita', 'Beni di prima necessità'],
    ['etf_sector_weights', 'sector_name', 'Servizi di pubblica utilita', 'Servizi di pubblica utilità'],
  ];

  for (const [table, col, from, to] of fixes) {
    const result = await pool.query(
      `UPDATE ${table} SET ${col} = $1 WHERE ${col} = $2`,
      [to, from]
    );
    if (result.rowCount > 0) {
      console.log(`  "${from}" -> "${to}": ${result.rowCount} rows`);
    }
  }

  // Verify unique sector names
  const sectors = await pool.query(
    'SELECT DISTINCT sector_name, COUNT(*) as cnt FROM etf_sector_weights GROUP BY sector_name ORDER BY sector_name'
  );
  console.log("\nUnique sector names:");
  for (const row of sectors.rows) {
    console.log(`  ${row.sector_name} (${row.cnt})`);
  }

  await pool.end();
}

main().catch(err => {
  console.error("Error:", err);
  pool.end();
  process.exit(1);
});

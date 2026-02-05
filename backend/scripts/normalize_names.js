
const pool = require('../src/config/database');

const SECTOR_MAP = {
  "Information Technology": "Informatica",
  "Financials": "Finanza",
  "Health Care": "Salute",
  "Consumer Discretionary": "Beni voluttuari",
  "Consumer Staples": "Beni di prima necessita",
  "Communication Services": "Telecomunicazioni",
  "Industrials": "Industria",
  "Materials": "Materie prime",
  "Energy": "Energia",
  "Utilities": "Servizi di pubblica utilita",
  "Real Estate": "Immobiliare",
};

const GEO_MAP = {
  "United States": "Stati Uniti",
  "United Kingdom": "Regno Unito",
  "Japan": "Giappone",
  "China": "Cina",
  "Netherlands": "Paesi Bassi",
  "Germany": "Germania",
  "France": "Francia",
  "Switzerland": "Svizzera",
  "Others": "Altri",
};

async function main() {
  console.log("=== Normalizing sector names to Italian ===\n");

  let totalUpdated = 0;

  // Normalize sectors
  for (const [eng, ita] of Object.entries(SECTOR_MAP)) {
    const result = await pool.query(
      'UPDATE etf_sector_weights SET sector_name = $1 WHERE sector_name = $2',
      [ita, eng]
    );
    if (result.rowCount > 0) {
      console.log("  " + eng + " -> " + ita + ": " + result.rowCount + " rows");
      totalUpdated += result.rowCount;
    }
  }

  // Normalize geographic
  for (const [eng, ita] of Object.entries(GEO_MAP)) {
    const result = await pool.query(
      'UPDATE etf_geographic_weights SET region_name = $1 WHERE region_name = $2',
      [ita, eng]
    );
    if (result.rowCount > 0) {
      console.log("  " + eng + " -> " + ita + ": " + result.rowCount + " rows");
      totalUpdated += result.rowCount;
    }
  }

  console.log("\nTotal rows updated: " + totalUpdated);

  // Verify: list unique sector names
  const sectors = await pool.query(
    'SELECT DISTINCT sector_name, COUNT(*) as cnt FROM etf_sector_weights GROUP BY sector_name ORDER BY sector_name'
  );
  console.log("\nUnique sector names after normalization:");
  for (const row of sectors.rows) {
    console.log("  " + row.sector_name + " (" + row.cnt + " entries)");
  }

  await pool.end();
}

main().catch(err => {
  console.error("Error:", err);
  pool.end();
  process.exit(1);
});

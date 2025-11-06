// ============================================
// IMPORT SCRIPT - Excel to PostgreSQL
// ============================================

const { Pool } = require('pg');
const XLSX = require('xlsx');
const fs = require('fs');

const pool = new Pool({
  host: 'localhost',
  port: 5432,
  database: 'finance',
  user: 'postgres',
  password: 'postgres',
});

function parseExcelDate(excelDate) {
  if (!excelDate) return null;
  if (excelDate instanceof Date) return excelDate.toISOString().split('T')[0];
  const date = new Date((excelDate - 25569) * 86400 * 1000);
  return date.toISOString().split('T')[0];
}

function cleanString(str) {
  if (!str) return null;
  return str.toString().trim();
}

function cleanNumber(num) {
  if (!num || num === '') return 0;
  if (typeof num === 'string') {
    return parseFloat(num.replace(',', '.'));
  }
  return parseFloat(num);
}

async function importPortfolios() {
  console.log('📁 Importazione Portafogli...');
  
  try {
    await pool.query(
      `INSERT INTO portfolios (name, broker, currency)
       VALUES ($1, $2, $3)
       ON CONFLICT (name) DO NOTHING`,
      ['Portafoglio Fineco', 'FinecoBank', 'EUR']
    );
    
    await pool.query(
      `INSERT INTO portfolios (name, broker, currency)
       VALUES ($1, $2, $3)
       ON CONFLICT (name) DO NOTHING`,
      ['Portafoglio ING', 'ING Direct', 'EUR']
    );
    
    console.log('✅ Portafogli importati');
  } catch (err) {
    console.error('❌ Errore import portafogli:', err.message);
  }
}

async function importAssets(excelPath) {
  console.log('📊 Importazione Asset...');
  
  try {
    const assets = [
      { isin: 'IE00B5BMR087', name: 'iShares Core S&P 500 UCITS ETF', type: 'Azionario', sector: 'Tecnologia', country: 'USA', region: 'Nord America', benchmark: 'S&P 500' },
      { isin: 'LU1829221024', name: 'Amundi Nasdaq-100 UCITS ETF', type: 'Azionario', sector: 'Tecnologia', country: 'USA', region: 'Nord America', benchmark: 'NASDAQ 100' },
      { isin: 'IE00B4L5Y983', name: 'iShares Core MSCI World UCITS ETF', type: 'Azionario', sector: 'Diversificato', country: 'Global', region: 'Global', benchmark: 'MSCI World' },
      { isin: 'IE00BJQRDN15', name: 'Invesco Quantitative Strategies Global Equity', type: 'Azionario', sector: 'Diversificato', country: 'Global', region: 'Global', benchmark: 'MSCI World' },
      { isin: 'IE00BP3QZ825', name: 'iShares Core STOXX Europe 600 UCITS ETF', type: 'Azionario', sector: 'Diversificato', country: 'Europa', region: 'Europa', benchmark: 'STOXX 600' },
      { isin: 'LU2090063673', name: 'Amundi Japan TOPIX UCITS ETF', type: 'Azionario', sector: 'Diversificato', country: 'Giappone', region: 'Asia', benchmark: 'TOPIX' },
      { isin: 'IE00BGYWFS63', name: 'Vanguard USD Treasury Bond UCITS ETF', type: 'Obbligazionario', sector: 'Obbligazioni Gov', country: 'USA', region: 'Nord America', benchmark: 'US Treasury' },
      { isin: 'LU0378434582', name: 'Amundi Euro Government Bond 1-3Y', type: 'Obbligazionario', sector: 'Obbligazioni Gov', country: 'Europa', region: 'Europa', benchmark: 'Euro Gov 1-3Y' },
      { isin: 'LU0484968812', name: 'Amundi Euro Government Bond 7-10Y', type: 'Obbligazionario', sector: 'Obbligazioni Gov', country: 'Europa', region: 'Europa', benchmark: 'Euro Gov 7-10Y' },
      { isin: 'IE00B579F325', name: 'Invesco Physical Gold ETC', type: 'Oro', sector: 'Metalli Preziosi', country: 'Global', region: 'Global', benchmark: 'Gold Spot' },
      { isin: 'LU0290358497', name: 'Xtrackers EUR Overnight Rate Swap UCITS ETF', type: 'Monetario', sector: 'Cash', country: 'Europa', region: 'Europa', benchmark: 'ESTR' },
    ];
    
    for (const asset of assets) {
      await pool.query(
        `INSERT INTO assets (
          isin, name, asset_type, sector, country, region, benchmark_index, currency
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (isin) DO UPDATE SET
          name = EXCLUDED.name,
          asset_type = EXCLUDED.asset_type,
          sector = EXCLUDED.sector,
          country = EXCLUDED.country,
          region = EXCLUDED.region`,
        [asset.isin, asset.name, asset.type, asset.sector, asset.country, asset.region, asset.benchmark, 'EUR']
      );
    }
    
    console.log(`✅ ${assets.length} asset importati`);
  } catch (err) {
    console.error('❌ Errore import asset:', err.message);
  }
}

async function importTransactions(excelPath) {
  console.log('💸 Importazione Transazioni...');
  
  try {
    const workbook = XLSX.readFile(excelPath);
    const sheet = workbook.Sheets['Storico Ordini'];
    const data = XLSX.utils.sheet_to_json(sheet);
    
    const portfolioResult = await pool.query(
      "SELECT portfolio_id FROM portfolios WHERE name = 'Portafoglio Fineco'"
    );
    const portfolio_id = portfolioResult.rows[0].portfolio_id;
    
    let imported = 0;
    
    for (const row of data) {
      if (!row.Isin || !row['Data valuta']) continue;
      
      const assetResult = await pool.query(
        'SELECT asset_id FROM assets WHERE isin = $1',
        [cleanString(row.Isin)]
      );
      
      if (assetResult.rows.length === 0) {
        console.log(`⚠️  Asset non trovato: ${row.Isin}`);
        continue;
      }
      
      const asset_id = assetResult.rows[0].asset_id;
      const transaction_date = parseExcelDate(row['Data valuta']);
      const transaction_type = row.Segno === 'A' ? 'BUY' : 'SELL';
      const quantity = cleanNumber(row.Quantita);
      const price = cleanNumber(row.Prezzo);
      const total = cleanNumber(row.Controvalore);
      const commission = cleanNumber(row['Commissioni amministrato']) || 0;
      
      try {
        await pool.query(
          `INSERT INTO transactions (
            portfolio_id, asset_id, transaction_type, transaction_date,
            quantity, price_per_share, total_amount, commission, currency
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
          [portfolio_id, asset_id, transaction_type, transaction_date,
           quantity, price, total, commission, 'EUR']
        );
        imported++;
      } catch (err) {
        console.log(`⚠️  Errore transazione: ${err.message}`);
      }
    }
    
    console.log(`✅ ${imported} transazioni importate`);
  } catch (err) {
    console.error('❌ Errore import transazioni:', err.message);
  }
}

async function importCurrentPrices() {
  console.log('💰 Importazione Prezzi Correnti...');
  
  try {
    const today = new Date().toISOString().split('T')[0];
    
    const prices = {
      'IE00B5BMR087': 624.50,
      'LU1829221024': 85.30,
      'IE00B4L5Y983': 108.75,
      'IE00BJQRDN15': 79.20,
      'IE00BP3QZ825': 101.45,
      'LU2090063673': 78.90,
      'IE00BGYWFS63': 25.10,
      'LU0378434582': 115.20,
      'LU0484968812': 132.80,
      'IE00B579F325': 268.40,
      'LU0290358497': 147.35,
    };
    
    for (const [isin, price] of Object.entries(prices)) {
      const assetResult = await pool.query(
        'SELECT asset_id FROM assets WHERE isin = $1',
        [isin]
      );
      
      if (assetResult.rows.length > 0) {
        const asset_id = assetResult.rows[0].asset_id;
        
        await pool.query(
          `INSERT INTO price_history (asset_id, price_date, close_price, data_source)
           VALUES ($1, $2, $3, 'MANUAL')
           ON CONFLICT (asset_id, price_date) 
           DO UPDATE SET close_price = EXCLUDED.close_price`,
          [asset_id, today, price]
        );
      }
    }
    
    console.log(`✅ ${Object.keys(prices).length} prezzi importati`);
  } catch (err) {
    console.error('❌ Errore import prezzi:', err.message);
  }
}

async function generateHistoricalPrices() {
  console.log('📈 Generazione Storico Prezzi (ultimi 12 mesi)...');
  
  try {
    const assets = await pool.query('SELECT asset_id, isin FROM assets');
    
    const basePrice = {
      'IE00B5BMR087': 580,
      'LU1829221024': 75,
      'IE00B4L5Y983': 95,
      'IE00BJQRDN15': 70,
      'IE00BP3QZ825': 90,
      'LU2090063673': 70,
      'IE00BGYWFS63': 23,
      'LU0378434582': 110,
      'LU0484968812': 125,
      'IE00B579F325': 230,
      'LU0290358497': 145,
    };
    
    let totalInserted = 0;
    
    for (const asset of assets.rows) {
      const startPrice = basePrice[asset.isin] || 100;
      
      for (let i = 365; i >= 0; i--) {
        const date = new Date();
        date.setDate(date.getDate() - i);
        const dateStr = date.toISOString().split('T')[0];
        
        const dayVariation = (Math.random() - 0.5) * 0.02;
        const trendGrowth = (365 - i) / 365 * 0.08;
        const price = startPrice * (1 + trendGrowth + dayVariation);
        
        await pool.query(
          `INSERT INTO price_history (asset_id, price_date, close_price, data_source)
           VALUES ($1, $2, $3, 'GENERATED')
           ON CONFLICT (asset_id, price_date) DO NOTHING`,
          [asset.asset_id, dateStr, price.toFixed(2)]
        );
        totalInserted++;
      }
    }
    
    console.log(`✅ ${totalInserted} prezzi storici generati`);
  } catch (err) {
    console.error('❌ Errore generazione storico:', err.message);
  }
}

async function createSnapshots() {
  console.log('📸 Creazione Snapshot Storici...');
  
  try {
    const portfolioResult = await pool.query(
      "SELECT portfolio_id FROM portfolios WHERE name = 'Portafoglio Fineco'"
    );
    const portfolio_id = portfolioResult.rows[0].portfolio_id;
    
    for (let i = 90; i >= 0; i--) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      const dateStr = date.toISOString().split('T')[0];
      
      try {
        await pool.query(
          'SELECT create_daily_snapshot($1, $2)',
          [portfolio_id, dateStr]
        );
      } catch (err) {
        // Ignora errori
      }
    }
    
    console.log('✅ Snapshot storici creati');
  } catch (err) {
    console.error('❌ Errore creazione snapshot:', err.message);
  }
}

async function importTargetAllocations() {
  console.log('🎯 Importazione Target Allocation...');
  
  try {
    const portfolioResult = await pool.query(
      "SELECT portfolio_id FROM portfolios WHERE name = 'Portafoglio Fineco'"
    );
    const portfolio_id = portfolioResult.rows[0].portfolio_id;
    
    await pool.query(
      `INSERT INTO target_allocations (
        portfolio_id, allocation_name, 
        target_azionario, target_obbligazionario, target_monetario, target_oro
      ) VALUES ($1, $2, $3, $4, $5, $6)
      ON CONFLICT DO NOTHING`,
      [portfolio_id, 'Target Standard', 65.0, 15.0, 8.0, 12.0]
    );
    
    console.log('✅ Target allocation importato');
  } catch (err) {
    console.error('❌ Errore import target:', err.message);
  }
}

async function runImport(excelPath) {
  console.log(`
╔═══════════════════════════════════════════╗
║   PORTFOLIO IMPORT SCRIPT                 ║
║   Excel → PostgreSQL                      ║
╚═══════════════════════════════════════════╝
  `);
  
  try {
    await pool.query('SELECT NOW()');
    console.log('✅ Connesso a PostgreSQL\n');
    
    await importPortfolios();
    await importAssets(excelPath);
    await importTransactions(excelPath);
    await importCurrentPrices();
    await generateHistoricalPrices();
    await importTargetAllocations();
    await createSnapshots();
    
    console.log(`
╔═══════════════════════════════════════════╗
║   ✅ IMPORT COMPLETATO CON SUCCESSO!     ║
╚═══════════════════════════════════════════╝

Prossimi step:
1. Avvia il server API: node server.js
2. Testa le API: http://localhost:3001/api/health
    `);
    
  } catch (err) {
    console.error('\n❌ ERRORE:', err.message);
    console.error(err.stack);
  } finally {
    await pool.end();
    console.log('\n👋 Connessione database chiusa');
  }
}

if (require.main === module) {
  const excelPath = process.argv[2] || './Investment.xlsm';
  
  if (!fs.existsSync(excelPath)) {
    console.error(`❌ File non trovato: ${excelPath}`);
    console.log('\nUso: node import.js <percorso-file-excel>');
    process.exit(1);
  }
  
  runImport(excelPath);
}

module.exports = { runImport };
